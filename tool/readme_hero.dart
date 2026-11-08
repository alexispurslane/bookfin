// Composes the README hero image: three phone screenshots side by side on
// the cream page color, each with rounded corners and a soft shadow. The
// middle phone sits a little higher than the other two.
//
// nix develop --command dart run tool/readme_hero.dart \
//   docs/screenshots/hero.png left.png middle.png right.png
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

const _phoneWidth = 420;
const _gap = 48;
const _margin = 72;
const _lift = 56;
const _radius = 34;
const _cream = (0xF6, 0xEF, 0xE3);
const _sand = (0xEA, 0xDC, 0xC6);
const _shadow = (0x5A, 0x3E, 0x26);

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    stderr.writeln('Usage: readme_hero.dart <out.png> <left> <middle> <right>');
    exit(64);
  }
  final phones = [
    for (final path in arguments.skip(1))
      _rounded(
        img.copyResize(
          img.decodeImage(await File(path).readAsBytes())!,
          width: _phoneWidth,
          interpolation: img.Interpolation.average,
        ),
      ),
  ];
  final phoneHeight = phones.map((phone) => phone.height).reduce(max);
  final width = _margin * 2 + _phoneWidth * 3 + _gap * 2;
  final height = _margin * 2 + phoneHeight + _lift;
  final canvas = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    final t = y / (height - 1);
    int mix(int a, int b) => (a + (b - a) * t).round();
    img.drawLine(
      canvas,
      x1: 0,
      y1: y,
      x2: width - 1,
      y2: y,
      color: img.ColorRgba8(
        mix(_cream.$1, _sand.$1),
        mix(_cream.$2, _sand.$2),
        mix(_cream.$3, _sand.$3),
        255,
      ),
    );
  }
  for (var i = 0; i < 3; i++) {
    final x = _margin + i * (_phoneWidth + _gap);
    final y = _margin + (i == 1 ? 0 : _lift);
    final shadow = _shadowOf(phones[i]);
    img.compositeImage(canvas, shadow, dstX: x - 30, dstY: y - 6);
    img.compositeImage(canvas, phones[i], dstX: x, dstY: y);
  }
  await File(arguments.first).writeAsBytes(img.encodePng(canvas, level: 9));
}

/// The screenshot with transparent rounded corners.
img.Image _rounded(img.Image source) {
  final phone = source.convert(numChannels: 4);
  for (var y = 0; y < phone.height; y++) {
    for (var x = 0; x < phone.width; x++) {
      final cx = x < _radius
          ? _radius - x - 0.5
          : x >= phone.width - _radius
          ? x - (phone.width - _radius) + 0.5
          : 0.0;
      final cy = y < _radius
          ? _radius - y - 0.5
          : y >= phone.height - _radius
          ? y - (phone.height - _radius) + 0.5
          : 0.0;
      if (cx == 0 || cy == 0) continue;
      final coverage = (_radius - sqrt(cx * cx + cy * cy) + 0.5).clamp(0, 1);
      final pixel = phone.getPixel(x, y);
      pixel.a = (pixel.a * coverage).round();
    }
  }
  return phone;
}

/// A blurred, warm-brown silhouette of [phone], padded by 30 pixels on
/// each side and moved 24 pixels down, for a soft drop shadow.
img.Image _shadowOf(img.Image phone) {
  const pad = 30;
  final shadow = img.Image(
    width: phone.width + pad * 2,
    height: phone.height + pad * 2,
    numChannels: 4,
  );
  for (var y = 0; y < phone.height; y++) {
    for (var x = 0; x < phone.width; x++) {
      final alpha = phone.getPixel(x, y).a;
      if (alpha == 0) continue;
      shadow.setPixelRgba(
        x + pad,
        y + pad + 24,
        _shadow.$1,
        _shadow.$2,
        _shadow.$3,
        (alpha * 0.32).round(),
      );
    }
  }
  return img.gaussianBlur(shadow, radius: 18);
}
