// Tool code: an on-demand host benchmark of admission's byte work, the old
// way against the new way (boo-yjq6). It is not part of Bookfin.
//
// It compares, on the entries of each book:
//
// - inflate: package:archive's Inflate against inflateEntry (zip.dart).
// - CRC-32: package:archive's getCrc32 against crc32 (zip.dart), on every
//   expanded entry.
// - image headers: package:image's startDecode against rasterSize
//   (image_size.dart), on every PNG and JPEG.
// - identity: the SHA-256 of every expanded entry, about the admitted files
//   that the identity hashed before boo-yjq6, against the one SHA-256 of
//   the policy, the revision and the digest.
//
// In the dev shell, from the repository root, compile it ahead of time, as
// the app runs, and run it on the books of docs/plans/faster-book-open.md:
//
//   dart compile exe tool/reader/admission_bytes_bench.dart -o /tmp/bench
//   /tmp/bench <book.epub>...
//
// It prints one line per book: the median of 7 rounds of each measure, in
// milliseconds.
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart'
    show Inflate, OutputMemoryStream, getCrc32;
import 'package:bookfin/reader/epub/image_size.dart';
import 'package:bookfin/reader/epub/zip.dart';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as raster;

/// One entry of a book's ZIP directory.
typedef _Entry = ({bool deflated, Uint8List content, int size});

List<_Entry> _entries(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  int word(int offset) => data.getUint16(offset, Endian.little);
  int integer(int offset) => data.getUint32(offset, Endian.little);
  var end = bytes.length - 22;
  while (integer(end) != 0x06054b50) {
    end--;
  }
  var cursor = integer(end + 16);
  return [
    for (var index = 0; index < word(end + 10); index++)
      () {
        final local = integer(cursor + 42);
        final start = local + 30 + word(local + 26) + word(local + 28);
        final entry = (
          deflated: word(cursor + 10) == 8,
          content: Uint8List.sublistView(
            bytes,
            start,
            start + integer(cursor + 20),
          ),
          size: integer(cursor + 24),
        );
        cursor +=
            46 + word(cursor + 28) + word(cursor + 30) + word(cursor + 32);
        return entry;
      }(),
  ];
}

double _median(void Function() body) {
  final times = <int>[];
  for (var round = 0; round < 7; round++) {
    final watch = Stopwatch()..start();
    body();
    times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  return times[times.length ~/ 2] / 1000;
}

void main(List<String> paths) {
  for (final path in paths) {
    final entries = _entries(File(path).readAsBytesSync());
    final deflated = entries.where((entry) => entry.deflated).toList();
    final oldInflate = _median(() {
      for (final entry in deflated) {
        Inflate(
          Uint8List.fromList(entry.content),
          output: OutputMemoryStream(size: entry.size),
        );
      }
    });
    final newInflate = _median(() {
      for (final entry in deflated) {
        inflateEntry(entry.content, entry.size);
      }
    });
    final expanded = [
      for (final entry in entries)
        entry.deflated
            ? inflateEntry(entry.content, entry.size)
            : entry.content,
    ];
    final oldCrc = _median(() {
      for (final bytes in expanded) {
        getCrc32(bytes);
      }
    });
    final newCrc = _median(() {
      for (final bytes in expanded) {
        crc32(bytes);
      }
    });
    final images = [
      for (final bytes in expanded)
        if (bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50)
          (bytes, 'image/png')
        else if (bytes.length > 3 && bytes[0] == 0xff && bytes[1] == 0xd8)
          (bytes, 'image/jpeg'),
    ];
    final oldHeaders = _median(() {
      for (final (bytes, mime) in images) {
        (mime == 'image/png' ? raster.PngDecoder() : raster.JpegDecoder())
            .startDecode(bytes);
      }
    });
    final newHeaders = _median(() {
      for (final (bytes, mime) in images) {
        rasterSize(bytes, mime);
      }
    });
    final oldIdentity = _median(() {
      for (final bytes in expanded) {
        sha256.convert(bytes);
      }
    });
    final newIdentity = _median(() {
      sha256.convert('bookfin-passive-epub-1/3/${'0' * 64}'.codeUnits);
    });
    stdout.writeln(
      '${path.split('/').last}: identity $oldIdentity -> $newIdentity ms',
    );
    stdout.writeln(
      '${path.split('/').last}: inflate of ${deflated.length} entries '
      '$oldInflate -> $newInflate ms; CRC-32 of ${expanded.length} entries '
      '$oldCrc -> $newCrc ms; headers of ${images.length} images '
      '$oldHeaders -> $newHeaders ms',
    );
  }
}
