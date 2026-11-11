// Admission keeps a PNG or JPEG image only when its header gives one
// frame of at least 1 and at most 16 million pixels, and keeps the image's
// width and height for layout (publication.dart). It reads them from the
// header with its own code (image_size.dart), which accepts and refuses
// what package:image's header decoders accepted and refused before
// boo-yjq6, and gives the same sizes.
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show ZipDecoder;
import 'package:bookfin/reader/epub/image_size.dart';
import 'package:bookfin/reader/epub/zip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

/// The size that admission kept before boo-yjq6, from package:image.
(int, int)? _before(Uint8List bytes, String mime) {
  try {
    final raster.Decoder decoder = mime == 'image/png'
        ? raster.PngDecoder()
        : raster.JpegDecoder();
    final info = decoder.startDecode(bytes);
    if (info == null ||
        info.width < 1 ||
        info.height < 1 ||
        info.width * info.height > 16000000 ||
        info.numFrames != 1) {
      return null;
    }
    return (info.width, info.height);
  } catch (_) {
    return null;
  }
}

/// Expects that admission keeps no size for [bytes], before and now.
void _expectRefused(List<int> bytes, String mime) {
  final image = Uint8List.fromList(bytes);
  expect(_before(image, mime), isNull, reason: 'package:image');
  expect(rasterSize(image, mime), isNull);
}

/// [bytes] with the chunk CRC of the PNG chunk at [at] made right again.
Uint8List _withChunkCrc(Uint8List bytes, int at) {
  final data = ByteData.sublistView(bytes);
  final length = data.getUint32(at);
  data.setUint32(
    at + 8 + length,
    crc32(Uint8List.sublistView(bytes, at + 4, at + 8 + length)),
  );
  return bytes;
}

Uint8List _png(int width, int height) =>
    raster.encodePng(raster.Image(width: width, height: height));

/// A JPEG of the [segments] between its start and end markers.
List<int> _jpeg(List<List<int>> segments) => [
  0xff,
  0xd8,
  for (final segment in segments) ...segment,
  0xff,
  0xd9,
];

/// The segment of [marker] that holds [data].
List<int> _segment(int marker, List<int> data) => [
  0xff,
  marker,
  (data.length + 2) >> 8,
  (data.length + 2) & 0xff,
  ...data,
];

/// A start of frame of [marker], [width] by [height], with one component
/// for each sampling byte of [sampling].
List<int> _frame(
  int width,
  int height, {
  int marker = 0xc0,
  List<int> sampling = const [0x11],
}) => _segment(marker, [
  8,
  height >> 8,
  height & 0xff,
  width >> 8,
  width & 0xff,
  sampling.length,
  for (var index = 0; index < sampling.length; index++) ...[
    index + 1,
    sampling[index],
    0,
  ],
]);

/// A start of scan and a few bytes of scan data.
final _scan = [
  ..._segment(0xda, [1, 1, 0, 0, 63, 0]),
  0x12,
  0x34,
  0x56,
];

void main() {
  group('a PNG', () {
    test('gives the size in its header', () {
      expect(rasterSize(_png(40, 30), 'image/png'), (40, 30));
    });

    test('is refused without the PNG signature', () {
      _expectRefused(_png(4, 3).sublist(1), 'image/png');
    });

    test('is refused when it ends before its end chunk', () {
      final png = _png(4, 3);
      _expectRefused(png.sublist(0, png.length - 12), 'image/png');
    });

    test('is refused when its header chunk fails its checksum', () {
      final png = _png(4, 3)..[16] ^= 1;
      _expectRefused(png, 'image/png');
    });

    test('is refused when its header names a bit depth that its color '
        'type does not have', () {
      // RGB at 4 bits a sample.
      final png = _withChunkCrc(_png(4, 3)..[24] = 4, 8);
      _expectRefused(png, 'image/png');
    });

    test('is refused when its header names no width', () {
      final png = _withChunkCrc(_png(4, 3)..setRange(16, 20, [0, 0, 0, 0]), 8);
      _expectRefused(png, 'image/png');
    });

    test('is refused when it animates more than one frame', () {
      final animation = raster.Image(width: 4, height: 3)
        ..addFrame(raster.Image(width: 4, height: 3));
      _expectRefused(raster.encodePng(animation), 'image/png');
    });

    test('is refused with more than 16 million pixels', () {
      _expectRefused(_png(5000, 3201), 'image/png');
    });

    test('of exactly 16 million pixels is kept', () {
      final png = _withChunkCrc(
        _png(4, 3)..setRange(16, 24, [0, 0, 0x0f, 0xa0, 0, 0, 0x0f, 0xa0]),
        8,
      );
      expect(_before(png, 'image/png'), (4000, 4000));
      expect(rasterSize(png, 'image/png'), (4000, 4000));
    });
  });

  group('a JPEG', () {
    test('gives the size in its frame header', () {
      final jpeg = raster.encodeJpg(raster.Image(width: 40, height: 30));
      expect(rasterSize(jpeg, 'image/jpeg'), (40, 30));
    });

    test('gives the size of a progressive frame', () {
      final jpeg = Uint8List.fromList(
        _jpeg([_frame(640, 480, marker: 0xc2), _scan]),
      );
      expect(_before(jpeg, 'image/jpeg'), (640, 480));
      expect(rasterSize(jpeg, 'image/jpeg'), (640, 480));
    });

    test('gives the size of its own frame, not of a thumbnail in its '
        'metadata', () {
      final thumbnail = _jpeg([_frame(16, 12), _scan]);
      final jpeg = Uint8List.fromList(
        _jpeg([
          _segment(0xe1, [...'Exif'.codeUnits, 0, 0, ...thumbnail]),
          _frame(800, 600),
          _scan,
        ]),
      );
      expect(_before(jpeg, 'image/jpeg'), (800, 600));
      expect(rasterSize(jpeg, 'image/jpeg'), (800, 600));
    });

    test('is refused without the start of image', () {
      _expectRefused([0x00, 0x00, ..._frame(8, 8), ..._scan], 'image/jpeg');
    });

    test('is refused without a frame header', () {
      _expectRefused(_jpeg([_scan]), 'image/jpeg');
    });

    test('is refused without a scan', () {
      _expectRefused(_jpeg([_frame(8, 8)]), 'image/jpeg');
    });

    test('is refused when its only frame is lossless', () {
      _expectRefused(_jpeg([_frame(8, 8, marker: 0xc3), _scan]), 'image/jpeg');
    });

    test('is refused with two frame headers', () {
      _expectRefused(_jpeg([_frame(8, 8), _frame(8, 8), _scan]), 'image/jpeg');
    });

    test('is refused when its frame header is cut short', () {
      _expectRefused(
        _jpeg([
          _segment(0xc0, [8, 0, 8, 0, 8, 3, 1, 0x11]),
          _scan,
        ]),
        'image/jpeg',
      );
    });

    test('is refused when a segment names a length below 2', () {
      _expectRefused(
        _jpeg([
          [0xff, 0xe0, 0, 1],
          _frame(8, 8),
          _scan,
        ]),
        'image/jpeg',
      );
    });

    test('is refused when its frame has no sampling', () {
      _expectRefused(
        _jpeg([
          _frame(8, 8, sampling: [0x00]),
          _scan,
        ]),
        'image/jpeg',
      );
    });

    test('is refused when its frame names no width', () {
      _expectRefused(_jpeg([_frame(0, 8), _scan]), 'image/jpeg');
    });

    test('is refused with more than 16 million pixels', () {
      _expectRefused(_jpeg([_frame(5000, 3201), _scan]), 'image/jpeg');
    });
  });

  test(
    'every PNG and JPEG of the corpus books gets the size that package:image '
    'gave',
    () {
      var images = 0;
      for (final book in Directory('.cache/epub-corpus/books').listSync()) {
        if (!book.path.endsWith('.epub')) continue;
        final archive = ZipDecoder().decodeBytes(
          File(book.path).readAsBytesSync(),
        );
        for (final file in archive.files) {
          final bytes = file.content;
          final mime = switch (file.name.split('.').last.toLowerCase()) {
            'png' => 'image/png',
            'jpg' || 'jpeg' => 'image/jpeg',
            _ => null,
          };
          if (mime == null) continue;
          expect(
            rasterSize(bytes, mime),
            _before(bytes, mime),
            reason: '${book.path} ${file.name}',
          );
          images++;
        }
      }
      expect(images, greaterThan(900));
    },
    skip: Platform.environment['BOOKFIN_EPUB_CORPUS'] == '1'
        ? null
        : 'set BOOKFIN_EPUB_CORPUS=1 with the corpus in '
              '.cache/epub-corpus/books to run',
  );
}
