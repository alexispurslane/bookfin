import 'dart:typed_data';

/// The first line of each screen of a column of lines, and one more entry,
/// the line count, that ends the last screen. Both reflow views cut their
/// screens with it: the word view from the lines of its column, and the
/// text view from the line metrics of its text.
///
/// Line n spans [lineTops] n to [lineBottoms] n, in one unit, such as
/// logical pixels, from the column's top. Lines go down the column in order
/// and do not overlap. [screenHeight] is the height of a screen in the same
/// unit. When [keepWithNext] n is true, line n and line n + 1 stay on one
/// screen when both fit on one.
///
/// - A screen holds every line that fits whole below its first line. So no
///   line is cut at the screen's edge.
/// - A screen's top is its first line's top. The space above the line,
///   such as a paragraph gap, belongs to the screen before it.
/// - A screen always holds its first line, so a line taller than a screen
///   gets a screen of its own.
Int32List cutScreens(
  List<double> lineTops,
  List<double> lineBottoms,
  List<bool> keepWithNext,
  double screenHeight,
) {
  final count = lineTops.length;
  if (lineBottoms.length != count || keepWithNext.length != count) {
    throw ArgumentError('Each line needs a top, a bottom and a keep mark.');
  }
  if (!(screenHeight > 0 && screenHeight.isFinite)) {
    throw ArgumentError.value(screenHeight, 'screenHeight', 'must be positive');
  }
  final starts = <int>[0];
  var first = 0;
  while (first < count) {
    final top = lineTops[first];
    var next = first + 1;
    while (next < count && lineBottoms[next] - top <= screenHeight) {
      next++;
    }
    if (next < count) {
      // Lines kept with the line that did not fit move with it, while the
      // screen keeps a line and the moved lines still fit on one screen.
      var cut = next;
      while (cut - 1 > first &&
          keepWithNext[cut - 1] &&
          lineBottoms[next] - lineTops[cut - 1] <= screenHeight) {
        cut--;
      }
      next = cut;
    }
    starts.add(next);
    first = next;
  }
  return Int32List.fromList(starts);
}
