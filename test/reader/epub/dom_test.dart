import 'package:bookfin/reader/epub/dom.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the visible characters before a place deep in a long text node are '
      'those of the nodes before it and of the text before the place', () {
    // Verse in one pre element: one text node of thousands of code units,
    // with spaces and newlines throughout.
    final verse = [
      for (var line = 0; line < 200; line++) 'I sing line  $line\n',
    ].join();
    final dom = DomSection.parse(
      '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Title page</p>'
      '<pre>$verse</pre></body></html>',
    );
    final node = dom.texts.last;
    int counted(int end) => [
      for (var unit = 0; unit < end; unit++)
        if (!isSpace(verse.codeUnitAt(unit))) unit,
    ].length;
    for (final offset in [0, 1, 255, 256, 257, 511, 512, 2047, 3000]) {
      expect(
        dom.visibleBefore(EpubPlace(0, node.order, offset)),
        'Titlepage'.length + counted(offset),
        reason: 'offset $offset',
      );
    }
    expect(
      dom.visibleBefore(EpubPlace(0, node.order, verse.length)),
      dom.visibleLength,
    );
  });
}
