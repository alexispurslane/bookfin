import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_epub_viewer/publication.dart';

Future<Publication> loadPublication(Uri uri) async {
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
      'The downloaded EPUB is missing or exceeds 64 MiB.',
    );
  }
  return compute(Publication.admit, await file.readAsBytes());
}
