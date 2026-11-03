import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_epub_viewer/publication.dart';

import 'document.dart';

Future<void> _imports = Future.value();

Future<EpubDocument> importMobi(File original) {
  final imported = _imports.then((_) => compute(_convert, original.path));
  _imports = imported.then<void>((_) {}, onError: (Object error) {});
  return imported;
}

Future<EpubDocument> _convert(String path) async {
  final original = File(path);
  if (await original.length() > Publication.maxArchiveBytes) {
    throw const FormatException(
      'This MOBI exceeds the 64 MiB import limit. The original download was kept.',
    );
  }
  final bytes = await original.readAsBytes();
  final digest = sha256.convert(bytes).toString();
  final cacheRoot = Directory('${original.parent.path}/.bookfin-mobi');
  final rootType = await FileSystemEntity.type(
    cacheRoot.path,
    followLinks: false,
  );
  if (rootType != FileSystemEntityType.notFound &&
      rootType != FileSystemEntityType.directory) {
    throw const FormatException(
      'The local MOBI cache is not a private directory. The original download was kept.',
    );
  }
  await cacheRoot.create();
  final destination = Directory('${cacheRoot.path}/$digest-libmobi-0.12-v1');
  final cached = await _cached(destination, digest);
  if (cached != null) return cached;
  final work = await cacheRoot.createTemp('conversion-');
  try {
    final input = await File('${work.path}/book.mobi')
        .writeAsBytes(bytes, flush: true);
    final library = DynamicLibrary.open(
      Platform.isAndroid
          ? 'libbookfin_mobi.so'
          : Platform.environment['BOOKFIN_MOBI_LIBRARY'] ??
                'libbookfin_mobi.dylib',
    );
    final convert = library
        .lookupFunction<
          Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)
        >('bookfin_convert');
    final nativePath = input.path.toNativeUtf8();
    int result;
    try {
      result = convert(nativePath);
    } finally {
      malloc.free(nativePath);
    }
    final output = File('${work.path}/book.epub');
    if (result != 0 ||
        !await output.exists() ||
        await output.length() > Publication.maxArchiveBytes) {
      throw const FormatException(
        'This MOBI is encrypted, damaged, too large, or uses an unsupported variant. The original download was kept.',
      );
    }
    final converted = await output.readAsBytes();
    final publication = Publication.admit(converted);
    await input.delete();
    await File('${work.path}/manifest.json').writeAsString(
      jsonEncode({
        'version': 1,
        'original': digest,
        'policy': EpubDocument.mobiPolicy,
        'epub': sha256.convert(converted).toString(),
      }),
      flush: true,
    );
    if (await destination.exists()) await destination.delete(recursive: true);
    await work.rename(destination.path);
    return EpubDocument.mobi(publication, digest);
  } on ArgumentError {
    throw const FormatException(
      'The bundled MOBI converter is unavailable in this build. The original download was kept.',
    );
  } finally {
    if (await work.exists()) await work.delete(recursive: true);
  }
}

Future<EpubDocument?> _cached(Directory folder, String digest) async {
  try {
    if (await FileSystemEntity.type(folder.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return null;
    }
    final manifest = jsonDecode(
      await File('${folder.path}/manifest.json').readAsString(),
    );
    final output = File('${folder.path}/book.epub');
    if (await FileSystemEntity.type(output.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await output.length() > Publication.maxArchiveBytes) {
      return null;
    }
    final Uint8List bytes = await output.readAsBytes();
    if (manifest is! Map ||
        manifest['version'] != 1 ||
        manifest['original'] != digest ||
        manifest['policy'] != EpubDocument.mobiPolicy ||
        manifest['epub'] != sha256.convert(bytes).toString()) {
      return null;
    }
    return EpubDocument.mobi(Publication.admit(bytes), digest);
  } on Exception {
    return null;
  }
}
