import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'crossings.dart';

/// Keeps each text outline of [Crossings] in its own file under [root],
/// named by the SHA-256 of its key. A write goes to a partial file first and
/// then renames it over the kept file, so a crash leaves the old outline or
/// the new one.
class DiskOutlines implements OutlineStore {
  DiskOutlines(this.root);
  final Directory root;

  File _file(String key) {
    // NOTE: Engine rule 1. This hashes one key of a few hundred bytes, which
    // costs far less than a hop to another isolate (see DiskCovers._file).
    final name = sha256.convert(utf8.encode(key));
    return File('${root.path}/$name.json');
  }

  @override
  Future<String?> read(String key) async {
    try {
      return await _file(key).readAsString();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final file = _file(key);
    await root.create(recursive: true);
    final partial = File('${file.path}.partial');
    await partial.writeAsString(value, flush: true);
    await partial.rename(file.path);
  }
}

/// The outline store beside the app's media storage, as the covers keep
/// theirs, or null when the platform names no storage.
Future<OutlineStore?> findOutlineStore() async {
  try {
    final info = await const MethodChannel('bookfin/media')
        .invokeMapMethod<String, dynamic>('storage');
    final media = info?['path'];
    if (media is! String) return null;
    return DiskOutlines(
      Directory('${File(media).parent.path}/bookfin-outlines'),
    );
  } catch (_) {
    return null;
  }
}
