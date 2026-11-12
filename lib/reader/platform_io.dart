import 'dart:io';

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
    return importMobi(file, original.digest);
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
  final publication = await _admitted(file, original.digest);
  return EpubDocument(
    publication,
    pageMaps: BookPageMaps(file, book: publication.identity, engine: engine),
  );
}

Future<Publication> loadPublication(VerifiedFile original) async =>
    _admitted(await _verifiedFile(original.uri), original.digest);

/// Completes once the files that the loads of the download [original]
/// wrote beside it after they gave their book are written: the kept
/// admitted book ([AdmittedBooks.written]).
Future<void> derivedFilesWritten(VerifiedFile original) =>
    AdmittedBooks.written(File.fromUri(original.uri));

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
  final outline = await switch (await _containerOf(file, source)) {
    'pdf' => PdfRuntime.instance.measureOutline(file.path),
    'mobi' || 'azw3' => readMobi(file, original.digest, measureTextOutline),
    _ => _readAdmitted(file, original.digest, measureTextOutline),
  };
  // The caller's read of the download ends when this does, so the kept
  // admitted book is written before a removal can start.
  await AdmittedBooks.written(file);
  return outline;
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

/// The admitted publication of the downloaded EPUB [file], whose SHA-256 is
/// [digest]. A worker reads the admitted book that Bookfin kept, or admits
/// the file and keeps it.
Future<Publication> _admitted(File file, String digest) =>
    _readAdmitted(file, digest, (publication) => publication);

/// What [use] gives for the admitted publication of [_admitted], run in the
/// same worker, so that only its result comes back.
Future<T> _readAdmitted<T>(
  File file,
  String digest,
  T Function(Publication publication) use,
) {
  final path = file.path;
  return AdmittedBooks.load(
    file,
    digest,
    Publication.policy,
    () async => Publication.admit(await File(path).readAsBytes(), digest),
    use,
  );
}

/// The admitted publication of the EPUB at [path], whose SHA-256 is
/// [digest], read in the calling isolate, which must not be the UI
/// isolate: the admitted book that Bookfin kept, else a new admission,
/// which is then kept.
Future<Publication> _admittedEpub(String path, String digest) async {
  final (publication, record) = await AdmittedBooks.read(
    File(path),
    digest,
    Publication.policy,
    () async => Publication.admit(await File(path).readAsBytes(), digest),
  );
  if (record != null) await AdmittedBooks.keep(record);
  return publication;
}

/// A reader of the words of the downloaded ebook [original] of [source],
/// for the worker of the book's words (see [BookSearch]). It reads the
/// admitted book that Bookfin kept, or admits or converts the file and
/// keeps it, as the reader does. Null for a PDF, whose words speech does
/// not read yet (t2-9csd).
Future<ReadBook?> bookWordsReader(
  VerifiedFile original,
  SourceFile source,
) async {
  final file = await _verifiedFile(original.uri);
  return switch (await _containerOf(file, source)) {
    'pdf' => null,
    'mobi' || 'azw3' => _wordsOf(file.path, original.digest, admittedMobi),
    _ => _wordsOf(file.path, original.digest, _admittedEpub),
  };
}

/// Reads the words of the publication that [admitted] gives for [path].
/// A top-level function, so that the reader captures only plain data and
/// can travel to the worker.
ReadBook _wordsOf(
  String path,
  String digest,
  Future<Publication> Function(String path, String digest) admitted,
) =>
    () async => bookWordsOf(await admitted(path, digest));

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
          FileSystemEntityType.file ||
      await file.length() > Publication.maxArchiveBytes) {
    throw const FormatException(
      'The downloaded ebook is missing or exceeds 64 MiB.',
    );
  }
  return file;
}
