import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

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
  final _blurring = <String, Future<Uri?>>{};
  final _missing = <String>{};

  /// The kept cover file of [cover] in [session]'s account directory.
  File _file(JellyfinSession session, CoverRef cover) {
    // NOTE: Engine rule 1. This hashes one account key of a few dozen
    // bytes. Measured in AOT on an M-series Mac, that takes about 2 µs, and
    // a hop to another isolate about 33 µs.
    final account = sha256.convert(utf8.encode(session.scope.key));
    return File(
      '${root.path}/$account/${_safe(cover.itemId)}@${_safe(cover.tag)}',
    );
  }

  @override
  Future<Uint8List?> load(JellyfinSession session, CoverRef cover) {
    final file = _file(session, cover);
    final directory = file.parent;
    final item = _safe(cover.itemId);
    final key = file.path;
    if (_missing.contains(key)) return Future.value();
    return _loading[key] ??= () async {
      try {
        if (await file.exists()) return await file.readAsBytes();
        if (session.needsSignIn) return null;
        final Uint8List? bytes;
        try {
          bytes = await _fetch(coverUri(session, cover), {
            'X-Emby-Token': session.token,
          });
        } catch (error) {
          if (error is CatalogFailure &&
              error.kind == CatalogFailureKind.unauthorized) {
            session.rejectCredential();
          }
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
        // Removes the files of older versions of the item's cover, and
        // keeps those of this version, such as its blurred copy.
        await for (final old in directory.list()) {
          final name = old.uri.pathSegments.last;
          if (old is File &&
              old.path != file.path &&
              !old.path.startsWith('${file.path}.') &&
              name.startsWith('$item@')) {
            await old.delete();
          }
        }
        return bytes;
      } finally {
        _loading.remove(key);
      }
    }();
  }

  /// Kept beside the cover as `<item>@<tag>.blur.png`. The first call for a
  /// cover image makes the copy in another isolate. Later calls, also after a
  /// restart, give the kept file. Null also when the phone cannot store it.
  @override
  Future<Uri?> blurred(JellyfinSession session, CoverRef cover) {
    final blurred = File('${_file(session, cover).path}.blur.png');
    return _blurring[blurred.path] ??= () async {
      try {
        if (await blurred.exists()) return blurred.uri;
        final bytes = await load(session, cover);
        if (bytes == null) return null;
        final art = await _blurElsewhere(bytes);
        if (art == null) return null;
        final partial = File('${blurred.path}.partial');
        await partial.writeAsBytes(art, flush: true);
        await partial.rename(blurred.path);
        return blurred.uri;
      } on FileSystemException {
        return null;
      } finally {
        _blurring.remove(blurred.path);
      }
    }();
  }

  @override
  Future<void> clear() async {
    _missing.clear();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

/// How far the blur of [DiskCovers.blurred] spreads, as a share of the
/// cover's width. It matches the player chip: [CoverGlass] blurs the cover
/// with a sigma of 22 logical pixels across a pane about 390 logical pixels
/// wide, and Android scales the art to the width of its player, which is
/// about as wide.
const _blurShare = 22 / 390;

/// The blur's sigma in pixels of the blurred copy. Like the chip's bitmap,
/// the copy is small and drawn stretched: at six pixels per sigma, it differs
/// from a full-size blur by at most a few levels of 255.
const _blurSigma = 6.0;

/// Runs [_blur] in another isolate. A top-level function, so that the
/// isolate message holds only [bytes], not the caller's state.
Future<Uint8List?> _blurElsewhere(Uint8List bytes) =>
    Isolate.run(() => _blur(bytes));

/// The cover [bytes] blurred as [DiskCovers.blurred] describes, as a PNG.
/// Null when [bytes] is no image that the decoders read.
Uint8List? _blur(Uint8List bytes) {
  final img.Image? cover;
  try {
    cover = img.decodeImage(bytes);
  } catch (_) {
    // The decoders throw on damaged data, such as a cut-off download.
    return null;
  }
  if (cover == null) return null;
  final width = (_blurSigma / _blurShare).round();
  final small = img.copyResize(
    cover,
    width: width,
    height: (cover.height * width / cover.width).round(),
    interpolation: img.Interpolation.average,
  );
  // The image package's blur of radius r has a sigma of 2r/3.
  final blurred = img.gaussianBlur(small, radius: (_blurSigma * 3 / 2).round());
  return img.encodePng(blurred);
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
    if (response.statusCode == 401) {
      throw const CatalogFailure(CatalogFailureKind.unauthorized);
    }
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

/// Keeps covers in `bookfin-covers`, beside the download directory that the
/// runner's media host contract names. Without that contract there are no
/// saved covers.
Future<Covers?> createCovers() async {
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
