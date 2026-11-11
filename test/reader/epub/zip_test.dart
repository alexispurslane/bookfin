// Admission unzips each entry of an EPUB under the limits of its ZIP
// directory: an entry must expand to exactly the size and the CRC-32 that
// the directory gives, and no entry may expand past its size, so a small
// archive cannot fill the phone's memory (a ZIP bomb).
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' show ZipDecoder, getCrc32;
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

  group('the CRC-32 of an entry', () {
    test('of the standard check bytes is the standard check value', () {
      expect(crc32(Uint8List.fromList(utf8.encode('123456789'))), 0xcbf43926);
    });

    test('of no bytes is 0', () {
      expect(crc32(Uint8List(0)), 0);
    });

    test('is the CRC-32 that package:archive gives, at every length and '
        'start in a word', () {
      final bytes = _noise(1 << 20);
      for (var start = 0; start < 8; start++) {
        for (final length in [
          for (var length = 0; length <= 40; length++) length,
          4093,
          (1 << 20) - 8,
        ]) {
          final part = Uint8List.sublistView(bytes, start, start + length);
          expect(crc32(part), getCrc32(part), reason: '$start, $length');
        }
      }
    });

    test(
      'of every entry of every corpus book is the CRC-32 that '
      'package:archive gives',
      () {
        var entries = 0;
        for (final book in Directory('.cache/epub-corpus/books').listSync()) {
          if (!book.path.endsWith('.epub')) continue;
          final archive = ZipDecoder().decodeBytes(
            File(book.path).readAsBytesSync(),
          );
          for (final file in archive.files) {
            final bytes = file.content;
            expect(
              crc32(bytes),
              getCrc32(bytes),
              reason: '${book.path} ${file.name}',
            );
            entries++;
          }
        }
        expect(entries, greaterThan(1000));
      },
      skip: Platform.environment['BOOKFIN_EPUB_CORPUS'] == '1'
          ? null
          : 'set BOOKFIN_EPUB_CORPUS=1 with the corpus in '
                '.cache/epub-corpus/books to run',
    );
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
