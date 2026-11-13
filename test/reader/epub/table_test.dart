import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/paint.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/table.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// A page small enough that tables run over several pages.
const smallPage = PageSettings(
  width: 320,
  height: 260,
  fontSize: 18,
  night: false,
);

const forever = Duration(days: 1);

/// A contents table as Project Gutenberg writes it: a centered table of
/// links to the chapters, with a title beside each link.
String gutenbergContents(int rows, {bool longTitles = false}) =>
    '<h2>CONTENTS</h2>'
    '<table style="margin-right: auto; margin-left: auto"><tbody>'
    '${[for (var i = 1; i <= rows; i++) '<tr><td><a href="#chap$i" class="pginternal">Chapter $i</a></td><td>${longTitles ? prose(1, 'Title $i') : 'Title $i'}</td></tr>'].join()}'
    '</tbody></table>';

/// A table shaped like the Etymology table of Standard Ebooks' Moby-Dick:
/// a centered two-column table of words in small caps beside their
/// languages in italics, here with a last row that spans both columns.
const etymology =
    '<section class="preamble"><h2>Etymology</h2>'
    '<p>While you take in hand to school others, and to teach them by what '
    'name a whale-fish is to be called in our tongue.</p>'
    '<table><tbody>'
    '<tr><td class="first-child">Cetus</td><td>Latin.</td></tr>'
    '<tr><td class="first-child">Whœl</td><td>Anglo-Saxon.</td></tr>'
    '<tr><td class="first-child">Hvalt</td><td>Danish.</td></tr>'
    '<tr><td class="first-child">Pekee-nuee-nuee</td><td>Fiji.</td></tr>'
    '<tr><td colspan="2">The whale, in all of these tongues.</td></tr>'
    '</tbody></table></section>';

const etymologyCss =
    '.preamble table{margin-left:auto;margin-right:auto}'
    '.preamble td.first-child{font-variant:small-caps}'
    '.preamble td + td{font-style:italic;padding-left:1em}'
    'p{text-align:left}';

/// The pages of a run of [section] from [from], stepped to its end.
List<LaidPage> runToEnd(PreparedSection section, {PageStart? from}) {
  final run = LayoutRun(section, from: from)..step(forever);
  expect(run.done, isTrue);
  run.dispose();
  return run.pages;
}

void disposeAll(Iterable<LaidPage> pages) {
  for (final page in pages) {
    page.dispose();
  }
}

/// The order of the first text node of [section] whose text holds [text].
int nodeOf(PreparedSection section, String text) =>
    section.dom.texts.firstWhere((node) => node.text.contains(text)).order;

/// The first visible place of the text node that holds [text].
EpubPlace placeOf(PreparedSection section, String text) {
  final node = section.dom.texts.firstWhere((node) => node.text.contains(text));
  return EpubPlace(section.index, node.order, node.text.indexOf(text));
}

/// The paragraphs of [pages] that show the text node that holds [text],
/// each with the index of its page.
List<(int, Piece)> piecesShowing(
  PreparedSection section,
  List<LaidPage> pages,
  String text,
) {
  final node = nodeOf(section, text);
  return [
    for (final (index, page) in pages.indexed)
      for (final piece in page.pieces)
        if (piece.map.nodes.contains(node)) (index, piece),
  ];
}

/// The one paragraph of [pages] that shows [text].
Piece pieceOf(PreparedSection section, List<LaidPage> pages, String text) {
  final found = piecesShowing(section, pages, text);
  expect(found, hasLength(1), reason: text);
  return found.single.$2;
}

/// The indices of the pages of [pages] that show [text].
Set<int> pagesShowing(
  PreparedSection section,
  List<LaidPage> pages,
  String text,
) => {for (final (index, _) in piecesShowing(section, pages, text)) index};

Future<List<int>> pixels(LaidPage page) async {
  final picture = drawPage(page, const {});
  final image = await picture.toImage(
    page.settings.width.round(),
    page.settings.height.round(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

/// Sections with tables in the places where pages can start: a long
/// contents table, a table with a caption and borders inside a bordered
/// box, a row taller than a page, a table in a list item, a table and a
/// list inside cells, hanging indents in cells, and spanning cells.
List<SectionSource> tableSections() => [
  section(gutenbergContents(40, longTitles: true)),
  section(
    '<p>${prose(3)}</p>'
    '<div class="box"><table class="ruled"><caption>Stores of the ship</caption>'
    '<thead><tr><th>Amount</th><th>Store</th></tr></thead><tbody>'
    '${[for (var i = 0; i < 12; i++) '<tr><td>${i * 1000}</td><td>${prose(1, 'Store $i')}</td></tr>'].join()}'
    '<tr><td>Tall</td><td>${prose(18, 'Tall')}</td></tr>'
    '<tr><td colspan="2">${prose(2, 'Spanning')}</td></tr>'
    '</tbody></table></div>'
    '<p>${prose(4, 'After')}</p>',
    css:
        '.box{border:2px solid;padding:6px;margin:12px 0}'
        '.ruled td{border:1px solid;padding:3px}',
  ),
  section(
    '<ol><li><table><tr><td>Listed cell</td><td>${prose(2, 'Listed')}</td>'
    '</tr></table></li><li>${prose(2, 'Second item')}</li></ol>'
    '<table class="illus"><tbody>'
    '${[for (var i = 0; i < 8; i++) '<tr><td><p class="illus">${prose(1, 'Plate $i')}</p></td><td>J. Leech</td></tr>'].join()}'
    '<tr><td><table><tr><td>Inner one</td><td>Inner two</td></tr></table>'
    '</td><td><ul><li>First listed</li><li>Second listed</li></ul></td></tr>'
    '</tbody></table>'
    '<p>${prose(6, 'Closing')}</p>',
    css: 'p.illus{text-indent:-2em;margin-left:2em}',
  ),
  section(etymology, css: etymologyCss),
];

void main() {
  setUpAll(loadReaderFont);

  group('column widths', () {
    // Chromium's default border-spacing.
    const spacing = 2.0;
    ({int span, double min, double max}) cell(
      double min,
      double max, {
      int span = 1,
    }) => (span: span, min: min, max: max);

    // A table without a set width is as wide as its widest content, or as
    // its containing block when that is narrower.
    test('columns whose widest content fits take that width', () {
      final rows = [
        [cell(10, 50), cell(20, 80)],
        [cell(30, 40), cell(5, 10)],
      ];
      expect(gridMaxContent(rows, spacing), 50 + 80 + 3 * spacing);
      expect(columnWidths(rows, gridMaxContent(rows, spacing), spacing), [
        50,
        80,
      ]);
    });

    test('a table that is set wider than its content shares the extra width '
        'in proportion to what each column asks for', () {
      final rows = [
        [cell(10, 50), cell(20, 150)],
      ];
      // 300 pixels hold 200 of content and three spaces.
      final widths = columnWidths(rows, 300 + 3 * spacing, spacing);
      expect(widths[0], closeTo(75, 1e-9));
      expect(widths[1], closeTo(225, 1e-9));
    });

    test('columns that do not fit take their narrowest width and a share of '
        'the rest in proportion to the width they want beyond it', () {
      final rows = [
        [cell(10, 50), cell(20, 80)],
      ];
      // 100 pixels: 30 for the narrowest widths, 70 shared 40 to 60.
      final widths = columnWidths(rows, 100 + 3 * spacing, spacing);
      expect(widths[0], closeTo(38, 1e-9));
      expect(widths[1], closeTo(62, 1e-9));
    });

    test('columns that cannot fit their narrowest content shrink in '
        'proportion to it', () {
      final rows = [
        [cell(100, 200), cell(300, 400)],
      ];
      final widths = columnWidths(rows, 200 + 3 * spacing, spacing);
      expect(widths[0], closeTo(50, 1e-9));
      expect(widths[1], closeTo(150, 1e-9));
    });

    test('a cell that spans columns widens them only by what they lack', () {
      final rows = [
        [cell(10, 40), cell(10, 40)],
        [cell(30, 120, span: 2)],
      ];
      // The two columns and the space between them give 82 of the 120.
      final widths = columnWidths(rows, gridMaxContent(rows, spacing), spacing);
      expect(widths[0], closeTo(59, 1e-9));
      expect(widths[1], closeTo(59, 1e-9));
      expect(cellBoxes([2], widths, spacing).single, (
        spacing,
        59 + spacing + 59,
      ));
    });

    test('a row with fewer cells leaves its last columns empty', () {
      final rows = [
        [cell(10, 40), cell(10, 60), cell(5, 30)],
        [cell(10, 20)],
      ];
      final widths = columnWidths(rows, gridMaxContent(rows, spacing), spacing);
      expect(widths, [40, 60, 30]);
      expect(cellBoxes([1, 1, 1], widths, spacing), [
        (spacing, 40),
        (2 * spacing + 40, 60),
        (3 * spacing + 100, 30),
      ]);
    });
  });

  group('collapsed borders', () {
    const none = [0.0, 0.0, 0.0, 0.0];
    List<double> all(double width) => [width, width, width, width];

    test('two cells that touch share the wider of their two borders, half '
        'on each side', () {
      final (:cells, :table) = collapseBorders([
        (
          border: none,
          cells: [
            (span: 1, border: [1.0, 6.0, 1.0, 1.0]),
            (span: 1, border: [1.0, 1.0, 1.0, 2.0]),
          ],
        ),
      ], none);
      expect(cells[0][0], [0.5, 3, 0.5, 0.5]);
      expect(cells[0][1], [0.5, 0.5, 0.5, 3]);
      // The table takes the other half of the borders at its edges.
      expect(table, [0.5, 0.5, 0.5, 0.5]);
    });

    test('an edge that meets several cells takes the widest of their '
        'borders', () {
      final (:cells, table: _) = collapseBorders([
        (border: none, cells: [(span: 2, border: all(1))]),
        (
          border: none,
          cells: [
            (span: 1, border: [3.0, 1.0, 1.0, 1.0]),
            (span: 1, border: all(1)),
          ],
        ),
      ], none);
      expect(cells[0][0][2], 1.5);
      expect(cells[1][0][0], 1.5);
      expect(cells[1][1][0], 0.5);
    });

    test('the borders of the table and of a row collapse with those of the '
        'cells at their edges', () {
      final (:cells, :table) = collapseBorders([
        (
          border: [0.0, 0.0, 2.0, 0.0],
          cells: [(span: 1, border: all(1)), (span: 1, border: all(1))],
        ),
        (
          border: none,
          cells: [(span: 1, border: all(1)), (span: 1, border: all(1))],
        ),
      ], all(4));
      expect(cells[0][0], [2, 0.5, 1, 2]);
      expect(cells[1][1], [1, 2, 2, 0.5]);
      expect(table, [2, 2, 2, 2]);
    });

    test('a table takes as its top and bottom border half the widest of the '
        'cells at that edge, and as its sides half those of its first row', () {
      final (cells: _, :table) = collapseBorders([
        (
          border: none,
          cells: [
            (span: 1, border: [2.0, 1.0, 1.0, 1.0]),
            (span: 1, border: [6.0, 3.0, 1.0, 1.0]),
          ],
        ),
        (
          border: none,
          cells: [
            (span: 1, border: [1.0, 1.0, 1.0, 8.0]),
            (span: 1, border: [1.0, 1.0, 4.0, 1.0]),
          ],
        ),
      ], none);
      expect(table, [3, 1.5, 2, 0.5]);
    });
  });

  group('row fragments', () {
    // Pages 100 pixels tall. A cell's slices are lines of its content,
    // from the top of its box: here a padding of 3 above and below.
    List<(double, double)> lines(int count, double height) => [
      for (var line = 0; line < count; line++)
        (3 + line * height, 3 + (line + 1) * height),
    ];

    test('a row that fits a page is one fragment, with each cell where its '
        'vertical-align puts it', () {
      final fragments = rowFragments([
        (slices: lines(2, 20), height: 46, align: 0.5),
        (slices: lines(1, 20), height: 26, align: 1),
      ], 100);
      expect(fragments, hasLength(1));
      final [fragment] = fragments;
      expect(fragment.height, 46);
      expect(
        [for (final cell in fragment.cells) (cell.from, cell.to)],
        [(0, 2), (0, 1)],
      );
      expect([for (final cell in fragment.cells) cell.offset], [0, 20]);
    });

    test('a row taller than a page breaks each cell after its last slice '
        'that fits, and goes on with each cell at the next fragment\'s '
        'top', () {
      final fragments = rowFragments([
        (slices: lines(10, 20), height: 206, align: 0.5),
        (slices: lines(4, 30), height: 126, align: 0.5),
      ], 100);
      // Each fragment but the last fills a page.
      expect(
        [for (final fragment in fragments) fragment.height],
        [100, 100, 23],
      );
      List<(int, int)> shown(int cell) => [
        for (final fragment in fragments)
          (fragment.cells[cell].from, fragment.cells[cell].to),
      ];
      expect(shown(0), [(0, 4), (4, 9), (9, 10)]);
      expect(shown(1), [(0, 3), (3, 4), (4, 4)]);
      // A split cell starts at the row's top, whatever its
      // vertical-align, and each later fragment starts with its next slice.
      final [first, second, third] = fragments;
      expect([for (final cell in first.cells) cell.offset], [0, 0]);
      expect([for (final cell in second.cells) cell.offset], [-83, -93]);
      expect(third.cells[0].offset, -183);
      // Each fragment shows the band of the box from its first slice to
      // the next fragment's first slice.
      expect(
        (first.cells[0].top, first.cells[0].bottom),
        (double.negativeInfinity, 83),
      );
      expect((second.cells[0].top, second.cells[0].bottom), (83, 183));
      expect(
        (second.cells[1].top, second.cells[1].bottom),
        (93, double.infinity),
      );
      expect(
        (third.cells[0].top, third.cells[0].bottom),
        (183, double.infinity),
      );
      // The second cell ended in the second fragment.
      expect(third.cells[1].bottom, lessThanOrEqualTo(third.cells[1].top));
    });

    test('a slice taller than a page goes on a fragment of its own', () {
      final fragments = rowFragments([
        (slices: [(0.0, 150.0), (150.0, 170.0)], height: 170, align: 0.5),
      ], 100);
      expect([for (final fragment in fragments) fragment.height], [150, 20]);
      expect([for (final fragment in fragments) fragment.cells[0].to], [1, 2]);
    });

    test('the bottom padding of a cell that does not fit goes on the next '
        'fragment when another cell goes on there', () {
      final fragments = rowFragments([
        (slices: [(0.0, 50.0), (50.0, 98.0)], height: 104, align: 0),
        (slices: lines(5, 20), height: 106, align: 0),
      ], 100);
      expect([for (final fragment in fragments) fragment.height], [100, 23]);
      expect([for (final fragment in fragments) fragment.cells[0].to], [2, 2]);
      expect(fragments.last.cells[0].bottom, double.infinity);
    });

    test('the bottom padding of cells that have no slice left is dropped at '
        'the break, so that every fragment shows a slice', () {
      final fragments = rowFragments([
        (slices: [(0.0, 50.0), (50.0, 98.0)], height: 104, align: 0),
        (slices: lines(4, 20), height: 86, align: 0),
      ], 100);
      expect([for (final fragment in fragments) fragment.height], [100]);
      expect([for (final cell in fragments.single.cells) cell.to], [2, 4]);
    });
  });

  group('preparing', () {
    test('a table with rows prepares as one table item, after its caption', () {
      final section = prepared(
        '<table><caption>Plates</caption><thead><tr><th>Plate</th>'
        '<th>Artist</th></tr></thead><tbody><tr><td>Marley</td>'
        '<td>J. Leech</td></tr><tr><td colspan="2" rowspan="3">Both</td>'
        '</tr></tbody></table>',
      );
      final tables = section.flow.whereType<TableItem>().toList();
      expect(tables, hasLength(1));
      final table = tables.single;
      expect([for (final row in table.rows) row.length], [2, 2, 1]);
      expect([for (final row in table.rows) row.first.colspan], [1, 1, 2]);
      // The caption's paragraph comes before the table.
      final caption = section.flow.indexWhere(
        (item) =>
            item is ParagraphItem &&
            item.text.runs.whereType<TextRun>().any(
              (run) => run.text.contains('Plates'),
            ),
      );
      expect(caption, lessThan(section.flow.indexOf(table)));
      // A cell keeps its padding beside the flow of its content.
      final cell = table.rows[1][0];
      expect(cell.padding, [1, 1, 1, 1]);
      expect(cell.flow.single, isA<ParagraphItem>());
    });

    test('a table inside a cell prepares as blocks', () {
      final section = prepared(
        '<table><tr><td><table><tr><td>Inner one</td><td>Inner two</td>'
        '</tr></table></td></tr></table>',
      );
      final table = section.flow.whereType<TableItem>().single;
      final cell = table.rows.single.single.flow;
      expect(cell.whereType<TableItem>(), isEmpty);
      expect(cell.whereType<ParagraphItem>(), hasLength(2));
    });

    test('a table without rows flows as blocks', () {
      final section = prepared(
        '<table><caption>Only a caption</caption>'
        '</table>',
      );
      expect(section.flow.whereType<TableItem>(), isEmpty);
      expect(section.flow.whereType<ParagraphItem>(), hasLength(1));
    });
  });

  test('a Project Gutenberg contents table lays out as a grid', () {
    final section = prepared(gutenbergContents(12));
    final pages = runToEnd(section);
    final links = [
      for (var i = 1; i <= 12; i++) pieceOf(section, pages, 'Chapter $i'),
    ];
    final titles = [
      for (var i = 1; i <= 12; i++) pieceOf(section, pages, 'Title $i'),
    ];
    for (var row = 0; row < 12; row++) {
      // The cells of a row sit side by side at one height.
      expect(titles[row].y, closeTo(links[row].y, 0.01));
      expect(
        titles[row].x,
        greaterThanOrEqualTo(links[row].x + links[row].paragraph.width),
      );
      // Each column keeps one left edge, and rows go down the page.
      expect(links[row].x, links.first.x);
      expect(titles[row].x, titles.first.x);
      if (row > 0) {
        expect(links[row].y, greaterThan(links[row - 1].y));
      }
    }
    // The centered table leaves the same space on each side.
    final heading = pieceOf(section, pages, 'CONTENTS');
    final left = links.first.x - heading.x;
    final right =
        heading.x +
        heading.paragraph.width -
        titles.first.x -
        titles.first.paragraph.width;
    expect(left, closeTo(right, 0.5));
    expect(left, greaterThan(50));
    disposeAll(pages);
  });

  test('every text and link of a contents table has a place on the page '
      'that shows it', () {
    final section = prepared(gutenbergContents(40), settings: smallPage);
    final chapter = layoutSection(section);
    expect(chapter.pages.length, greaterThan(2));
    for (var i = 1; i <= 40; i++) {
      for (final text in ['Chapter $i', 'Title $i']) {
        final place = placeOf(section, text);
        final shown = pagesShowing(section, chapter.pages, text);
        expect(shown, hasLength(1), reason: text);
        expect(chapter.pageAt(place), shown.single, reason: text);
        // The page that lineStart gives starts with the row of the place.
        final run = LayoutRun(section, from: lineStart(section, place))
          ..step(forever, want: 1);
        final first = run.pages.first.startPlace!;
        expect(
          section.dom.textAt(first)!.text,
          contains('Chapter $i'),
          reason: text,
        );
        disposeAll(run.pages);
        run.dispose();
      }
    }
    chapter.dispose();
  });

  test('an Etymology table lays out centered in its columns, and a cell '
      'that spans both columns is as wide as both', () {
    final section = prepared(etymology, css: etymologyCss);
    final pages = runToEnd(section);
    final words = [
      for (final word in ['Cetus', 'Whœl', 'Hvalt', 'Pekee'])
        pieceOf(section, pages, word),
    ];
    final tongues = [
      for (final tongue in ['Latin', 'Anglo-Saxon', 'Danish', 'Fiji'])
        pieceOf(section, pages, tongue),
    ];
    for (var row = 0; row < 4; row++) {
      expect(words[row].x, words.first.x);
      expect(tongues[row].x, tongues.first.x);
      expect(tongues[row].y, closeTo(words[row].y, 0.01));
      // The padding-left of 1em sits between the columns.
      expect(
        tongues[row].x,
        greaterThanOrEqualTo(words[row].x + words[row].paragraph.width + 18),
      );
    }
    final spanning = pieceOf(section, pages, 'all of these tongues');
    expect(spanning.x, words.first.x);
    expect(
      spanning.x + spanning.paragraph.width,
      closeTo(tongues.first.x + tongues.first.paragraph.width, 0.01),
    );
    final text = pieceOf(section, pages, 'take in hand');
    final left = words.first.x - text.x;
    final right =
        text.x +
        text.paragraph.width -
        tongues.first.x -
        tongues.first.paragraph.width;
    expect(left, closeTo(right, 0.5));
    disposeAll(pages);
  });

  test('pages break only between rows', () {
    final section = prepared(
      gutenbergContents(40, longTitles: true),
      settings: smallPage,
    );
    final pages = runToEnd(section);
    expect(pages.length, greaterThan(3));
    for (var i = 1; i <= 40; i++) {
      final link = pagesShowing(section, pages, 'Chapter $i');
      final title = pagesShowing(section, pages, 'Title $i');
      expect(link, hasLength(1), reason: 'row $i');
      expect(title, link, reason: 'row $i');
    }
    disposeAll(pages);
  });

  group('a row taller than a page', () {
    // Two long cells side by side, the left one in smaller type, so that
    // their lines do not line up, between a short row and a row after.
    const css =
        'td{border:1px solid;padding:3px}td.small{font-size:13px}'
        'td.narrow{width:20%}';
    final body =
        '<p>${prose(1, 'Before')}</p>'
        '<table><tr><td>Short</td><td>Row</td></tr>'
        '<tr><td class="small">${prose(5, 'Left')}</td>'
        '<td>${prose(6, 'Right')}</td></tr>'
        '<tr><td class="narrow">Last</td><td>${prose(2, 'Tall')}</td></tr>'
        '<tr><td>Next</td><td>Row</td></tr></table>'
        '<p>${prose(2, 'After')}</p>';

    test('splits between the lines of its cells, so every line shows whole '
        'on one page', () {
      final section = prepared(body, css: css, settings: smallPage);
      final run = LayoutRun(section);
      while (!run.done) {
        run
          ..step(forever, want: 1)
          ..checkInvariants();
      }
      run.dispose();
      final pages = run.pages;
      final left = pagesShowing(section, pages, 'Left passage 1.');
      expect(left.length, greaterThan(2));
      expect(
        pagesShowing(section, pages, 'Right passage 1.'),
        containsAll(left),
      );
      expect(shownLines(section, pages, ['Left', 'Right']), isEmpty);
      disposeAll(pages);
    });

    test('starts its split cells at the top of the row, draws their top '
        'borders on its first page and their bottom borders on its last', () {
      final section = prepared(body, css: css, settings: smallPage);
      final pages = runToEnd(section);
      final shown = pagesShowing(section, pages, 'Right passage 1.').toList()
        ..sort();
      final [left, right] = [
        for (final text in ['Left passage 1.', 'Right passage 1.'])
          piecesShowing(
            section,
            pages,
            text,
          ).firstWhere((found) => found.$1 == shown.first).$2,
      ];
      expect(left.y, closeTo(right.y, 0.01));
      // The horizontal rules of each page of the row: the first page has
      // the cells' top borders, the pages between have none, and the last
      // has their bottom borders above the next row.
      List<double> across(LaidPage page, [double below = double.infinity]) => [
        for (final decoration in page.decorations)
          if (decoration case RuleDecoration(:final rect)
              when rect.height == 1 && rect.width > 1 && rect.top < below)
            rect.top - page.top,
      ];
      final first = pages[shown.first];
      expect(across(first), [0, 0]);
      for (final page in shown.skip(1).take(shown.length - 2)) {
        expect(across(pages[page]), isEmpty, reason: 'page $page');
      }
      final next = piecesShowing(section, pages, 'Last');
      final end = pages[shown.last];
      expect(
        across(
          end,
          next.first.$1 == shown.last ? next.first.$2.y : double.infinity,
        ),
        hasLength(2),
      );
      disposeAll(pages);
    });

    test('lays out again from every page start inside it as the main run '
        'does, and draws the same pixels', () async {
      final section = prepared(body, css: css, settings: smallPage);
      final main = runToEnd(section);
      final inside = pagesShowing(section, main, 'Left passage 1.');
      expect(inside.length, greaterThan(2));
      for (var page = 1; page < main.length; page++) {
        final resumed = runToEnd(section, from: main[page].start);
        expect(keys(resumed), keys(main.skip(page)), reason: 'page $page');
        expect(await pixels(resumed.first), await pixels(main[page]));
        disposeAll(resumed);
      }
      disposeAll(main);
    });

    test('leaves no page that holds only the bottom padding of a row whose '
        'lines fill its last page, before another row taller than a page', () {
      // Each row is 26 lines of exactly 20 pixels: two pages of 260
      // pixels, and then 10 pixels of bottom padding.
      String row(String label) =>
          '<tr><td>${[for (var line = 0; line < 26; line++) '$label line $line'].join('<br/>')}</td></tr>';
      final section = prepared(
        '<table>${row('First')}${row('Second')}</table>',
        css: 'td{padding:0 0 10px;line-height:20px}',
        settings: smallPage,
      );
      final main = runToEnd(section);
      for (final (index, page) in main.indexed) {
        expect(page.pieces, isNotEmpty, reason: 'page $index is blank');
      }
      expect(main, hasLength(4));
      for (var page = 1; page < main.length; page++) {
        final resumed = runToEnd(section, from: main[page].start);
        expect(keys(resumed), keys(main.skip(page)), reason: 'page $page');
        disposeAll(resumed);
      }
      disposeAll(main);
    });

    test('opens a place in its second cell on the page that shows it', () {
      final section = prepared(body, css: css, settings: smallPage);
      final chapter = layoutSection(section);
      for (var passage = 1; passage <= 6; passage++) {
        final text = 'Right passage $passage.';
        final place = placeOf(section, text);
        final page = chapter.pages.indexWhere(
          (page) => _shows(page, place, section),
        );
        expect(page, isNonNegative, reason: text);
        expect(chapter.pageAt(place), page, reason: text);
        final run = LayoutRun(section, from: lineStart(section, place))
          ..step(forever, want: 1);
        expect(run.pages.first.start, chapter.pages[page].start, reason: text);
        disposeAll(run.pages);
        run.dispose();
      }
      chapter.dispose();
    });

    test('ends each of its pages at the last character that the page '
        'shows', () {
      final section = prepared(body, css: css, settings: smallPage);
      final pages = runToEnd(section);
      final shown = pagesShowing(section, pages, 'Right passage 1.');
      for (final index in shown) {
        final page = pages[index];
        final end = page.endPlace!;
        expect(_shows(page, end, section), isTrue, reason: 'page $index');
        final text = section.dom.textAt(end)!.text;
        expect(text, contains('Right passage'), reason: 'page $index');
      }
      disposeAll(pages);
    });
  });

  test('a ruled cell draws its borders as tall as its row', () {
    final section = prepared(
      '<table><tr><td>Short</td><td>${prose(2, 'Tall')}</td></tr></table>',
      css: 'td{border:1px solid;padding:3px}',
      settings: smallPage,
    );
    final pages = runToEnd(section);
    final tall = pieceOf(section, pages, 'Tall passage 1');
    final short = pieceOf(section, pages, 'Short');
    // The short cell's text sits in the middle of the row.
    expect(short.y, greaterThan(tall.y));
    final sides = [
      for (final decoration in pages.single.decorations)
        if (decoration case RuleDecoration(:final rect) when rect.width == 1)
          rect,
    ];
    expect(sides, hasLength(4));
    for (final side in sides) {
      expect(side.top, sides.first.top);
      expect(side.height, closeTo(tall.tops.last + 8, 0.01));
    }
    disposeAll(pages);
  });

  test('a cell sits at the top or the bottom of its row as its '
      'vertical-align asks', () {
    final section = prepared(
      '<table><tr><td class="top">Top</td><td>Middle</td>'
      '<td class="bottom">Bottom</td><td>${prose(1, 'Tall')}</td></tr>'
      '</table>',
      css: 'td.top{vertical-align:top}tr td.bottom{vertical-align:bottom}',
      settings: smallPage,
    );
    final pages = runToEnd(section);
    final tall = pieceOf(section, pages, 'Tall passage 1');
    final top = pieceOf(section, pages, 'Top');
    final middle = pieceOf(section, pages, 'Middle');
    final bottom = pieceOf(section, pages, 'Bottom');
    expect(top.y, closeTo(tall.y, 0.01));
    expect(
      middle.y + middle.tops.last / 2,
      closeTo(tall.y + tall.tops.last / 2, 0.01),
    );
    expect(bottom.y + bottom.tops.last, closeTo(tall.y + tall.tops.last, 0.01));
    disposeAll(pages);
  });

  group('border-spacing and border-collapse', () {
    const grid =
        '<table><tr><td class="wide">One</td><td>Two</td></tr>'
        '<tr><td>Three</td><td>Four</td></tr></table>';

    /// The rules of the one page of [pages] that are taller than wide, and
    /// those that are wider than tall, each sorted by where they start.
    ({List<ui.Rect> down, List<ui.Rect> across}) rules(List<LaidPage> pages) {
      final rects = [
        for (final decoration in pages.single.decorations)
          if (decoration case RuleDecoration(:final rect)) rect,
      ];
      return (
        down: [
          for (final rect in rects)
            if (rect.height > rect.width) rect,
        ]..sort((a, b) => a.left.compareTo(b.left)),
        across: [
          for (final rect in rects)
            if (rect.width > rect.height) rect,
        ]..sort((a, b) => a.top.compareTo(b.top)),
      );
    }

    /// The rules of [down] that run beside the first row's cells only.
    List<ui.Rect> firstRow(
      PreparedSection section,
      List<LaidPage> pages,
      List<ui.Rect> down,
    ) {
      final three = pieceOf(section, pages, 'Three');
      return [
        for (final rect in down)
          if (rect.bottom <= three.y) rect,
      ];
    }

    test('a table spaces its columns and rows by its border-spacing', () {
      final section = prepared(
        grid,
        css: 'table{border-spacing:10px 20px}td{border:1px solid}',
      );
      final pages = runToEnd(section);
      final (:down, :across) = rules(pages);
      // The first row's cells: One's left and right, Two's left and right.
      final row = firstRow(section, pages, down);
      expect(row, hasLength(4));
      expect(row[2].left - row[1].right, closeTo(10, 0.01));
      // One's top and bottom, then Three's top.
      final tops = {for (final rect in across) rect.top}.toList();
      expect(tops[2] - (tops[1] + 1), closeTo(20, 0.01));
      final one = pieceOf(section, pages, 'One');
      final three = pieceOf(section, pages, 'Three');
      expect(three.x, one.x);
      disposeAll(pages);
    });

    test('collapsed borders leave no space between cells and draw one rule '
        'as wide as the wider border where two cells meet', () {
      final section = prepared(
        grid,
        css:
            'table{border-collapse:collapse}td{border:2px solid}'
            'td.wide{border-right:6px solid}',
      );
      final pages = runToEnd(section);
      final (:down, :across) = rules(pages);
      final row = firstRow(section, pages, down);
      expect(row, hasLength(4));
      // One's right half and Two's left half meet in one 6 pixel rule.
      final (oneRight, twoLeft) = (row[1], row[2]);
      expect(twoLeft.left, closeTo(oneRight.right, 0.01));
      expect(oneRight.width + twoLeft.width, closeTo(6, 0.01));
      // One's bottom half and Three's top half meet in one 2 pixel rule.
      final one = pieceOf(section, pages, 'One');
      final three = pieceOf(section, pages, 'Three');
      final between = [
        for (final rect in across)
          if (rect.left == row[0].left &&
              rect.top > one.y &&
              rect.bottom < three.y)
            rect,
      ];
      expect(between, hasLength(2));
      expect(between[1].top, closeTo(between[0].bottom, 0.01));
      expect(between[0].height + between[1].height, closeTo(2, 0.01));
      disposeAll(pages);
    });

    test('a table whose borders collapse ignores its padding and draws half '
        'of its outer border, and its cells draw the other half', () {
      final section = prepared(
        grid,
        css:
            'table{border-collapse:collapse;border:4px solid;padding:10px}'
            'td{border:2px solid}',
      );
      final pages = runToEnd(section);
      final (:down, across: _) = rules(pages);
      // The table's left rule, then One's left rule beside it.
      final [table, one, ...] = down;
      expect(table.width, closeTo(2, 0.01));
      expect(one.width, closeTo(2, 0.01));
      expect(one.left, closeTo(table.right, 0.01));
      disposeAll(pages);
    });
  });

  test('a caption lays out as a block above its table', () {
    final section = prepared(
      '<table><caption>Plates in the book</caption>'
      '<tr><td>Marley</td><td>J. Leech</td></tr></table>',
    );
    final pages = runToEnd(section);
    final caption = pieceOf(section, pages, 'Plates in the book');
    final cell = pieceOf(section, pages, 'Marley');
    expect(caption.y + caption.paragraph.height, lessThanOrEqualTo(cell.y));
    disposeAll(pages);
  });

  test('a table inside a cell lays out as blocks', () {
    final section = prepared(
      '<table><tr><td><table><tr><td>Inner one</td><td>Inner two</td></tr>'
      '</table></td><td>Outer</td></tr></table>',
    );
    final pages = runToEnd(section);
    final one = pieceOf(section, pages, 'Inner one');
    final two = pieceOf(section, pages, 'Inner two');
    final outer = pieceOf(section, pages, 'Outer');
    expect(two.x, one.x);
    expect(two.y, greaterThanOrEqualTo(one.y + one.paragraph.height));
    expect(outer.x, greaterThan(one.x + one.paragraph.width));
    disposeAll(pages);
  });

  test('a cell that asks for more rows takes one', () {
    final section = prepared(
      '<table><tr><td rowspan="2">Spanning</td><td>First</td></tr>'
      '<tr><td>Second</td></tr></table>',
    );
    final pages = runToEnd(section);
    final spanning = pieceOf(section, pages, 'Spanning');
    final first = pieceOf(section, pages, 'First');
    final second = pieceOf(section, pages, 'Second');
    expect(first.x, greaterThan(spanning.x));
    // The second row starts again at the first column.
    expect(second.x, spanning.x);
    expect(second.y, greaterThan(first.y));
    disposeAll(pages);
  });

  test('a run from any true page start cuts the same pages with tables', () {
    for (final settings in [readerPage, smallPage]) {
      for (final section in prepareSections(tableSections(), settings)) {
        final main = runToEnd(section);
        expect(section.flow.whereType<TableItem>(), isNotEmpty);
        for (var page = 1; page < main.length; page++) {
          final resumed = runToEnd(section, from: main[page].start);
          expect(
            keys(resumed),
            keys(main.skip(page)),
            reason: 'section ${section.index}, $settings, page $page',
          );
          disposeAll(resumed);
        }
        disposeAll(main);
      }
    }
  });

  test('a page of a table laid out again from its start draws the same '
      'pixels', () async {
    final section = prepareSections(tableSections(), smallPage)[1];
    final main = runToEnd(section);
    expect(main.length, greaterThan(4));
    for (var page = 1; page < main.length; page++) {
      final run = LayoutRun(section, from: main[page].start)
        ..step(forever, want: 1);
      expect(await pixels(run.pages.first), await pixels(main[page]));
      disposeAll(run.pages);
      run.dispose();
    }
    disposeAll(main);
  });

  test('pages with tables cover the section text once and in order', () {
    for (final section in prepareSections(tableSections(), smallPage)) {
      final pages = runToEnd(section);
      var visible = 0;
      for (final page in pages) {
        expect(page.startVisible, greaterThanOrEqualTo(visible));
        expect(page.endVisible, greaterThanOrEqualTo(page.startVisible));
        visible = page.endVisible;
      }
      expect(visible, section.dom.visibleLength);
      disposeAll(pages);
    }
  });

  group('a row of many paragraphs', () {
    // Speeches of many paragraphs beside their speaker, as in Plato's
    // dialogues and Roget's Thesaurus, in rows taller than a page.
    final body =
        '<p>${prose(1, 'Before')}</p><table>'
        '${[
          for (var row = 0; row < 3; row++) '<tr><td>Speaker $row</td><td>${[for (var i = 0; i < 12; i++) '<p>${prose(2, 'Speech $row part $i')}</p>'].join()}</td></tr>',
        ].join()}'
        '</table><p>${prose(2, 'After')}</p>';

    test('lays out one paragraph of its cells in each step, and the steps cut '
        'the pages of one long step', () {
      final section = prepared(body, settings: smallPage);
      final table = section.flow.indexWhere((item) => item is TableItem);
      // A clock that moves on 1 ms each time the run reads it, so that a
      // step with a budget of 1 ms ends after its first unit of work.
      var now = Duration.zero;
      final run = LayoutRun(
        section,
        clock: () => now += const Duration(milliseconds: 1),
      );
      var stepsInTable = 0;
      while (!run.done) {
        run
          ..step(const Duration(milliseconds: 1))
          ..checkInvariants();
        if (run.reached == table) stepsInTable++;
      }
      run.dispose();
      // Twelve paragraphs in each of three rows.
      expect(stepsInTable, greaterThanOrEqualTo(3 * 12));
      final whole = runToEnd(section);
      expect(keys(run.pages), keys(whole));
      disposeAll(run.pages);
      disposeAll(whole);
    });

    test('lays out again from every page start inside it as the main run '
        'does', () {
      for (final settings in [readerPage, smallPage]) {
        final section = prepared(body, settings: settings);
        final main = runToEnd(section);
        for (var page = 1; page < main.length; page++) {
          final resumed = runToEnd(section, from: main[page].start);
          expect(
            keys(resumed),
            keys(main.skip(page)),
            reason: '$settings, page $page',
          );
          disposeAll(resumed);
        }
        disposeAll(main);
      }
    });

    test('a run stopped inside a row lets go of what it laid out', () {
      final section = prepared(body, settings: smallPage);
      final table = section.flow.indexWhere((item) => item is TableItem);
      var now = Duration.zero;
      final run = LayoutRun(
        section,
        clock: () => now += const Duration(milliseconds: 1),
      );
      while (run.reached < table) {
        run.step(const Duration(milliseconds: 1));
      }
      for (var unit = 0; unit < 8; unit++) {
        run.step(const Duration(milliseconds: 1));
      }
      run
        ..checkInvariants()
        ..dispose()
        ..checkInvariants();
      disposeAll(run.pages);
    });
  });

  group('a long table', () {
    // Dialogue set as a table of speaker and speech, as Standard Ebooks sets
    // its plays and Plato's dialogues.
    final body =
        '<p>${prose(1, 'Before')}</p><table>'
        '${[for (var i = 0; i < 40; i++) '<tr><td>Speaker $i</td><td>${prose(1, 'Speech $i')}</td></tr>'].join()}'
        '</table><p>${prose(2, 'After')}</p>';

    test('lays out one row in each step that one row spends, and the steps '
        'cut the pages of one long step', () {
      final section = prepared(body);
      final table = section.flow.indexWhere((item) => item is TableItem);
      // A clock that moves on 1 ms each time the run reads it, so that a
      // step with a budget of 1 ms ends after its first unit of work.
      var now = Duration.zero;
      final run = LayoutRun(
        section,
        clock: () => now += const Duration(milliseconds: 1),
      );
      var stepsInTable = 0;
      while (!run.done) {
        run
          ..step(const Duration(milliseconds: 1))
          ..checkInvariants();
        if (run.reached == table) stepsInTable++;
      }
      run.dispose();
      expect(stepsInTable, greaterThanOrEqualTo(40));
      final whole = runToEnd(section);
      expect(keys(run.pages), keys(whole));
      disposeAll(run.pages);
      disposeAll(whole);
    });

    test('finds the line of a place in it in steps of one measured row when '
        'no run measured it, and at once after', () {
      final place = placeOf(prepared(body), 'Speech 30 passage 1.');
      final expected = lineStart(prepared(body), place);
      final section = prepared(body);
      final measurements = LayoutMeasurements();
      final search = LineSearch(section, place, measurements: measurements);
      var steps = 0;
      while (search.found == null) {
        search.step(Duration.zero);
        steps++;
      }
      expect(steps, greaterThanOrEqualTo(40));
      expect(search.found, expected);
      expect(
        (LineSearch(
          section,
          place,
          measurements: measurements,
        )..step(Duration.zero)).found,
        expected,
      );
    });

    test('a run whose table a search measured meanwhile measures the next '
        'table by its own cells', () {
      final twoTables =
          '<table>${[for (var i = 0; i < 6; i++) '<tr><td>Antidisestablishmentarianism$i</td><td>Short</td></tr>'].join()}</table>'
          '<table>${[for (var i = 0; i < 6; i++) '<tr><td>A$i</td><td>${prose(1, 'Wide $i')}</td></tr>'].join()}</table>';
      final whole = runToEnd(prepared(twoTables));
      final section = prepared(twoTables);
      final run = LayoutRun(section);
      // The table's own box asks for its widths, so the run measures the
      // table there: four of its six rows, one in each step.
      final table = section.flow.indexWhere((item) => item is TableItem);
      while (run.reached < table - 1) {
        run.step(Duration.zero);
      }
      for (var row = 0; row < 4; row++) {
        run.step(Duration.zero);
      }
      lineStart(
        section,
        placeOf(section, 'Antidisestablishmentarianism0'),
        measurements: run.measurements,
      );
      run.step(forever);
      run.dispose();
      expect(keys(run.pages), keys(whole));
      disposeAll(run.pages);
      disposeAll(whole);
    });

    test('opens a place in any of its rows on a page that starts at that '
        'row, as the run from the section start places it', () {
      for (final settings in [readerPage, smallPage]) {
        final section = prepared(body, settings: settings);
        final chapter = layoutSection(section);
        // The page start of each row in the run from the section start.
        final rows = [
          for (final slice in chapter.slices)
            if (slice.cellSlices.isNotEmpty) slice.at,
        ];
        expect(rows, hasLength(40));
        for (var row = 1; row < 40; row += 3) {
          for (final text in ['Speaker $row', 'Speech $row passage 1.']) {
            final place = placeOf(section, text);
            final start = lineStart(section, place);
            expect(start, rows[row], reason: '$text, $settings');
            final run = LayoutRun(section, from: start)..step(forever, want: 1);
            expect(_shows(run.pages.first, place, section), isTrue);
            disposeAll(run.pages);
            run.dispose();
          }
        }
        chapter.dispose();
      }
    });
  });

  group('other layout', () {
    for (final display in ['flex', 'grid']) {
      test('a $display box shows its children as blocks in order', () {
        final section = prepared(
          '<div class="row"><span>Alpha item</span><em>Beta item</em>'
          'Gamma text<p>Delta paragraph</p></div>',
          css: '.row{display:$display;flex-direction:row}',
        );
        final pages = runToEnd(section);
        final shown = [
          for (final text in ['Alpha', 'Beta', 'Gamma', 'Delta'])
            pieceOf(section, pages, text),
        ];
        for (var index = 1; index < shown.length; index++) {
          expect(
            shown[index].y,
            greaterThanOrEqualTo(
              shown[index - 1].y + shown[index - 1].paragraph.height,
            ),
          );
        }
        disposeAll(pages);
      });
    }

    test('a float shows its text as a block', () {
      final section = prepared(
        '<p>Before the float.</p><div class="side">Floated note</div>'
        '<p>After the float.</p>',
        css: '.side{float:right}',
      );
      final pages = runToEnd(section);
      final before = pieceOf(section, pages, 'Before');
      final note = pieceOf(section, pages, 'Floated note');
      final after = pieceOf(section, pages, 'After');
      expect(note.y, greaterThan(before.y));
      expect(after.y, greaterThan(note.y));
      disposeAll(pages);
    });

    test('an absolutely placed box with offsets that are not negative '
        'flows as a block', () {
      final section = prepared(
        '<p>Before <span class="placed">Placed words</span> after.</p>'
        '<div class="fixed">Fixed box</div>',
        css:
            '.placed{position:absolute;left:10px;top:0}'
            '.fixed{position:fixed;top:2em}',
      );
      final pages = runToEnd(section);
      final before = pieceOf(section, pages, 'Before');
      final placed = pieceOf(section, pages, 'Placed words');
      expect(identical(before, placed), isFalse);
      expect(placed.y, greaterThan(before.y));
      expect(pagesShowing(section, pages, 'Fixed box'), {0});
      disposeAll(pages);
    });

    test('a box moved off the page by a negative offset stays out', () {
      final section = prepared(
        '<p>Shown text.</p><div class="away">Screen reader text</div>'
        '<p>Shown <span class="up">raised away</span> again.</p>',
        css:
            '.away{position:absolute;left:-9999px}'
            '.up{position:absolute;top:-500px}',
      );
      final pages = runToEnd(section);
      expect(pagesShowing(section, pages, 'Screen reader'), isEmpty);
      expect(pagesShowing(section, pages, 'raised away'), isEmpty);
      expect(pagesShowing(section, pages, 'Shown text'), {0});
      disposeAll(pages);
    });
  });
}

/// The lines of the paragraphs that show the texts that start with one of
/// [labels] that [pages] do not show exactly once and whole: each with
/// the number of pages that show it whole and whether a page cuts it.
List<String> shownLines(
  PreparedSection section,
  List<LaidPage> pages,
  List<String> labels,
) {
  final whole = <(ui.Paragraph, int), int>{};
  final cut = <(ui.Paragraph, int)>{};
  final paragraphs = <ui.Paragraph>{};
  for (final page in pages) {
    for (final piece in page.pieces) {
      final text = [
        for (final node in piece.map.nodes)
          if (node >= 0) section.dom.texts.firstWhere((n) => n.order == node),
      ].map((node) => node.text).join();
      if (!labels.any((label) => text.contains('$label passage'))) continue;
      paragraphs.add(piece.paragraph);
      final top = math.max(page.top, piece.y);
      final bottom = math.min(_bottom(page), piece.y + piece.shown);
      // Each line draws at its exact place, clipped to it.
      final tops = piece.tops;
      for (var line = 0; line + 1 < tops.length; line++) {
        final lineTop = piece.y + tops[line];
        final lineBottom = piece.y + tops[line + 1];
        final key = (piece.paragraph, line);
        if (lineTop >= top - 0.01 && lineBottom <= bottom + 0.01) {
          whole[key] = (whole[key] ?? 0) + 1;
        } else if (lineBottom > top + 0.01 && lineTop < bottom - 0.01) {
          cut.add(key);
        }
      }
    }
  }
  expect(paragraphs, isNotEmpty);
  return [
    for (final paragraph in paragraphs)
      for (var line = 0; line < paragraph.computeLineMetrics().length; line++)
        if (whole[(paragraph, line)] != 1 || cut.contains((paragraph, line)))
          'line $line: whole on ${whole[(paragraph, line)] ?? 0} pages, '
              'cut ${cut.contains((paragraph, line))}',
  ];
}

/// Whether [page] shows the line that holds [place], whole.
bool _shows(LaidPage page, EpubPlace place, PreparedSection section) {
  for (final piece in page.pieces) {
    final segment = piece.map.nodes.indexOf(place.node);
    if (segment < 0) continue;
    final offsets = piece.map.offsets[segment]!;
    final local = offsets.indexOf(place.offset);
    if (local < 0) continue;
    final unit = piece.map.starts[segment] + local;
    if (piece.paragraph.getBoxesForRange(unit, unit + 1).isEmpty) continue;
    // The character draws in its line, at the line's exact place.
    final line = piece.paragraph.getLineNumberAt(unit)!;
    final top = piece.y + piece.tops[line];
    final bottom = piece.y + piece.tops[line + 1];
    if (top >= math.max(page.top, piece.y) - 0.01 &&
        bottom <= math.min(_bottom(page), piece.y + piece.shown) + 0.01) {
      return true;
    }
  }
  return false;
}

/// The strip position where [page] stops showing: its bottom, or one page
/// height below its top for a page that is taller.
double _bottom(LaidPage page) =>
    math.min(page.bottom, page.top + page.settings.height);
