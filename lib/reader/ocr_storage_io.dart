import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// The text that the cache file at `path` keeps in its [field] for `key`,
/// or null when the file is not a whole saved entry. It runs in a hop.
Future<String?> _readEntry(
  ({String path, String key, String field}) entry,
) async {
  try {
    final value = jsonDecode(await File(entry.path).readAsString());
    if (value is! Map ||
        value['key'] != entry.key ||
        value[entry.field] is! String ||
        value['sha256'] !=
            sha256
                .convert(utf8.encode(value[entry.field] as String))
                .toString()) {
      return null;
    }
    return value[entry.field] as String;
  } on FormatException {
    return null;
  }
}

/// The cache file text that keeps `text` in its `field` for `key`. It runs
/// in a hop.
String _encodeEntry(({String key, String field, String text}) entry) =>
    jsonEncode({
      'key': entry.key,
      entry.field: entry.text,
      'sha256': sha256.convert(utf8.encode(entry.text)).toString(),
    });

/// The hOCR text that the cache file at `path` holds for `key`, or null when
/// the file is not a whole saved page. It runs in a hop.
Future<String?> _readPage(({String path, String key}) page) =>
    _readEntry((path: page.path, key: page.key, field: 'hocr'));

/// The cache file text that saves `hocr` for `key`. It runs in a hop.
String _encodePage(({String key, String hocr}) page) =>
    _encodeEntry((key: page.key, field: 'hocr', text: page.hocr));

/// The layout record that the cache file at `path` holds for `key`, or null
/// when the file is not a whole saved record. The record is kept as the
/// base64 of its numbers in little-endian order. It runs in a hop.
Future<Int32List?> _readLayout(({String path, String key}) page) async {
  final text = await _readEntry((
    path: page.path,
    key: page.key,
    field: 'layout',
  ));
  if (text == null) return null;
  final Uint8List bytes;
  try {
    bytes = base64Decode(text);
  } on FormatException {
    return null;
  }
  if (bytes.length % 4 != 0) return null;
  final data = ByteData.sublistView(bytes);
  return Int32List.fromList([
    for (var offset = 0; offset < bytes.length; offset += 4)
      data.getInt32(offset, Endian.little),
  ]);
}

/// The cache file text that saves the layout record `record` for `key`. It
/// runs in a hop.
String _encodeLayout(({String key, Int32List record}) page) {
  final data = ByteData(page.record.length * 4);
  for (var index = 0; index < page.record.length; index++) {
    data.setInt32(index * 4, page.record[index], Endian.little);
  }
  return _encodeEntry((
    key: page.key,
    field: 'layout',
    text: base64Encode(data.buffer.asUint8List()),
  ));
}

/// The recognition output that the cache keeps under [key] for the
/// downloaded PDF [original], or null when it keeps none. [digest] names the
/// PDF that the reader opened. Decoding runs in a hop.
Future<String?> readOcrCache(
  VerifiedFile original,
  String digest,
  String key, {
  IsolateHop hop = compute,
}) => _read(
  original,
  digest,
  key,
  (path) => hop(_readPage, (path: path, key: key)),
);

/// The layout record that the cache keeps under [key] for the downloaded
/// PDF [original], or null when it keeps none. [digest] names the PDF that
/// the reader opened. Decoding runs in a hop.
Future<Int32List?> readLayoutCache(
  VerifiedFile original,
  String digest,
  String key, {
  IsolateHop hop = compute,
}) => _read(
  original,
  digest,
  key,
  (path) => hop(_readLayout, (path: path, key: key)),
);

/// What [decode] gives for the cache file of [key], or null when the cache
/// has no such file.
Future<T?> _read<T>(
  VerifiedFile original,
  String digest,
  String key,
  Future<T?> Function(String path) decode,
) async {
  final directory = await _directory(original, digest);
  final file = File('${directory.path}/$key.json');
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() > 8000000) {
    return null;
  }
  return decode(file.path);
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
}) => _write(
  original,
  digest,
  key,
  live,
  () => hop(_encodePage, (key: key, hocr: hocr)),
);

/// Keeps the layout record [record] under [key] for the downloaded PDF
/// [original], while [live] holds. [digest] names the PDF that the reader
/// opened. Encoding runs in a hop, and the write replaces the file whole.
Future<void> writeLayoutCache(
  VerifiedFile original,
  String digest,
  String key,
  Int32List record,
  bool Function() live, {
  IsolateHop hop = compute,
}) => _write(
  original,
  digest,
  key,
  live,
  () => hop(_encodeLayout, (key: key, record: record)),
);

/// Writes the file text that [encode] gives as the cache file of [key]:
/// first to a pending file, then a rename replaces the file whole.
Future<void> _write(
  VerifiedFile original,
  String digest,
  String key,
  bool Function() live,
  Future<String> Function() encode,
) async {
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
  final text = await encode();
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
