// The size of a PNG or JPEG image from its header, which admission
// (publication.dart) keeps for layout. It uses no dart:ui, so a worker
// isolate or a plain Dart program can run it.
//
// It accepts and refuses what package:image's header decoders did before
// boo-yjq6, with the same sizes on every image of the corpus
// (image_size_test.dart). package:image's JPEG header decoder read every
// byte of the image and allocated the blocks of every pixel, 189 ms for the
// 30 MB of JPEG images of the Divine Comedy on the phone
// (docs/plans/faster-book-open.md). This code reads the segments up to the
// first scan. Admission does not decode the pixels: the page draws an
// image's alt text when the platform cannot decode them.
import 'dart:typed_data';

import 'zip.dart' show crc32;

/// The width and height in pixels of the PNG or JPEG [bytes], whose media
/// type is [mime], from its header. Null when the header is unreadable,
/// the image has more than one frame, or it has fewer than 1 or more than
/// 16 million pixels.
(int, int)? rasterSize(Uint8List bytes, String mime) {
  final size = mime == 'image/png' ? _pngSize(bytes) : _jpegSize(bytes);
  if (size == null) return null;
  final (width, height) = size;
  return width < 1 || height < 1 || width * height > 16000000 ? null : size;
}

/// The size in the header of the single-frame PNG [bytes], or null.
///
/// It walks the chunks to the end chunk. It checks the header chunk: its
/// checksum, its color type, the bit depth of that color type and its
/// filter method. It checks the checksums of the palette and transparency
/// chunks, and it reads the frame count of an animation control chunk.
(int, int)? _pngSize(Uint8List bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 8) return null;
  for (var index = 0; index < 8; index++) {
    if (bytes[index] != signature[index]) return null;
  }
  final data = ByteData.sublistView(bytes);
  (int, int)? size;
  var frames = 1;
  var at = 8;
  while (at + 8 <= bytes.length) {
    final length = data.getUint32(at);
    final type = String.fromCharCodes(bytes, at + 4, at + 8);
    final start = at + 8;
    final end = start + length;
    if (end + 4 > bytes.length) return null;
    bool sound() =>
        crc32(Uint8List.sublistView(bytes, at + 4, end)) == data.getUint32(end);
    switch (type) {
      case 'IHDR':
        if (length < 13 || !sound()) return null;
        final depth = bytes[start + 8];
        final depths = switch (bytes[start + 9]) {
          0 => const [1, 2, 4, 8, 16],
          3 => const [1, 2, 4, 8],
          2 || 4 || 6 => const [8, 16],
          _ => const <int>[],
        };
        if (!depths.contains(depth) || bytes[start + 11] != 0) return null;
        size = (data.getUint32(start), data.getUint32(start + 4));
      case 'PLTE' || 'tRNS':
        if (!sound()) return null;
      case 'acTL':
        if (length < 4) return null;
        frames = data.getUint32(start);
      case 'IEND':
        return frames == 1 ? size : null;
    }
    at = end + 4;
  }
  return null;
}

/// The size in the frame header of the JPEG [bytes], or null.
///
/// It reads the segments from the start of the image to the first scan.
/// The image needs one frame header of a baseline, extended or progressive
/// frame, with at least one component that samples, before its first scan.
(int, int)? _jpegSize(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) return null;
  (int, int)? size;
  var at = 2;
  while (true) {
    // A marker is 0xFF, any number of fill bytes 0xFF, and the marker's
    // code. Other bytes before it are skipped, as package:image did.
    while (at < bytes.length && bytes[at] != 0xff) {
      at++;
    }
    while (at < bytes.length && bytes[at] == 0xff) {
      at++;
    }
    if (at + 3 > bytes.length) return null;
    final marker = bytes[at];
    final length = bytes[at + 1] << 8 | bytes[at + 2];
    final start = at + 3;
    final end = at + 1 + length;
    if (marker == 0xd9 || length < 2 || end > bytes.length) return null;
    switch (marker) {
      case 0xc0 || 0xc1 || 0xc2:
        final components = length >= 8 ? bytes[start + 5] : 0;
        if (size != null || length < 8 + 3 * components) return null;
        var horizontal = 0;
        var vertical = 0;
        for (var index = 0; index < components; index++) {
          final sampling = bytes[start + 7 + 3 * index];
          horizontal |= sampling >> 4;
          vertical |= sampling & 0xf;
        }
        if (horizontal == 0 || vertical == 0) return null;
        size = (
          bytes[start + 3] << 8 | bytes[start + 4],
          bytes[start + 1] << 8 | bytes[start + 2],
        );
      case 0xda:
        return size;
    }
    at = end;
  }
}
