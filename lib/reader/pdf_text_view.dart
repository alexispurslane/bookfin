import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'screen_cut.dart';

/// One source page's reading text, laid out and cut into whole-line screens.
/// Character offsets name the displayed text; the viewport maps them back to
/// the source text when it saves a place. Empty lines remain paragraph gaps
/// within screens, but cannot become a screen's first line.
class PdfTextScreens {
  PdfTextScreens({
    required this.text,
    required this.style,
    required this.size,
  }) {
    _painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    final tops = <double>[];
    final bottoms = <double>[];
    for (final line in _painter.computeLineMetrics()) {
      final range = _painter.getLineBoundary(
        _painter.getPositionForOffset(Offset(line.left, line.baseline)),
      );
      if (text.substring(range.start, range.end).trim().isEmpty) continue;
      _characters.add(range.start);
      tops.add(line.baseline - line.ascent);
      bottoms.add(line.baseline + line.descent);
    }
    _tops = tops;
    _screens = cutScreens(
      tops,
      bottoms,
      List.filled(tops.length, false),
      size.height,
    );
  }

  final String text;
  final TextStyle style;
  final Size size;
  late final TextPainter _painter;
  final _characters = <int>[];
  late final List<double> _tops;
  late final Int32List _screens;

  int get count => math.max(1, _screens.length - 1);

  int firstCharacter(int screen) =>
      _characters.isEmpty ? 0 : _characters[_screens[screen]];

  int screenAt(int character) {
    var first = 0;
    var end = count;
    while (first + 1 < end) {
      final middle = (first + end) ~/ 2;
      if (firstCharacter(middle) <= character) {
        first = middle;
      } else {
        end = middle;
      }
    }
    return first;
  }

  String textOf(int screen) => text
      .substring(
        firstCharacter(screen),
        screen + 1 < count ? firstCharacter(screen + 1) : text.length,
      )
      .trimRight();

  void paint(Canvas canvas, int screen) {
    if (_characters.isEmpty) return;
    final top = _tops[_screens[screen]];
    final bottom = screen + 1 < count
        ? _tops[_screens[screen + 1]]
        : _painter.height;
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(0, 0, size.width, math.min(size.height, bottom - top)),
    );
    _painter.paint(canvas, Offset(0, -top));
    canvas.restore();
  }

  void dispose() => _painter.dispose();
}

/// Draws only the chosen whole-line screen, with its reading text available
/// to accessibility. The viewport owns the layout and the chosen screen.
class PdfTextView extends StatelessWidget {
  const PdfTextView({super.key, required this.screens, required this.screen});

  final PdfTextScreens screens;
  final int screen;

  @override
  Widget build(BuildContext context) => Semantics(
    label: screens.textOf(screen),
    textDirection: TextDirection.ltr,
    child: CustomPaint(
      painter: _TextScreenPainter(screens, screen),
      size: screens.size,
    ),
  );
}

class _TextScreenPainter extends CustomPainter {
  const _TextScreenPainter(this.screens, this.screen);

  final PdfTextScreens screens;
  final int screen;

  @override
  void paint(Canvas canvas, Size size) => screens.paint(canvas, screen);

  @override
  bool shouldRepaint(_TextScreenPainter oldDelegate) =>
      oldDelegate.screens != screens || oldDelegate.screen != screen;
}
