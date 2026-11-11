// Admission unzips each entry of an EPUB under the limits of its ZIP
// directory: an entry must expand to exactly the size and the CRC-32 that
// the directory gives, and no entry may expand past its size, so a small
// archive cannot fill the phone's memory (a ZIP bomb).
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/epub/zip.dart';
import 'package:flutter_test/flutter_test.dart';

import '../publication_test.dart' show epub;

/// [bytes] as raw DEFLATE data, as a ZIP entry holds them.
Uint8List _deflated(List<int> bytes) =>
    Uint8List.fromList(ZLibEncoder(raw: true).convert(bytes));

/// Bytes that do not repeat, so that they do not compress to nothing.
Uint8List _noise(int length) {
  final random = Random(7);
  return Uint8List.fromList([
    for (var index = 0; index < length; index++) random.nextInt(256),
  ]);
}

/// The EPUB [archive] with the central directory entry of [name] changed:
/// its uncompressed [size] and its [crc].
Uint8List _withEntry(Uint8List archive, String name, {int? size, int? crc}) {
  final bytes = Uint8List.fromList(archive);
  final data = ByteData.sublistView(bytes);
  final wanted = utf8.encode(name);
  for (var at = 0; at + 46 <= bytes.length; at++) {
    if (data.getUint32(at, Endian.little) != 0x02014b50) continue;
    final length = data.getUint16(at + 28, Endian.little);
    if (length != wanted.length ||
        !_same(bytes.sublist(at + 46, at + 46 + length), wanted)) {
      continue;
    }
    if (crc != null) data.setUint32(at + 16, crc, Endian.little);
    if (size != null) data.setUint32(at + 24, size, Endian.little);
    return bytes;
  }
  throw StateError('$name is not in the archive.');
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

void main() {
  group('inflating an entry', () {
    test('gives the bytes that were deflated', () {
      final bytes = _noise(300000);

      expect(inflateEntry(_deflated(bytes), bytes.length), bytes);
    });

    test('gives an empty entry for an empty stream', () {
      expect(inflateEntry(_deflated(const []), 0), isEmpty);
    });

    test('refuses an entry that expands past its declared size', () {
      // 64 MiB of zeros deflate to about 64 KiB.
      final bomb = _deflated(Uint8List(64 * 1024 * 1024));

      expect(() => inflateEntry(bomb, 1000), throwsFormatException);
    });

    test('refuses an entry that expands to fewer bytes than its size', () {
      final bytes = _noise(5000);

      expect(
        () => inflateEntry(_deflated(bytes), bytes.length + 1),
        throwsFormatException,
      );
    });

    test('refuses a stream that is cut short', () {
      final deflated = _deflated(_noise(5000));

      expect(
        () => inflateEntry(Uint8List.sublistView(deflated, 0, 2000), 5000),
        throwsFormatException,
      );
    });

    test('refuses data that is not a DEFLATE stream', () {
      expect(
        () => inflateEntry(Uint8List.fromList(List.filled(64, 0xff)), 100),
        throwsFormatException,
      );
    });
  });

  group('admission refuses a book', () {
    test('whose entry expands past the size that its directory gives', () {
      // The chapter expands to far more than 1,000 bytes, but stays below
      // the ratio limit that the directory alone can show.
      final book = epub(chapter: '<html><body>${' ' * 2000000}</body></html>');

      expect(
        () => Publication.admit(_withEntry(book, 'OPS/one.xhtml', size: 1000)),
        throwsFormatException,
      );
    });

    test('whose entry does not have the CRC-32 that its directory gives', () {
      final book = epub();
      final chapter = utf8.encode(
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>River</title>',
      );

      expect(
        () => Publication.admit(
          _withEntry(book, 'OPS/one.xhtml', crc: getCrc32(chapter)),
        ),
        throwsFormatException,
      );
    });
  });

  test('a book from disk still admits whole', () {
    final publication = Publication.admit(
      File('test/reader/fixtures/broken-image.epub').readAsBytesSync(),
    );

    publication.checkInvariants();
    expect(publication.spine, isNotEmpty);
  });
}
