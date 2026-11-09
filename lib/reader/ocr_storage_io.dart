import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;

import '../downloads/downloads.dart';
import '../foundation/hop.dart';
import '../downloads/derived_files.dart';

/// The cache directory of the downloaded PDF [original], whose pages the
/// reader opened from bytes with [digest]. Downloads made sure that the file
/// of [original] has the digest of [original], so the cache trusts that
/// digest and does not hash the file again. Throws a [FormatException] when
/// the download now holds another PDF than the open book, or when the file or
/// its cache directory is not a plain file or directory.
Future<Directory> _directory(VerifiedFile original, String digest) async {
  final file = File.fromUri(original.uri);
  if (original.digest != digest ||
      original.uri.scheme != 'file' ||
      original.uri.host.isNotEmpty ||
      await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
    throw const FormatException(
      'The original PDF changed. Reopen its download.',
    );
  }
  final directory = DerivedBookFiles.ocrDirectory(file);
  final type = await FileSystemEntity.type(directory.path, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.directory) {
    throw const FormatException(
      'The recognition cache is not a private directory.',
    );
  }
  return directory;
}

/// The hOCR text that the cache file at `path` holds for `key`, or null when
/// the file is not a whole saved page. It runs in a hop.
Future<String?> _readPage(({String path, String key}) page) async {
  try {
    final value = jsonDecode(await File(page.path).readAsString());
    if (value is! Map ||
        value['key'] != page.key ||
        value['hocr'] is! String ||
        value['sha256'] !=
            sha256.convert(utf8.encode(value['hocr'] as String)).toString()) {
      return null;
    }
    return value['hocr'] as String;
  } on FormatException {
    return null;
  }
}

/// The cache file text that saves `hocr` for `key`. It runs in a hop.
String _encodePage(({String key, String hocr}) page) => jsonEncode({
  'key': page.key,
  'hocr': page.hocr,
  'sha256': sha256.convert(utf8.encode(page.hocr)).toString(),
});

/// The recognition output that the cache keeps under [key] for the
/// downloaded PDF [original], or null when it keeps none. [digest] names the
/// PDF that the reader opened. Decoding runs in a hop.
Future<String?> readOcrCache(
  VerifiedFile original,
  String digest,
  String key, {
  IsolateHop hop = compute,
}) async {
  final directory = await _directory(original, digest);
  final file = File('${directory.path}/$key.json');
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() > 8000000) {
    return null;
  }
  return hop(_readPage, (path: file.path, key: key));
}

/// Keeps the recognition output [hocr] under [key] for the downloaded PDF
/// [original], while [live] holds. [digest] names the PDF that the reader
/// opened. Encoding runs in a hop, and the write replaces the file whole.
Future<void> writeOcrCache(
  VerifiedFile original,
  String digest,
  String key,
  String hocr,
  bool Function() live, {
  IsolateHop hop = compute,
}) async {
  final directory = await _directory(original, digest);
  if (!live()) return;
  await directory.create();
  final file = File('${directory.path}/$key.json');
  final pending = File('${file.path}.pending');
  for (final path in [file.path, pending.path]) {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const FormatException('The recognition cache contains a link.');
    }
  }
  final text = await hop(_encodePage, (key: key, hocr: hocr));
  try {
    await pending.writeAsString(text, flush: true);
    // Downloads removes a download in the same command queue that runs this
    // write's read of the original, so no removal starts before the rename
    // ends.
    if (live()) await pending.rename(file.path);
  } finally {
    if (await pending.exists()) await pending.delete();
  }
}
