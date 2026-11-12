import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../downloads/derived_files.dart';
import '../downloads/downloads.dart';
import '../sync/device.dart';
import 'admitted_books.dart';
import 'document.dart';
import 'epub/page_maps.dart';
import 'epub/publication.dart';

Future<void> _imports = Future.value();

/// The document of the downloaded MOBI [original]. Its first open converts
/// it to EPUB and admits that EPUB, unless Downloads prepared it
/// ([prepareMobi]). Later opens read the admitted book that Bookfin kept,
/// and neither convert, read nor hash the MOBI.
Future<EpubDocument> importMobi(VerifiedFile original) async {
  // The fingerprint names the page maps' key. Its first call asks the
  // platform, beside the import.
  final engine = textEngineFingerprint();
  final publication = await readMobi(original, (publication) => publication);
  return EpubDocument.mobi(
    publication,
    original.digest,
    pageMaps: BookPageMaps(
      File.fromUri(original.uri),
      book: publication.identity,
      engine: engine,
    ),
  );
}

/// What [use] gives for the publication of the MOBI [original], run in the
/// worker isolate that reads the admitted book that Bookfin kept, or
/// converts and admits the file and keeps it, as [importMobi] does. Only
/// the result of [use] comes back. Conversions run one at a time.
Future<T> readMobi<T>(
  VerifiedFile original,
  T Function(Publication publication) use,
) {
  final convert = _conversion(original);
  final read = _imports.then(
    (_) => AdmittedBooks.load(original, EpubDocument.mobiPolicy, convert, use),
  );
  _imports = read.then<void>((_) {}, onError: (Object error) {});
  return read;
}

/// Prepares the downloaded MOBI [original] for reading, as
/// [AdmittedBooks.prepare] does: it converts the MOBI to EPUB and keeps the
/// conversion, then admits the EPUB and keeps the admitted book, unless
/// the admitted book is kept already. Conversions run one at a time.
Future<void> prepareMobi(VerifiedFile original) {
  final convert = _conversion(original);
  final prepared = _imports.then(
    (_) => AdmittedBooks.prepare(original, EpubDocument.mobiPolicy, convert),
  );
  _imports = prepared.then<void>((_) {}, onError: (Object error) {});
  return prepared;
}

/// The conversion and admission of the downloaded MOBI [original], which
/// can run in a worker.
///
/// IMPORTANT: A closure holds every variable of its scope that a closure of
/// that scope captures. So the conversion is made in a scope of its own,
/// where it captures only the file's path and digest, and not the lent file,
/// whose hold reaches Downloads, which no isolate message can carry.
Future<Publication> Function() _conversion(VerifiedFile original) {
  final path = File.fromUri(original.uri).path;
  final digest = original.digest;
  return () => _convert(path, digest);
}

/// The admitted publication of the MOBI at [path], whose SHA-256 is
/// [digest], from what Bookfin kept beside it: the admitted book, else the
/// kept conversion. It writes nothing, so it can run outside Downloads'
/// read of the download (t4-3o9f). It reads in the calling isolate, which
/// must not be the UI isolate. It throws a [FormatException] when Bookfin
/// kept neither, because the reader did not convert the MOBI yet.
Future<Publication> keptMobi(String path, String digest) async {
  final (publication, _) = await AdmittedBooks.read(
    File(path),
    digest,
    EpubDocument.mobiPolicy,
    () async =>
        await _cached(_conversionOf(File(path), digest), digest) ??
        (throw const FormatException('This MOBI is not converted yet.')),
  );
  return publication;
}

/// The folder of the conversion of the MOBI [original], whose SHA-256 is
/// [digest].
Directory _conversionOf(File original, String digest) => Directory(
  '${DerivedBookFiles.mobiDirectory(original).path}/$digest-libmobi-0.12-v1',
);

/// The admitted EPUB of the MOBI at [path], whose SHA-256 is [digest]: from
/// the conversion that Bookfin kept, else from a new conversion.
Future<Publication> _convert(String path, String digest) async {
  final original = File(path);
  if (await original.length() > Publication.maxArchiveBytes) {
    throw const FormatException(
      'This MOBI exceeds the 64 MiB import limit. The original download was kept.',
    );
  }
  final cacheRoot = DerivedBookFiles.mobiDirectory(original);
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
  final destination = _conversionOf(original, digest);
  final cached = await _cached(destination, digest);
  if (cached != null) return cached;
  final work = await cacheRoot.createTemp('conversion-');
  try {
    final input = await original.copy('${work.path}/book.mobi');
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
    final epub = sha256.convert(converted).toString();
    final publication = Publication.admit(converted, epub);
    await input.delete();
    await File('${work.path}/manifest.json').writeAsString(
      jsonEncode({
        'version': 1,
        'original': digest,
        'policy': EpubDocument.mobiPolicy,
        'epub': epub,
      }),
      flush: true,
    );
    if (await destination.exists()) await destination.delete(recursive: true);
    await work.rename(destination.path);
    return publication;
  } on ArgumentError {
    throw const FormatException(
      'The bundled MOBI converter is unavailable in this build. The original download was kept.',
    );
  } finally {
    if (await work.exists()) await work.delete(recursive: true);
  }
}

Future<Publication?> _cached(Directory folder, String digest) async {
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
    final epub = sha256.convert(bytes).toString();
    if (manifest is! Map ||
        manifest['version'] != 1 ||
        manifest['original'] != digest ||
        manifest['policy'] != EpubDocument.mobiPolicy ||
        manifest['epub'] != epub) {
      return null;
    }
    return Publication.admit(bytes, epub);
  } on Exception {
    return null;
  }
}
