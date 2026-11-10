import 'package:bookfin/reader/screen_cut.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lines of [heights] that follow each other with [gaps] between them: the
/// gap before line n is gaps[n - 1]. It gives their tops and bottoms.
(List<double>, List<double>) stack(List<double> heights, List<double> gaps) {
  final tops = <double>[], bottoms = <double>[];
  var y = 0.0;
  for (final (line, height) in heights.indexed) {
    if (line > 0) y += gaps[line - 1];
    tops.add(y);
    y += height;
    bottoms.add(y);
  }
  return (tops, bottoms);
}

void main() {
  test('a screen holds every line that fits whole below its first line, and '
      'the next screen starts with the first line that did not fit', () {
    // Lines 30 tall with 10 between them: a screen of 110 holds lines 0
    // to 2, which end at 110, and line 3 ends at 150.
    final (tops, bottoms) = stack(List.filled(7, 30), List.filled(6, 10));
    expect(cutScreens(tops, bottoms, List.filled(7, false), 110), [0, 3, 6, 7]);
  });

  test('a paragraph gap above a screen\'s first line takes no room on that '
      'screen', () {
    // A gap of 60 before line 2. The second screen starts at line 2's top,
    // so it holds lines 2 and 3 in its 70 (line 2 to line 3 is 70).
    final (tops, bottoms) = stack(List.filled(4, 30), [10, 60, 10]);
    expect(cutScreens(tops, bottoms, List.filled(4, false), 70), [0, 2, 4]);
  });

  test('a line kept with the next line moves to the next screen with it '
      'when both fit on one screen', () {
    // Line 2 (a caption) keeps with line 3 (its figure, 80 tall). Line 3
    // does not fit on the first screen, so line 2 moves with it.
    final (tops, bottoms) = stack([30, 30, 30, 80, 30], List.filled(4, 10));
    expect(cutScreens(tops, bottoms, [false, false, true, false, false], 120), [
      0,
      2,
      4,
      5,
    ]);
  });

  test('a chain of kept lines moves together when all of it fits', () {
    // A caption above (line 1), a figure (line 2) and a caption below
    // (line 3): lines 1 and 2 keep with their next lines.
    final (tops, bottoms) = stack([30, 30, 60, 30], List.filled(3, 10));
    expect(cutScreens(tops, bottoms, [false, true, true, false], 140), [
      0,
      1,
      4,
    ]);
  });

  test('a kept pair taller than one screen stays where the lines fall', () {
    final (tops, bottoms) = stack([30, 30, 90], List.filled(2, 10));
    expect(cutScreens(tops, bottoms, [false, true, false], 100), [0, 2, 3]);
  });

  test('a line taller than the screen gets a screen of its own', () {
    final (tops, bottoms) = stack([30, 150, 30], List.filled(2, 10));
    expect(cutScreens(tops, bottoms, List.filled(3, false), 100), [0, 1, 2, 3]);
  });

  test('a column without lines has no screens', () {
    expect(cutScreens([], [], [], 100), [0]);
  });
}
