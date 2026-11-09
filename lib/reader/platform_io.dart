import 'dart:io';
import 'dart:isolate';

import '../catalog/model.dart';
import '../downloads/downloads.dart';
import 'admitted_books.dart';
import 'document.dart';
import 'epub/publication.dart';
import 'mobi.dart';
import 'ocr.dart';
import 'pdf.dart';

Future<ReaderDocument> loadReadingDocument(
  VerifiedFile original,
  SourceFile source, {
  PdfTextSupply? textSupply,
}) async {
  final file = await _verifiedFile(original.uri);
  var container = source.container.trim().toLowerCase();
  if (container.isEmpty) {
    // Jellyfin Book originals can omit both Container and MediaSources.
    // Signatures select a parser; that parser still validates the full book.
    final input = await file.open();
    try {
      final header = String.fromCharCodes(await input.read(1024));
      if (header.startsWith('%PDF-')) {
        container = 'pdf';
      } else if (header.length >= 68 &&
          header.substring(60, 68) == 'BOOKMOBI') {
        container = 'mobi';
      }
    } finally {
      await input.close();
    }
  }
  if (container == 'mobi' || container == 'azw3') {
    return importMobi(file, original.digest);
  }
  if (container == 'pdf') {
    return PdfRuntime.instance.open(
      await file.readAsBytes(),
      original.digest,
      textSupply:
          textSupply ?? (Platform.isAndroid ? BundledEnglishText() : null),
    );
  }
  return EpubDocument(await _admitted(file, original.digest));
}

Future<Publication> loadPublication(VerifiedFile original) async =>
    _admitted(await _verifiedFile(original.uri), original.digest);

/// The admitted publication of the downloaded EPUB [file], whose SHA-256 is
/// [digest]. A worker reads the admitted book that Bookfin kept, or admits
/// the file and keeps it.
Future<Publication> _admitted(File file, String digest) {
  final path = file.path;
  return Isolate.run(
    () => AdmittedBooks.open(
      File(path),
      digest,
      Publication.policy,
      () async => Publication.admit(await File(path).readAsBytes(), digest),
    ),
  );
}

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
