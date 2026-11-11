// The byte work of reading one ZIP entry, which admission
// (publication.dart) does for every entry of a book. It uses no dart:ui, so
// a worker isolate or a plain Dart program can run it.
import 'dart:io';
import 'dart:typed_data';

/// The [size] bytes that the raw DEFLATE stream [deflated] of a ZIP entry
/// expands to.
///
/// Throws a [FormatException] when the stream is damaged, or when it
/// expands to more or fewer bytes than [size]. It stops as soon as the
/// output passes [size], so a stream that expands far past it (a ZIP bomb)
/// costs at most [size] bytes and one chunk of memory.
Uint8List inflateEntry(Uint8List deflated, int size) {
  // NOTE: dart:io's zlib is native, 2 to 3 times faster than
  // package:archive's Inflate (docs/plans/faster-book-open.md). Its filter
  // gives the output in chunks of at most 64 KiB, so the limit holds as
  // the bytes come.
  final filter = RawZLibFilter.inflateFilter(raw: true);
  List<int>? next() {
    try {
      return filter.processed(end: true);
    } on Exception {
      throw const FormatException('EPUB resource data is damaged.');
    }
  }

  final output = Uint8List(size);
  var length = 0;
  filter.process(deflated, 0, deflated.length);
  for (var chunk = next(); chunk != null; chunk = next()) {
    if (length + chunk.length > size) {
      throw const FormatException(
        'EPUB decompression exceeds the declared size.',
      );
    }
    output.setRange(length, length += chunk.length, chunk);
  }
  if (length != size) {
    throw const FormatException(
      'EPUB resource checksum or length does not match.',
    );
  }
  return output;
}

/// The CRC-32 of [bytes], as ZIP defines it (the polynomial 0xEDB88320,
/// reflected, with the start and end inverted).
int crc32(Uint8List bytes) {
  // NOTE: Slicing-by-8 (Intel, 2006) reads 8 bytes a step through 8 tables,
  // 4.1 times faster than package:archive's byte at a time on the host
  // (docs/plans/faster-book-open.md). Table k gives the CRC of a byte
  // followed by k zero bytes.
  final t = _crcTables;
  var crc = 0xffffffff;
  var index = 0;
  final words = bytes.length - bytes.length % 8;
  while (index < words) {
    final low =
        crc ^
        (bytes[index] |
            bytes[index + 1] << 8 |
            bytes[index + 2] << 16 |
            bytes[index + 3] << 24);
    crc =
        t[0x700 | low & 0xff] ^
        t[0x600 | low >> 8 & 0xff] ^
        t[0x500 | low >> 16 & 0xff] ^
        t[0x400 | low >> 24] ^
        t[0x300 | bytes[index + 4]] ^
        t[0x200 | bytes[index + 5]] ^
        t[0x100 | bytes[index + 6]] ^
        t[bytes[index + 7]];
    index += 8;
  }
  while (index < bytes.length) {
    crc = t[(crc ^ bytes[index++]) & 0xff] ^ crc >> 8;
  }
  return crc ^ 0xffffffff;
}

/// The 8 tables of [crc32], each of 256 entries, one after the other.
final _crcTables = () {
  final tables = Uint32List(8 * 256);
  for (var byte = 0; byte < 256; byte++) {
    var crc = byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc & 1 == 1 ? 0xedb88320 ^ crc >> 1 : crc >> 1;
    }
    tables[byte] = crc;
  }
  for (var table = 1; table < 8; table++) {
    for (var byte = 0; byte < 256; byte++) {
      final before = tables[(table - 1) << 8 | byte];
      tables[table << 8 | byte] = tables[before & 0xff] ^ before >> 8;
    }
  }
  return tables;
}();
