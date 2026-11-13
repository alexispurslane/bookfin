import 'dart:io';
import 'dart:typed_data';

import '../catalog/model.dart';
import '../downloads/downloads.dart';
import '../speech/book_search.dart';
import '../speech/book_words.dart';
import '../sync/device.dart';
import 'admitted_books.dart';
import 'document.dart';
import 'epub/page_maps.dart';
import 'epub/publication.dart';
import 'mobi.dart';
import 'ocr.dart';
import 'pdf.dart';
import 'text_outline.dart';

Future<ReaderDocument> loadReadingDocument(
  VerifiedFile original,
  SourceFile source, {
  PdfTextSupply? textSupply,
}) async {
  final file = await _verifiedFile(original.uri);
  final container = await _containerOf(file, source);
  if (container == 'mobi' || container == 'azw3') {
    return importMobi(original);
  }
  if (container == 'pdf') {
    return PdfRuntime.instance.open(
      file.path,
      original.digest,
      textSupply:
          textSupply ?? (Platform.isAndroid ? BundledEnglishText() : null),
    );
  }
  // The fingerprint names the page maps' key. Its first call asks the
  // platform, beside the admission.
  final engine = textEngineFingerprint();
  final publication = await _admitted(original);
  return EpubDocument(
    publication,
    pageMaps: BookPageMaps(file, book: publication.identity, engine: engine),
  );
}

Future<Publication> loadPublication(VerifiedFile original) async {
  await _verifiedFile(original.uri);
  return _admitted(original);
}

/// Prepares the downloaded ebook [original] of [source] for reading, so
/// that its first open reads the admitted book that Bookfin keeps: it
/// admits an EPUB, or converts a MOBI to EPUB and admits that, and keeps
/// the results beside the download ([AdmittedBooks.prepare]). A book whose
/// results are kept costs a read of their key. A PDF needs nothing.
/// Downloads runs it under a hold of the download when the download
/// completes and at launch. Throws when the book cannot be admitted: its
/// open then reports why.
Future<void> prepareDownloadedBook(
  VerifiedFile original,
  SourceFile source,
) async {
  final file = await _verifiedFile(original.uri);
  switch (await _containerOf(file, source)) {
    case 'pdf':
      return;
    case 'mobi' || 'azw3':
      await prepareMobi(original);
    default:
      await AdmittedBooks.prepare(
        original,
        Publication.policy,
        _admission(original),
      );
  }
}

/// The text outline of the downloaded ebook [original] of [source]. One
/// worker isolate reads the admitted book that Bookfin kept, or admits or
/// converts the file and keeps it, as the reader does, and measures the
/// outline there. Only the small outline comes back. A PDF's outline comes
/// from its bookmarks and its text layer, on PDFium's worker (see
/// [PdfRuntime.measureOutline]).
Future<TextOutline> measureDownloadedOutline(
  VerifiedFile original,
  SourceFile source,
) async {
  final file = await _verifiedFile(original.uri);
  return switch (await _containerOf(file, source)) {
    'pdf' => PdfRuntime.instance.measureOutline(file.path),
    'mobi' || 'azw3' => readMobi(original, measureTextOutline),
    _ => _readAdmitted(original, measureTextOutline),
  };
}

/// The container of the downloaded [file] of [source], in lowercase:
/// Jellyfin's, or, when Jellyfin names none, `pdf` or `mobi` by the file's
/// signature, else empty.
Future<String> _containerOf(File file, SourceFile source) async {
  final container = source.container.trim().toLowerCase();
  if (container.isNotEmpty) return container;
  // Jellyfin Book originals can omit both Container and MediaSources.
  // Signatures select a parser; that parser still validates the full book.
  final input = await file.open();
  try {
    final header = String.fromCharCodes(await input.read(1024));
    if (header.startsWith('%PDF-')) return 'pdf';
    if (header.length >= 68 && header.substring(60, 68) == 'BOOKMOBI') {
      return 'mobi';
    }
    return '';
  } finally {
    await input.close();
  }
}

/// The admitted publication of the downloaded EPUB [original]. A worker
/// reads the admitted book that Bookfin kept, or admits the file and keeps
/// it.
Future<Publication> _admitted(VerifiedFile original) =>
    _readAdmitted(original, (publication) => publication);

/// What [use] gives for the admitted publication of [_admitted], run in the
/// same worker, so that only its result comes back.
Future<T> _readAdmitted<T>(
  VerifiedFile original,
  T Function(Publication publication) use,
) =>
    AdmittedBooks.load(original, Publication.policy, _admission(original), use);

/// The admission of the downloaded EPUB [original], which can run in a
/// worker. It is made in a scope of its own, so that it captures only the
/// file's path and digest, and not the lent file (see `_conversion` in
/// mobi.dart).
Future<Publication> Function() _admission(VerifiedFile original) {
  final path = File.fromUri(original.uri).path;
  final digest = original.digest;
  return () async => Publication.admit(await _archiveBytes(path), digest);
}

/// The admitted publication of the EPUB at [path], whose SHA-256 is
/// [digest]: the admitted book that Bookfin kept, else a new admission. It
/// keeps nothing, so it can run outside Downloads' read of the download
/// (t4-3o9f). It reads in the calling isolate, which must not be the UI
/// isolate.
Future<Publication> _keptOrAdmittedEpub(String path, String digest) =>
    AdmittedBooks.readOnly(
      File(path),
      digest,
      Publication.policy,
      () async => Publication.admit(await _archiveBytes(path), digest),
    );

/// A reader of the words of the downloaded ebook [original] of [source],
/// using Crossings' [outline] for the same file revision, for the worker
/// of the book's words (see [BookSearch]). The worker reads
/// later, outside Downloads' read of the download, so the reader writes
/// nothing beside it: it reads the admitted book that Bookfin kept, else
/// admits an EPUB again, and reads a MOBI only after Downloads prepared it
/// ([prepareDownloadedBook]) or the reader or the outline measurement
/// converted it. Null for a PDF, whose words speech does not read yet
/// (t2-9csd).
Future<ReadBook?> bookWordsReader(
  VerifiedFile original,
  SourceFile source,
  TextOutline outline,
) async {
  final file = await _verifiedFile(original.uri);
  return switch (await _containerOf(file, source)) {
    'pdf' => null,
    'mobi' || 'azw3' => _wordsOf(file.path, original.digest, outline, keptMobi),
    _ => _wordsOf(file.path, original.digest, outline, _keptOrAdmittedEpub),
  };
}

/// Reads the words of the publication that [admitted] gives for [path].
/// A top-level function, so that the reader captures only plain data and
/// can travel to the worker.
ReadBook _wordsOf(
  String path,
  String digest,
  TextOutline outline,
  Future<Publication> Function(String path, String digest) admitted,
) =>
    () async => bookWordsOf(await admitted(path, digest), outline);

/// The regular local file at [uri], which Downloads verified. Throws for
/// any other address and for a link, so that a reader never follows a
/// path out of the downloads. It sets no size limit: each format's loader
/// knows whether the bytes come into memory ([_archiveBytes]).
Future<File> _verifiedFile(Uri uri) async {
  if (uri.scheme != 'file' ||
      uri.host.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !uri.path.startsWith('/')) {
    throw const FormatException(
      'The reader requires a verified local download.',
    );
  }
  final file = File.fromUri(uri);
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException('The downloaded ebook is missing.');
  }
  return file;
}

/// The bytes of the EPUB at [path]. An EPUB loads whole into the memory of
/// the calling isolate, so a file above [Publication.maxArchiveBytes] is
/// refused before the read. A MOBI has the same limit in its conversion
/// (mobi.dart). A PDF has none: PDFium reads it from its path.
Future<Uint8List> _archiveBytes(String path) async {
  final file = File(path);
  if (await file.length() > Publication.maxArchiveBytes) {
    throw const FormatException(
      'This EPUB exceeds the 64 MiB limit. The original download was kept.',
    );
  }
  return file.readAsBytes();
}
