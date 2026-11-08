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
      expect(gridMaxContent(rows), 50 + 80 + 3 * cellSpacing);
      expect(columnWidths(rows, gridMaxContent(rows)), [50, 80]);
    });

    test('a table that is set wider than its content shares the extra width '
        'in proportion to what each column asks for', () {
      final rows = [
        [cell(10, 50), cell(20, 150)],
      ];
      // 300 pixels hold 200 of content and three spaces.
      final widths = columnWidths(rows, 300 + 3 * cellSpacing);
      expect(widths[0], closeTo(75, 1e-9));
      expect(widths[1], closeTo(225, 1e-9));
    });

    test('columns that do not fit take their narrowest width and a share of '
        'the rest in proportion to the width they want beyond it', () {
      final rows = [
        [cell(10, 50), cell(20, 80)],
      ];
      // 100 pixels: 30 for the narrowest widths, 70 shared 40 to 60.
      final widths = columnWidths(rows, 100 + 3 * cellSpacing);
      expect(widths[0], closeTo(38, 1e-9));
      expect(widths[1], closeTo(62, 1e-9));
    });

    test('columns that cannot fit their narrowest content shrink in '
        'proportion to it', () {
      final rows = [
        [cell(100, 200), cell(300, 400)],
      ];
      final widths = columnWidths(rows, 200 + 3 * cellSpacing);
      expect(widths[0], closeTo(50, 1e-9));
      expect(widths[1], closeTo(150, 1e-9));
    });

    test('a cell that spans columns widens them only by what they lack', () {
      final rows = [
        [cell(10, 40), cell(10, 40)],
        [cell(30, 120, span: 2)],
      ];
      // The two columns and the space between them give 82 of the 120.
      final widths = columnWidths(rows, gridMaxContent(rows));
      expect(widths[0], closeTo(59, 1e-9));
      expect(widths[1], closeTo(59, 1e-9));
      expect(cellBoxes([2], widths).single, (
        cellSpacing,
        59 + cellSpacing + 59,
      ));
    });

    test('a row with fewer cells leaves its last columns empty', () {
      final rows = [
        [cell(10, 40), cell(10, 60), cell(5, 30)],
        [cell(10, 20)],
      ];
      final widths = columnWidths(rows, gridMaxContent(rows));
      expect(widths, [40, 60, 30]);
      expect(cellBoxes([1, 1, 1], widths), [
        (cellSpacing, 40),
        (2 * cellSpacing + 40, 60),
        (3 * cellSpacing + 100, 30),
      ]);
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

  test('a row taller than a page gets a page of its own', () {
    final section = prepared(
      '<table><tr><td>Short</td><td>Row</td></tr>'
      '<tr><td>Tall</td><td>${prose(30, 'Tall')}</td></tr>'
      '<tr><td>Next</td><td>Row</td></tr></table>',
      settings: smallPage,
    );
    final pages = runToEnd(section);
    final tall = pagesShowing(section, pages, 'Tall passage 1.');
    expect(tall, hasLength(1));
    final page = pages[tall.single];
    expect(pagesShowing(section, pages, 'Short'), isNot(contains(page)));
    expect(pagesShowing(section, pages, 'Next').single, tall.single + 1);
    expect(page.slices, hasLength(1));
    expect(page.height, greaterThan(smallPage.height));
    disposeAll(pages);
  });

  test('a ruled cell draws its borders as tall as its row', () {
    final section = prepared(
      '<table><tr><td>Short</td><td>${prose(3, 'Tall')}</td></tr></table>',
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
      expect(side.height, closeTo(tall.paragraph.height + 8, 0.01));
    }
    disposeAll(pages);
  });

  test('a cell sits at the top or the bottom of its row as its '
      'vertical-align asks', () {
    final section = prepared(
      '<table><tr><td class="top">Top</td><td>Middle</td>'
      '<td class="bottom">Bottom</td><td>${prose(3, 'Tall')}</td></tr>'
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
      middle.y + middle.paragraph.height / 2,
      closeTo(tall.y + tall.paragraph.height / 2, 0.01),
    );
    expect(
      bottom.y + bottom.paragraph.height,
      closeTo(tall.y + tall.paragraph.height, 0.01),
    );
    disposeAll(pages);
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
