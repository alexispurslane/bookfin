// The kept page of each downloaded EPUB or MOBI book (boo-sy2d): the drawn
// form of the last page that the reader showed of it, which a reopen of the
// book draws before the book loads.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;

import '../catalog/model.dart';
import '../downloads/derived_files.dart';
import '../downloads/downloads.dart';
import '../playback/records.dart' show encodeTextPosition;
import 'epub/kept_page.dart';
import 'epub/publication.dart';

/// Keeps one page of each download: the file `last-page` in the download's
/// layout directory ([DerivedBookFiles.layoutDirectory]), which a removal
/// of the download removes.
///
/// The file holds three lines: its key, the CRC-32 of its body, and the
/// body, a text that [KeptPage.encode] wrote. The key names everything that
/// changes the page outside its body: the format of the body, the text
/// engine and its fonts ([engine]), the admission revision
/// ([Publication.revision], which decides the characters that draw in a
/// book's own fonts), the downloaded file's digest, and the saved place
/// that the page shows. The body holds the page settings. A
/// read with another key, or of a body that does not match its CRC-32,
/// gives nothing, so a reopen never draws a page that is not the true one.
/// Each write replaces the file whole, unless the file keeps that page
/// already.
class KeptPages {
  KeptPages({required this.engine});

  /// The text engine of this process (`textEngineFingerprint`), or null
  /// when this process cannot name it, as in a debug build: then no page
  /// is kept or read.
  final Future<String?> Function() engine;

  /// The page that [write] kept for the saved place [at] of the download
  /// [original], with its paragraphs built, or null.
  Future<KeptPage?> read(VerifiedFile original, TextPosition at) async {
    final engine = await this.engine();
    if (engine == null) return null;
    final body = await _body(original, _key(engine, original.digest, at));
    return body == null ? null : KeptPage.decode(body);
  }

  /// The body of the kept file of [original] when its key is [key] and the
  /// body matches its CRC-32, or null.
  static Future<String?> _body(VerifiedFile original, Uint8List key) async {
    final Uint8List bytes;
    try {
      bytes = await _fileOf(original).readAsBytes();
    } on FileSystemException {
      return null;
    }
    final keyEnd = bytes.indexOf(_newline);
    if (keyEnd != key.length || !_same(bytes, key)) return null;
    final crcEnd = bytes.indexOf(_newline, keyEnd + 1);
    if (crcEnd < 0) return null;
    final body = Uint8List.sublistView(bytes, crcEnd + 1);
    // The body is a few kilobytes. Its CRC-32 takes microseconds, much less
    // than a hop to a worker.
    final crc = int.tryParse(
      latin1.decode(Uint8List.sublistView(bytes, keyEnd + 1, crcEnd)),
    );
    if (crc != getCrc32(body)) return null;
    try {
      return utf8.decode(body);
    } on FormatException {
      return null;
    }
  }

  /// Keeps [body], a text that [KeptPage.encode] wrote, as the page of the
  /// saved place [at] of the download [original], in place of the page
  /// kept before. It writes under a hold of the download
  /// ([VerifiedFile.hold]), which it takes at once, so the read that lent
  /// [original] can end before the write does, and a removal of the
  /// download waits for the write. When the file keeps that page at [at]
  /// already ([KeptPage.alike]), nothing is written. A page that cannot be
  /// written is not kept, so the write does not fail.
  Future<void> write(VerifiedFile original, TextPosition at, String body) =>
      original.hold(() async {
        final engine = await this.engine();
        if (engine == null) return;
        final key = _key(engine, original.digest, at);
        if (await _body(original, key) case final kept?
            when KeptPage.alike(kept, body)) {
          return;
        }
        final encoded = utf8.encode(body);
        final bytes = BytesBuilder(copy: false)
          ..add(key)
          ..addByte(_newline)
          ..add(latin1.encode('${getCrc32(encoded)}'))
          ..addByte(_newline)
          ..add(encoded);
        try {
          await DerivedBookFiles.write(_fileOf(original), bytes.takeBytes());
        } on FileSystemException {
          // The next reopen shows no kept page, and its next page is kept.
        }
      });

  static File _fileOf(VerifiedFile original) => File(
    '${DerivedBookFiles.layoutDirectory(File.fromUri(original.uri)).path}'
    '/last-page',
  );

  /// The key line of a page of the saved place [at] in the download whose
  /// bytes have the SHA-256 [digest], drawn by the text engine [engine].
  /// JSON keeps the line breaks of [engine] out of the line.
  static Uint8List _key(String engine, String digest, TextPosition at) =>
      utf8.encode(
        jsonEncode([
          KeptPage.format,
          engine,
          Publication.revision,
          digest,
          encodeTextPosition(at),
        ]),
      );

  static bool _same(Uint8List bytes, Uint8List key) {
    for (var index = 0; index < key.length; index++) {
      if (bytes[index] != key[index]) return false;
    }
    return true;
  }

  static const _newline = 0x0a;
}
