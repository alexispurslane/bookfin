import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'covers.dart';
import 'jellyfin.dart';
import 'model.dart';

typedef CoverFetch = Future<Uint8List?> Function(
  Uri uri,
  Map<String, String> headers,
);

/// Keeps covers in one directory per account, one file per item:
/// `<root>/<account hash>/<item>@<tag>`. A newer tag replaces the older file.
class DiskCovers implements Covers {
  DiskCovers({required this.root, CoverFetch? fetch})
    : _fetch = fetch ?? _httpFetch;
  final Directory root;
  final CoverFetch _fetch;
  final _loading = <String, Future<Uint8List?>>{};
  final _missing = <String>{};

  @override
  Future<Uint8List?> load(JellyfinSession session, CoverRef cover) {
    // NOTE: Engine rule 1. This hashes one account key of a few dozen
    // bytes. Measured in AOT on an M-series Mac, that takes about 2 µs, and
    // a hop to another isolate about 33 µs.
    final directory = Directory(
      '${root.path}/${sha256.convert(utf8.encode(session.scope.key))}',
    );
    final item = _safe(cover.itemId);
    final file = File('${directory.path}/$item@${_safe(cover.tag)}');
    final key = file.path;
    if (_missing.contains(key)) return Future.value();
    return _loading[key] ??= () async {
      try {
        if (await file.exists()) return await file.readAsBytes();
        final Uint8List? bytes;
        try {
          bytes = await _fetch(coverUri(session, cover), {
            'X-Emby-Token': session.token,
          });
        } catch (_) {
          return null;
        }
        if (bytes == null || bytes.isEmpty) {
          _missing.add(key);
          return null;
        }
        await directory.create(recursive: true);
        final partial = File('${file.path}.partial');
        await partial.writeAsBytes(bytes, flush: true);
        await partial.rename(file.path);
        await for (final old in directory.list()) {
          if (old is File &&
              old.path != file.path &&
              old.uri.pathSegments.last.startsWith('$item@')) {
            await old.delete();
          }
        }
        return bytes;
      } finally {
        _loading.remove(key);
      }
    }();
  }

  @override
  Future<void> clear() async {
    _missing.clear();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

String _safe(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

final _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);

Future<Uint8List?> _httpFetch(Uri uri, Map<String, String> headers) async {
  final request = await _client
      .getUrl(uri)
      .timeout(const Duration(seconds: 20));
  headers.forEach(request.headers.set);
  final response = await request.close().timeout(const Duration(seconds: 20));
  if (response.statusCode == 404) {
    await response.drain<void>();
    return null;
  }
  if (response.statusCode != 200) {
    await response.drain<void>();
    throw HttpException('cover ${response.statusCode}', uri: uri);
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in response.timeout(const Duration(seconds: 20))) {
    bytes.add(chunk);
    if (bytes.length > 10 * 1024 * 1024) {
      throw HttpException('cover too large', uri: uri);
    }
  }
  return bytes.takeBytes();
}

Future<Covers?> createCovers() async {
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    final info = await const MethodChannel('bookfin/media')
        .invokeMapMethod<String, dynamic>('storage');
    final media = info?['path'];
    if (media is! String) return null;
    return DiskCovers(
      root: Directory('${File(media).parent.path}/bookfin-covers'),
    );
  } catch (_) {
    return null;
  }
}
