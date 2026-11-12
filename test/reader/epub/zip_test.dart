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
Uint8List withEntry(Uint8List archive, String name, {int? size, int? crc}) {
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

/// The EPUB [archive] with the general purpose [flags] of [name], in its
/// directory entry and in its local header.
Uint8List withFlags(Uint8List archive, String name, int flags) {
  final bytes = Uint8List.fromList(archive);
  final data = ByteData.sublistView(bytes);
  final wanted = utf8.encode(name);
  var found = 0;
  for (var at = 0; at + 46 <= bytes.length; at++) {
    final signature = data.getUint32(at, Endian.little);
    final (flagsAt, nameAt) = switch (signature) {
      0x02014b50 => (at + 8, at + 46),
      0x04034b50 => (at + 6, at + 30),
      _ => (-1, -1),
    };
    if (flagsAt < 0) continue;
    final length = data.getUint16(
      signature == 0x02014b50 ? at + 28 : at + 26,
      Endian.little,
    );
    if (length != wanted.length ||
        !_same(bytes.sublist(nameAt, nameAt + length), wanted)) {
      continue;
    }
    data.setUint16(flagsAt, flags, Endian.little);
    found++;
  }
  if (found != 2) throw StateError('$name is not in the archive.');
  return bytes;
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

  // A chapter that fails the ZIP check shows a note instead of its text
  // (t5-gk30), so admission keeps none of its bytes.
  group('admission keeps none of the bytes of a chapter', () {
    /// The chapter of [publication].
    String chapter(Publication publication) =>
        utf8.decode(publication.textFiles['OPS/one.xhtml']!);

    test('whose entry expands past the size that its directory gives', () {
      // The chapter expands to far more than 1,000 bytes, but stays below
      // the ratio limit that the directory alone can show.
      final book = epub(chapter: '<html><body>${' ' * 2000000}</body></html>');

      final publication = Publication.admit(
        withEntry(book, 'OPS/one.xhtml', size: 1000),
      );

      expect(chapter(publication), contains('could not be read'));
      expect(chapter(publication).length, lessThan(1000));
    });

    test('whose entry does not have the CRC-32 that its directory gives', () {
      final book = epub();
      final start = utf8.encode(
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>River</title>',
      );

      final publication = Publication.admit(
        withEntry(book, 'OPS/one.xhtml', crc: getCrc32(start)),
      );

      expect(chapter(publication), contains('could not be read'));
      expect(chapter(publication), isNot(contains('A river')));
    });
  });

  test('a file whose ZIP flags name its DEFLATE level is read as it is '
      '(t5-gk30)', () {
    // Bit 1 asks for the best compression. Some EPUB tools set it.
    final publication = Publication.admit(
      withFlags(epub(), 'OPS/one.xhtml', 0x0002),
    );

    expect(
      utf8.decode(publication.textFiles['OPS/one.xhtml']!),
      contains('A river'),
    );
  });

  test('a book whose every file names its DEFLATE level and a UTF-8 name '
      'opens as it is (t5-gk30)', () {
    // One of the user's books sets flags 0x0802 on every file, the stored
    // ones too. Before t5-gk30 this refused the whole book.
    var book = epub();
    for (final file in ZipDecoder().decodeBytes(book).files) {
      book = withFlags(book, file.name, 0x0802);
    }

    final publication = Publication.admit(book);

    expect(
      utf8.decode(publication.textFiles['OPS/one.xhtml']!),
      contains('A river'),
    );
  });

  test('an encrypted file shows the note instead of its bytes (t5-gk30)', () {
    final publication = Publication.admit(
      withFlags(epub(), 'OPS/one.xhtml', 0x0001),
    );

    expect(
      utf8.decode(publication.textFiles['OPS/one.xhtml']!),
      contains('could not be read'),
    );
  });

  test('a book whose encryption.xml fails the ZIP check is still refused as '
      'encrypted (t5-gk30)', () {
    final book = epub(
      extra: {'META-INF/encryption.xml': utf8.encode('<encryption/>')},
    );

    expect(
      () => Publication.admit(
        withEntry(book, 'META-INF/encryption.xml', crc: 0x12345678),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Encrypted'),
        ),
      ),
    );
  });

  test('a book from disk still admits whole', () {
    final publication = Publication.admit(
      File('test/reader/fixtures/broken-image.epub').readAsBytesSync(),
    );

    publication.checkInvariants();
    expect(publication.spine, isNotEmpty);
  });
}
