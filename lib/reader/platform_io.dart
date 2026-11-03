import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_epub_viewer/publication.dart';

import '../catalog/model.dart';
import 'document.dart';
import 'pdf.dart';
import 'mobi.dart';

Future<ReaderDocument> loadReadingDocument(Uri uri, SourceFile source) async {
  if (source.container.toLowerCase() == 'mobi' ||
      source.container.toLowerCase() == 'azw3') {
    return importMobi(await _verifiedFile(uri));
  }
  if (source.container.toLowerCase() != 'pdf') {
    return EpubDocument(await loadPublication(uri));
  }
  final file = await _verifiedFile(uri);
  return PdfRuntime.instance.open(await file.readAsBytes());
}

Future<Publication> loadPublication(Uri uri) async {
  final file = await _verifiedFile(uri);
  return compute(Publication.admit, await file.readAsBytes());
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
