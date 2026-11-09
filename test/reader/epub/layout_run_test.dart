import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/paint.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../../tool/showcase_media.dart' as media;
import 'helpers.dart';

/// A page small enough that breaks land inside lists, bordered blocks,
/// verse and split paragraphs.
const smallPage = PageSettings(
  width: 320,
  height: 260,
  fontSize: 18,
  night: false,
);

const forever = Duration(days: 1);

/// A section with every kind of page start: lines of split paragraphs,
/// block images, rules, list items with markers, bordered and padded
/// blocks, avoid rules, hanging indents, raised text, inline images and a
/// shrink-to-fit box.
SectionSource richSection() => section(
  '<h1>Harbour</h1><p>${prose(14)}</p>'
  '<img src="map.png"/>'
  '<ol><li>${prose(2, 'First')}</li><li><p>${prose(3, 'Second')}</p>'
  '<p>Second <sup>2</sup> stop.</p></li></ol>'
  '<hr/>'
  '<blockquote class="box">${[for (var i = 0; i < 4; i++) '<p>${prose(2, 'Quote $i')}</p>'].join()}</blockquote>'
  '<div class="keep"><p>${prose(1, 'Kept')}</p><p>${prose(1, 'Together')}</p></div>'
  '<h2>Second part</h2><p>${prose(5)}</p>'
  '<p class="verse">${[for (var i = 0; i < 9; i++) '<span>Verse line $i of the long hanging stanza</span>'].join('<br/>')}</p>'
  '<p>A small <img src="map.png" style="width:40px"/> map.</p>'
  '<div class="card">Card text</div><hr/><hr/>'
  '<div class="box"><div class="box"><p>${prose(8, 'Nested')}</p></div></div>'
  '<p>${prose(30, 'Closing')}</p>',
  css:
      '.verse{padding-left:2em;text-indent:-2em}'
      '.card{display:inline-block;border:1px solid}'
      '.box{border:2px solid;padding:6px 10px;margin:12px 0}'
      '.keep{break-inside:avoid}'
      'h2{break-after:avoid}',
  files: {'text/map.png': img.encodePng(img.Image(width: 300, height: 200))},
);

/// Every section of the showcase fixture books, as the reader admits them.
List<SectionSource> fixtureSections() => [
  for (final (id, title, chapters) in [
    ('frost', 'First Frost', media.firstFrost),
    ('salt', 'Salt and Lantern', media.saltAndLantern),
    ('winter', 'The Winter Ledger', media.winterLedger),
  ])
    ...() {
      final book = Publication.admit(
        media.epub(id, title, 'Bookfin Showcase', chapters),
      );
      return [
        for (var index = 0; index < book.spine.length; index++)
          SectionSource(
            index: index,
            path: book.spine[index],
            xhtml: utf8.decode(book.resources[book.spine[index]]!),
            fontPrefix: 'bookfin-${book.identity.substring(0, 12)}',
          ),
      ];
    }(),
];

/// The sections that the page tests run over, each prepared for each page
/// size.
List<PreparedSection> sampleSections() => [
  for (final settings in [readerPage, smallPage])
    ...prepareSections([
      richSection(),
      section('<p>${prose(80)}</p>'),
      section(
        [for (var i = 0; i < 40; i++) '<p>${prose(3, 'Part $i')}</p>'].join(),
      ),
      ...fixtureSections(),
    ], settings),
];

/// The pages of a run of [section] from [from], stepped to its end.
List<LaidPage> runToEnd(PreparedSection section, {PageStart? from}) {
  final run = LayoutRun(section, from: from)..step(forever);
  expect(run.done, isTrue);
  return run.pages;
}

void disposeAll(Iterable<LaidPage> pages) {
  for (final page in pages) {
    page.dispose();
  }
}

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

/// The place in [dom] that orders [place] among line starts: a place in
/// white space counts as the next visible character of its node.
(int, int) order(DomSection dom, EpubPlace place) {
  final text = dom.textAt(place);
  if (text == null) return (place.node, 0);
  var offset = place.offset;
  while (offset < text.text.length && isSpace(text.text.codeUnitAt(offset))) {
    offset++;
  }
  return (place.node, offset);
}

bool atOrBefore((int, int) a, (int, int) b) =>
    a.$1 < b.$1 || (a.$1 == b.$1 && a.$2 <= b.$2);

void main() {
  setUpAll(loadReaderFont);

  test(
    'a run from any true page start cuts the same pages as the main run',
    () {
      for (final section in sampleSections()) {
        final main = runToEnd(section);
        for (var page = 1; page < main.length; page++) {
          final resumed = runToEnd(section, from: main[page].start);
          expect(
            keys(resumed),
            keys(main.skip(page)),
            reason: 'section ${section.index}, ${section.settings}, page $page',
          );
          disposeAll(resumed);
        }
        disposeAll(main);
      }
    },
  );

  test('a page laid out again from its start draws the same pixels', () async {
    final section = prepareSections([richSection()], smallPage).single;
    final main = runToEnd(section);
    expect(main.length, greaterThan(10));
    for (var page = 1; page < main.length; page++) {
      final run = LayoutRun(section, from: main[page].start)
        ..step(forever, want: 1);
      expect(await pixels(run.pages.first), await pixels(main[page]));
      disposeAll(run.pages);
      run.dispose();
    }
    disposeAll(main);
  });

  test(
    'a run stopped after every step cuts the same pages as one long step',
    () {
      for (final section in sampleSections()) {
        final whole = runToEnd(section);
        final stepped = LayoutRun(section);
        var steps = 0;
        while (!stepped.done) {
          stepped
            ..step(Duration.zero)
            ..checkInvariants();
          steps++;
          expect(steps, lessThanOrEqualTo(section.flow.length + 1));
        }
        expect(keys(stepped.pages), keys(whole));
        final paged = LayoutRun(section);
        while (!paged.done) {
          final before = paged.pages.length;
          paged.step(forever, want: 1);
          expect(paged.pages.length, greaterThan(before));
        }
        expect(keys(paged.pages), keys(whole));
        disposeAll([...whole, ...stepped.pages, ...paged.pages]);
      }
    },
  );

  test('a step ends after the paragraph that spends its budget', () {
    final section = prepareSections([richSection()], smallPage).single;
    int paragraphsBefore(int item) =>
        section.flow.take(item).whereType<ParagraphItem>().length;
    // Each paragraph costs one millisecond on this clock.
    late final LayoutRun run;
    run = LayoutRun(
      section,
      clock: () => Duration(milliseconds: paragraphsBefore(run.reached)),
    );
    const budget = Duration(milliseconds: 3);
    while (!run.done) {
      final before = paragraphsBefore(run.reached);
      run.step(budget);
      final laid = paragraphsBefore(run.reached) - before;
      expect(laid, lessThanOrEqualTo(budget.inMilliseconds + 1));
      if (!run.done) {
        // The step ends right after the paragraph that spends the budget.
        expect(laid, budget.inMilliseconds);
        expect(section.flow[run.reached - 1], isA<ParagraphItem>());
      }
    }
    disposeAll(run.pages);
  });

  test('a page that starts at an image or a rule lays out the same again', () {
    // At 20 pixels a line is 33 pixels high, and a page holds 20 lines.
    String filler(int lines) =>
        [for (var i = 0; i < lines; i++) '<p>Line $i.</p>'].join();
    final section = prepared(
      '${filler(19)}<img src="map.png" class="wide"/>'
      '${filler(13)}<hr/>${filler(10)}',
      css:
          'p{margin:0;text-align:left}'
          '.wide{display:block;margin:24px 0}'
          'hr{margin:30px 0;border:2px solid;padding:4px 0}',
      files: {
        'text/map.png': img.encodePng(img.Image(width: 300, height: 200)),
      },
    );
    final main = runToEnd(section);
    final starts = [
      for (final page in main.skip(1)) section.flow[page.start.item],
    ];
    expect(starts.whereType<ImageItem>(), hasLength(1));
    expect(starts.whereType<BlockStart>(), hasLength(1));
    for (var page = 1; page < main.length; page++) {
      final resumed = runToEnd(section, from: main[page].start);
      expect(keys(resumed), keys(main.skip(page)), reason: 'page $page');
      disposeAll(resumed);
    }
    disposeAll(main);
  });

  test('a page that starts inside a paragraph keeps orphans and widows', () {
    // Lines are 29.7 pixels high, so an 75 pixel page holds two lines.
    const twoLines = PageSettings(
      width: 320,
      height: 75,
      fontSize: 18,
      night: false,
    );
    final verse = [for (var i = 0; i < 5; i++) '<span>Verse line $i</span>']
        .join('<br/>');
    final section = prepared(
      '<p>$verse</p>',
      css: 'p{margin:0;text-align:left}',
      settings: twoLines,
    );
    String first(LaidPage page) => section.dom.textAt(page.startPlace!)!.text;
    final main = runToEnd(section);
    // Two lines on the second page would leave one line alone.
    expect(
      [for (final page in main) first(page)],
      ['Verse line 0', 'Verse line 2', 'Verse line 3'],
    );
    final resumed = runToEnd(section, from: main[1].start);
    expect(keys(resumed), keys(main.skip(1)));
    disposeAll([...main, ...resumed]);
  });

  test('lineStart gives a page start whose first line holds the place', () {
    final small = sampleSections().where(
      (section) => section.settings == smallPage,
    );
    for (final section in small) {
      final main = runToEnd(section);
      final dom = section.dom;
      final lines = [
        for (final page in main)
          for (final slice in page.slices)
            if (slice.start case final start? when dom.textAt(start) != null)
              start,
      ];
      for (var line = 0; line < lines.length; line++) {
        final next = line + 1 < lines.length ? lines[line + 1] : null;
        final places = [
          lines[line],
          if (next != null &&
              next.node == lines[line].node &&
              next.offset > lines[line].offset + 2)
            EpubPlace(section.index, lines[line].node, lines[line].offset + 2),
        ];
        for (final place in places) {
          final run = LayoutRun(section, from: lineStart(section, place))
            ..step(forever, want: 1);
          final shown = [
            for (final slice in run.pages.first.slices)
              if (slice.start case final start? when dom.textAt(start) != null)
                start,
          ];
          final key = order(dom, place);
          expect(
            atOrBefore(order(dom, shown.first), key),
            isTrue,
            reason: '$place in ${section.settings}',
          );
          if (shown.length > 1) {
            expect(
              atOrBefore(order(dom, shown[1]), key),
              isFalse,
              reason: '$place in ${section.settings}',
            );
          }
          disposeAll(run.pages);
          run.dispose();
        }
      }
      disposeAll(main);
    }
  });

  test('a place in white space opens on the line of the next character '
      'that it shows', () {
    final sections = [
      ...sampleSections(),
      // Poems in the shape of a Standard Ebooks collection: a contents
      // entry names the article, whose first text node is white space.
      ...prepareSections([
        section(
          [
            for (var i = 0; i < 6; i++)
              '<article id="poem-$i">\n\t<header>\n\t\t<h2>Poem $i</h2>\n'
                  '\t</header>\n\t<p>${prose(3, 'Poem $i')}</p>\n</article>\n',
          ].join(),
        ),
        // Words in elements of their own, with white space between them,
        // so that some lines break at a node of white space.
        section(
          '<p>${[for (var i = 0; i < 160; i++) '<span>word$i</span>'].join('\n')}</p>',
        ),
      ], smallPage),
    ];
    for (final section in sections) {
      final dom = section.dom;
      final chapter = layoutSection(section);
      for (final (index, text) in dom.texts.indexed) {
        if (visibleCount(text.text, 0, text.text.length) > 0) continue;
        // The next visible character, with nothing shown before it.
        final next = dom.texts
            .skip(index + 1)
            .where(
              (later) => visibleCount(later.text, 0, later.text.length) > 0,
            );
        if (next.isEmpty) continue;
        final visible = next.first;
        final between = [
          for (var node = text.order + 1; node < visible.order; node++)
            dom.nodeAt(node),
        ];
        if (between.any((node) => node is DomElement && node.name == 'img')) {
          continue;
        }
        var offset = 0;
        while (isSpace(visible.text.codeUnitAt(offset))) {
          offset++;
        }
        final place = EpubPlace(section.index, text.order, 0);
        final target = EpubPlace(section.index, visible.order, offset);
        final reason = '$place in ${section.settings}';
        expect(
          lineStart(section, place),
          lineStart(section, target),
          reason: reason,
        );
        expect(chapter.pageAt(place), chapter.pageAt(target), reason: reason);
      }
      chapter.dispose();
    }
  });

  test('a place in white space before an image opens on the image', () {
    final section = prepared(
      '<p>${prose(8)}</p>\n<img src="map.png"/>\n<p>${prose(2)}</p>',
      settings: smallPage,
      files: {
        'text/map.png': img.encodePng(img.Image(width: 300, height: 200)),
      },
    );
    final dom = section.dom;
    final space = dom.texts.firstWhere(
      (text) => text.text == '\n' && text.parent == dom.body,
    );
    final place = EpubPlace(section.index, space.order, 0);
    final run = LayoutRun(section, from: lineStart(section, place))
      ..step(forever, want: 1);
    final image = run.pages.first.slices.first.start!;
    expect(dom.nodeAt(image.node), isA<DomElement>());
    expect((dom.nodeAt(image.node) as DomElement).name, 'img');
    final chapter = layoutSection(section);
    expect(chapter.pageAt(place), chapter.pageAt(image));
    disposeAll(run.pages);
    run.dispose();
    chapter.dispose();
  });

  test('a place in raised text stays on the line that raises it', () {
    final section = prepared(
      '<p>${[for (var i = 0; i < 80; i++) 'Note<sup>$i$i</sup>'].join(' ')}</p>',
      settings: smallPage,
    );
    final dom = section.dom;
    final chapter = layoutSection(section);
    for (final (index, text) in dom.texts.indexed) {
      if (text.parent?.name != 'sup') continue;
      // "Note" and its raised number make one word, so one line holds both.
      final word = dom.texts[index - 1];
      final note = EpubPlace(section.index, word.order, word.text.length - 1);
      for (var offset = 0; offset < text.text.length; offset++) {
        final place = EpubPlace(section.index, text.order, offset);
        expect(lineStart(section, place), lineStart(section, note));
        expect(chapter.pageAt(place), chapter.pageAt(note));
      }
    }
    chapter.dispose();
  });

  test('the first line of a section starts its first page', () {
    final section = prepareSections([richSection()], smallPage).single;
    final main = runToEnd(section);
    final first = main.first.slices.first.start!;
    expect(lineStart(section, first), main.first.start);
    expect(main.first.start, const PageStart(0, 0));
    disposeAll(main);
  });

  test('published pages never change while the run goes on', () {
    final section = prepareSections([richSection()], smallPage).single;
    final run = LayoutRun(section);
    final published = <LaidPage>[];
    final seen = <List<Object?>>[];
    while (!run.done) {
      run.step(Duration.zero);
      for (final page in run.pages.skip(published.length)) {
        published.add(page);
        seen.add(pageKey(page));
      }
      expect(run.pages.take(published.length), orderedEquals(published));
    }
    expect(keys(published), seen);
    expect(published.last.last, isTrue);
    expect(published.where((page) => page.last), hasLength(1));
    disposeAll(published);
  });

  test('a page draws after its run and its neighbors are disposed', () async {
    final section = prepared('<p>${prose(80)}</p>');
    final run = LayoutRun(section)..step(forever);
    final [first, second, ...rest] = run.pages;
    // The paragraph runs over both pages.
    expect(
      identical(first.slices.last.piece, second.slices.first.piece),
      isTrue,
    );
    final before = await pixels(second);
    run.dispose();
    first.dispose();
    disposeAll(rest);
    expect(await pixels(second), before);
    second.dispose();
  });

  test('pages cover the section text once and in order', () {
    for (final section in sampleSections()) {
      final pages = runToEnd(section);
      var visible = 0;
      for (final page in pages) {
        expect(page.startVisible, greaterThanOrEqualTo(visible));
        expect(page.endVisible, greaterThanOrEqualTo(page.startVisible));
        visible = page.endVisible;
      }
      expect(visible, section.dom.visibleLength);
      for (var page = 1; page < pages.length; page++) {
        expect(pages[page].start.compareTo(pages[page - 1].start), 1);
      }
      disposeAll(pages);
    }
  });

  test('a paragraph\'s lines start at each soft wrap and after each hard '
      'break, whose newline ends the line that it breaks', () async {
    // The code units [start, end) of each line, as the renderer cut them
    // when it asked the engine for one line boundary per line.
    final expected = {
      '<p>${prose(1, 'Wrapped')}<br/>Short line<br/><br/>After an empty '
          'line<br/>Trailing ${prose(1, 'Last')}<br/></p>': [
        (0, 39), (39, 81), (81, 89), (89, 100), (100, 101), //
        (101, 121), (121, 157), (157, 196), (196, 216), (216, 216),
      ],
      '<pre>one\ntwo two\n\nfour four four four four four four four four '
          'four four four four four four four four\n</pre>': [
        (0, 4), (4, 12), (12, 13), (13, 28), (28, 43), //
        (43, 58), (58, 73), (73, 88), (88, 98), (98, 98),
      ],
      '<p lang="en" style="hyphens:auto;text-align:justify">'
          '${prose(2, 'Extraordinarily')} incomprehensibilities<br/>'
          'characteristically</p>': [
        (0, 43), (43, 80), (80, 121), (121, 165), //
        (165, 205), (205, 231), (231, 254),
      ],
      '<p>Ancient 𝔊𝔬𝔱𝔥𝔦𝔠 letters 𝔊𝔬𝔱𝔥𝔦𝔠 𝔊𝔬𝔱𝔥𝔦𝔠 𝔊𝔬𝔱𝔥𝔦𝔠 𝔊𝔬𝔱𝔥𝔦𝔠 and more '
          '𝔊𝔬𝔱𝔥𝔦𝔠 𝔊𝔬𝔱𝔥𝔦𝔠 𝔊𝔬𝔱𝔥𝔦𝔠 words<br/>end</p>': [
        (0, 55),
        (55, 103),
        (103, 135),
        (135, 138),
      ],
      '<p style="padding-left:2em;text-indent:-2em">'
          '${prose(1, 'Hanging')}<br/>second<br/></p>': [
        (0, 39),
        (0, 36),
        (36, 50),
        (50, 57),
        (57, 57),
      ],
    };
    for (final MapEntry(key: body, value: lines) in expected.entries) {
      final chapter = await lay(body);
      expect(
        [
          for (final slice in chapter.slices)
            if (slice.piece != null) slice.units,
        ],
        lines,
        reason: body,
      );
      chapter.dispose();
    }
  });
}
