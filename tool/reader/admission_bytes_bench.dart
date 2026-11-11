// Tool code: an on-demand host benchmark of admission's byte work, the old
// way against the new way (boo-yjq6). It is not part of Bookfin.
//
// It compares, on the entries of each book:
//
// - inflate: package:archive's Inflate against inflateEntry (zip.dart).
// - CRC-32: package:archive's getCrc32 against crc32 (zip.dart), on every
//   expanded entry.
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
import 'package:bookfin/reader/epub/zip.dart';

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
    stdout.writeln(
      '${path.split('/').last}: inflate of ${deflated.length} entries '
      '$oldInflate -> $newInflate ms; CRC-32 of ${expanded.length} entries '
      '$oldCrc -> $newCrc ms',
    );
  }
}
