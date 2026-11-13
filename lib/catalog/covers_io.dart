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
  final _loading = <String, ({Object credential, Future<Uint8List?> done})>{};
  final _blurring = <String, ({Object credential, Future<Uri?> done})>{};
  final _missing = <(String, Object)>{};
  final _versions = <String, int>{};
  final _clearing = <String, Future<void>>{};

  String _directory(AccountScope scope) {
    // One short account key costs less to hash than an isolate hop.
    return '${root.path}/${sha256.convert(utf8.encode(scope.key))}';
  }

  bool _current(String directory, int version) =>
      (_versions[directory] ?? 0) == version &&
      !_clearing.containsKey(directory);

  /// The kept cover file of [cover] in [session]'s account directory.
  File _file(JellyfinSession session, CoverRef cover) {
    return File(
      '${_directory(session.scope)}/${_safe(cover.itemId)}@${_safe(cover.tag)}',
    );
  }

  @override
  Future<Uint8List?> load(JellyfinSession session, CoverRef cover) {
    final file = _file(session, cover);
    final directory = file.parent;
    final version = _versions[directory.path] ?? 0;
    bool current() => _current(directory.path, version);
    if (!current()) return Future.value();
    final item = _safe(cover.itemId);
    final key = file.path;
    final missingKey = (key, session.credentialIdentity);
    if (_missing.contains(missingKey)) return Future.value();
    final loading = _loading[key];
    if (loading != null) {
      // Keep writes to this file serialized. A replacement can use a saved
      // result, but retries its own credential after an obsolete failure.
      return loading.credential == session.credentialIdentity
          ? loading.done
          : loading.done.then((_) => current() ? load(session, cover) : null);
    }
    final done = () async {
      try {
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          return current() ? bytes : null;
        }
        if (session.needsSignIn) return null;
        final Uint8List? bytes;
        try {
          bytes = await _fetch(coverUri(session, cover), {
            'X-Emby-Token': session.token,
          });
        } on Exception catch (error) {
          if (error is CatalogFailure &&
              error.kind == CatalogFailureKind.unauthorized) {
            session.rejectCredential();
          }
          return null;
        }
        if (!current()) return null;
        if (bytes == null || bytes.isEmpty) {
          _missing.add(missingKey);
          return null;
        }
        await directory.create(recursive: true);
        if (!current()) return null;
        final partial = File('${file.path}.partial');
        await partial.writeAsBytes(bytes, flush: true);
        if (!current()) return null;
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
        return current() ? bytes : null;
      } finally {
        _loading.remove(key);
      }
    }();
    _loading[key] = (credential: session.credentialIdentity, done: done);
    return done;
  }

  /// Kept beside the cover as `<item>@<tag>.blur.png`. The first call for a
  /// cover image makes the copy in another isolate. Later calls, also after a
  /// restart, give the kept file. Null also when the phone cannot store it.
  @override
  Future<Uri?> blurred(JellyfinSession session, CoverRef cover) {
    final blurred = File('${_file(session, cover).path}.blur.png');
    final directory = blurred.parent.path;
    final version = _versions[directory] ?? 0;
    bool current() => _current(directory, version);
    if (!current()) return Future.value();
    final blurring = _blurring[blurred.path];
    if (blurring != null) {
      return blurring.credential == session.credentialIdentity
          ? blurring.done
          : blurring.done.then(
              (_) => current() ? this.blurred(session, cover) : null,
            );
    }
    final done = () async {
      try {
        if (await blurred.exists()) return current() ? blurred.uri : null;
        final bytes = await load(session, cover);
        if (bytes == null || !current()) return null;
        final art = await _blurElsewhere(bytes);
        if (art == null || !current()) return null;
        final partial = File('${blurred.path}.partial');
        await partial.writeAsBytes(art, flush: true);
        if (!current()) return null;
        await partial.rename(blurred.path);
        return current() ? blurred.uri : null;
      } on FileSystemException {
        return null;
      } finally {
        _blurring.remove(blurred.path);
      }
    }();
    _blurring[blurred.path] = (
      credential: session.credentialIdentity,
      done: done,
    );
    return done;
  }

  @override
  Future<void> clear(AccountScope account) {
    final directory = _directory(account);
    if (_clearing[directory] case final clearing?) return clearing;
    _versions[directory] = (_versions[directory] ?? 0) + 1;
    _missing.removeWhere((entry) => entry.$1.startsWith('$directory/'));
    final pending = <Future<Object?>>[
      for (final entry in _loading.entries)
        if (entry.key.startsWith('$directory/')) entry.value.done,
      for (final entry in _blurring.entries)
        if (entry.key.startsWith('$directory/')) entry.value.done,
    ];
    final done = () async {
      // Older writers settle before deletion; new loads cannot start while
      // this future owns the account. Neither path can recreate its files.
      await Future.wait(pending);
      final type = await FileSystemEntity.type(directory, followLinks: false);
      if (type == FileSystemEntityType.notFound) return;
      if (type != FileSystemEntityType.directory ||
          await FileSystemEntity.type(root.path, followLinks: false) !=
              FileSystemEntityType.directory) {
        throw const FileSystemException(
          'Cover storage is not a private directory.',
        );
      }
      await Directory(directory).delete(recursive: true);
    }();
    _clearing[directory] = done;
    return done.whenComplete(() => _clearing.remove(directory));
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
