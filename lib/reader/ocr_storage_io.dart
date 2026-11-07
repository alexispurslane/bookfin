import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;

import '../downloads/derived_files.dart';

/// Runs [work] on [input] in another isolate and completes with its result.
/// [compute] is the default.
typedef OcrHop = Future<R> Function<M, R>(
  FutureOr<R> Function(M) work,
  M input,
);

/// The check of the original PDF that the last cache access made: its path,
/// the digest that it was checked against, its size and modification time
/// at that moment, and whether its bytes had that digest.
///
/// One open document reads and writes the cache for each recognized page,
/// so the check runs once for the document. A changed size or modification
/// time, another document, or a failed check starts a new check.
({
  String path,
  String digest,
  int size,
  DateTime modified,
  Future<bool> matches,
})?
_lastCheck;

/// Whether the original PDF [file] has [digest]. The hash runs in a hop.
Future<bool> _matches(File file, String digest, OcrHop hop) async {
  final stat = await file.stat();
  final last = _lastCheck;
  if (last != null &&
      last.path == file.path &&
      last.digest == digest &&
      last.size == stat.size &&
      last.modified == stat.modified) {
    return last.matches;
  }
  final matches = hop(_digestOf, file.path).then((actual) => actual == digest);
  _lastCheck = (
    path: file.path,
    digest: digest,
    size: stat.size,
    modified: stat.modified,
    matches: matches,
  );
  var matched = false;
  try {
    return matched = await matches;
  } finally {
    // A failed check is not kept, so the next access checks again.
    if (!matched && identical(_lastCheck?.matches, matches)) _lastCheck = null;
  }
}

Future<String> _digestOf(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

Future<Directory> _directory(Uri original, String digest, OcrHop hop) async {
  final file = File.fromUri(original);
  if (original.scheme != 'file' ||
      original.host.isNotEmpty ||
      await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      !await _matches(file, digest, hop)) {
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

Future<String?> readOcrCache(
  Uri original,
  String digest,
  String key, {
  OcrHop hop = compute,
}) async {
  final directory = await _directory(original, digest, hop);
  final file = File('${directory.path}/$key.json');
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() > 8000000) {
    return null;
  }
  return hop(_readPage, (path: file.path, key: key));
}

Future<void> writeOcrCache(
  Uri original,
  String digest,
  String key,
  String hocr,
  bool Function() live, {
  OcrHop hop = compute,
}) async {
  final directory = await _directory(original, digest, hop);
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
