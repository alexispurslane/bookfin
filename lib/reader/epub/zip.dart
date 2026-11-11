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
