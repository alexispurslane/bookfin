import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../downloads/derived_files.dart';

Future<Directory> _directory(Uri original, String digest) async {
  final file = File.fromUri(original);
  if (original.scheme != 'file' ||
      original.host.isNotEmpty ||
      await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      (await sha256.bind(file.openRead()).first).toString() != digest) {
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

Future<String?> readOcrCache(Uri original, String digest, String key) async {
  final directory = await _directory(original, digest);
  final file = File('${directory.path}/$key.json');
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() > 8000000) {
    return null;
  }
  try {
    final value = jsonDecode(await file.readAsString());
    if (value is! Map ||
        value['key'] != key ||
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

Future<void> writeOcrCache(
  Uri original,
  String digest,
  String key,
  String hocr,
  bool Function() live,
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
  try {
    await pending.writeAsString(
      jsonEncode({
        'key': key,
        'hocr': hocr,
        'sha256': sha256.convert(utf8.encode(hocr)).toString(),
      }),
      flush: true,
    );
    if (live()) pending.renameSync(file.path);
  } finally {
    if (await pending.exists()) await pending.delete();
  }
}
