import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'catalog_files.dart';

/// Atomic catalog files under [root]. Disk access and conversion between text
/// and bytes run together in a worker isolate. Incomplete .partial files are
/// never read, and a retry replaces them before committing.
class DiskCatalogFiles implements CatalogFiles {
  DiskCatalogFiles(this.root);
  final Directory root;

  String _path(String key) {
    // One short account key costs less to hash than an isolate hop. Catalog
    // text conversion and all disk work below run in the worker instead.
    final name = sha256.convert(utf8.encode(key));
    return '${root.path}/$name.catalog';
  }

  @override
  Future<String?> read(String key) {
    final path = _path(key);
    return Isolate.run(() async {
      try {
        return await File(path).readAsString();
      } on PathNotFoundException {
        return null;
      }
    });
  }

  @override
  Future<void> write(String key, String text) {
    final path = _path(key);
    return Isolate.run(() async {
      final file = File(path);
      await file.parent.create(recursive: true);
      final partial = File('$path.partial');
      await partial.writeAsString(text, flush: true);
      await partial.rename(path);
    });
  }
}

/// Resolves the native host's application-private directory lazily. A failed
/// lookup is retried on the next operation and is never treated as empty data.
CatalogFiles createCatalogFiles() => _HostCatalogFiles();

class _HostCatalogFiles implements CatalogFiles {
  DiskCatalogFiles? _files;

  Future<DiskCatalogFiles> _open() async {
    if (_files case final files?) return files;
    final info = await const MethodChannel('bookfin/media')
        .invokeMapMethod<String, dynamic>('storage');
    final media = info?['path'];
    if (media is! String || media.isEmpty) {
      throw const FileSystemException(
        'Private catalog storage is unavailable.',
      );
    }
    return _files = DiskCatalogFiles(
      Directory('${File(media).parent.path}/bookfin-catalog'),
    );
  }

  @override
  Future<String?> read(String key) async => (await _open()).read(key);

  @override
  Future<void> write(String key, String text) async =>
      (await _open()).write(key, text);
}
