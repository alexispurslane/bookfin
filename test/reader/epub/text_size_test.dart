// The reader's text size and a book's own type sizes. Before the reader
// uses the size buttons, a book keeps its own design. Once they are used,
// the reader's text size is the size of the book's main text, and every
// other size in the book keeps its proportion to it.
import 'dart:async';

import 'package:bookfin/reader/epub/css.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/document.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'page_source_test.dart' show TestScheduler, book;

/// A book that fixes its body text at 12 points (16 pixels), with headings
/// twice that size, a line height of 15 points, an indent of 1.5 em, and a
/// last section of notes in 9 points (12 pixels).
Publication fixedBook() => book(
  [
    '<h1>The Dust</h1>${_paragraphs(4, 'Opening')}',
    _paragraphs(30, 'Planet'),
    [
      for (var note = 1; note <= 12; note++)
        '<p class="note">Note $note. ${prose(3, 'Note $note')}</p>',
    ].join(),
  ],
  css:
      'p { font-size: 12pt; line-height: 15pt; text-indent: 1.5em }'
      'h1 { font-size: 24pt }'
      'p.note { font-size: 9pt }',
);

/// A book that sets no type size of its own.
Publication plainBook() => book([
  '<h1>Plain</h1>${_paragraphs(4, 'Opening')}',
  _paragraphs(12, 'Middle'),
]);

String _paragraphs(int count, String label) =>
    [for (var at = 0; at < count; at++) '<p>${prose(6, '$label $at')}</p>']
        .join();

PageSettings settings(double fontSize, {bool sizesMainText = false}) =>
    PageSettings(
      width: 412,
      height: 671,
      fontSize: fontSize,
      night: false,
      sizesMainText: sizesMainText,
    );

/// The run style of the first text run of [section] that starts with
/// [text].
RunStyle styleOf(PreparedSection section, String text) {
  for (final item in section.flow) {
    if (item is! ParagraphItem) continue;
    for (final run in item.text.runs) {
      if (run is TextRun && run.text.trimLeft().startsWith(text)) {
        return section.styles[run.style];
      }
    }
  }
  throw StateError('No run starts with $text.');
}

/// The first paragraph of [section] whose first run starts with [text].
ParagraphItem paragraphOf(PreparedSection section, String text) =>
    section.flow.whereType<ParagraphItem>().firstWhere(
      (item) =>
          item.text.runs.first is TextRun &&
          (item.text.runs.first as TextRun).text.trimLeft().startsWith(text),
    );

/// A section of [body] under [css], in a book whose main text size is
/// [mainTextSize].
SectionSource sized(String body, String css, {double mainTextSize = 16}) =>
    SectionSource(
      index: 0,
      path: 'text/one.xhtml',
      xhtml:
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>T</title>'
          '<style>$css</style></head><body>$body</body></html>',
      fontPrefix: testFontPrefix,
      mainTextSize: mainTextSize,
    );

/// The computed style of each element with an id in [source], on a page of
/// [settings].
Map<String, Style> stylesOf(SectionSource source, PageSettings settings) {
  final (:styles, faces: _) = styleSection(
    source,
    DomSection.parse(source.xhtml),
    settings,
  );
  return {
    for (final MapEntry(key: element, value: style) in styles.entries)
      ?element.id: style,
  };
}

void main() {
  setUpAll(loadReaderFont);

  late TestScheduler scheduler;
  setUp(() => scheduler = TestScheduler());

  PageSource sourceOf(Publication publication) =>
      PageSource(publication, schedule: scheduler.schedule);

  Future<PreparedSection> section(
    PageSource source,
    PageSettings value,
    int index,
  ) {
    source.settings = value;
    return scheduler.until(source.section(index));
  }

  test('a book that fixes its body text size keeps its design before the '
      'size buttons are used', () async {
    final source = sourceOf(fixedBook());
    for (final size in [14.0, 20.0, 26.0, 40.0]) {
      final opening = await section(source, settings(size), 0);
      expect(styleOf(opening, 'Opening').size, 16, reason: '$size px');
      expect(styleOf(opening, 'The Dust').size, 32, reason: '$size px');
    }
  });

  test('after the size buttons are used, a fixed-size body is the reader\'s '
      'text size and grows with each larger step', () async {
    final source = sourceOf(fixedBook());
    var previous = 0.0;
    for (var size = 14.0; size <= 40; size += 2) {
      // The same page source served the book's own design first, so a
      // stale layout of the same text size would show here.
      await section(source, settings(size), 1);
      final planet = await section(
        source,
        settings(size, sizesMainText: true),
        1,
      );
      final body = styleOf(planet, 'Planet').size;
      expect(body, closeTo(size, 1e-9));
      expect(body, greaterThan(previous));
      previous = body;
    }
  });

  test('headings keep their proportion to the body text', () async {
    final opening = await section(
      sourceOf(fixedBook()),
      settings(26, sizesMainText: true),
      0,
    );
    expect(styleOf(opening, 'The Dust').size, closeTo(52, 1e-9));
    expect(styleOf(opening, 'Opening').size, closeTo(26, 1e-9));
  });

  test('a notes section in small print stays smaller than body text', () async {
    final notes = await section(
      sourceOf(fixedBook()),
      settings(26, sizesMainText: true),
      2,
    );
    expect(styleOf(notes, 'Note 1.').size, closeTo(26 * 12 / 16, 1e-9));
  });

  test('line heights and em lengths follow the scaled text sizes', () async {
    final planet = await section(
      sourceOf(fixedBook()),
      settings(26, sizesMainText: true),
      1,
    );
    // 15 points is 20 pixels at the book's 16-pixel body text.
    expect(styleOf(planet, 'Planet').lineHeight, closeTo(20 * 26 / 16, 1e-9));
    expect(paragraphOf(planet, 'Planet').indent.value, closeTo(39, 1e-9));
  });

  test('a book that sets no type size of its own looks the same whether or '
      'not the size buttons were used', () async {
    final source = sourceOf(plainBook());
    for (final size in [14.0, 20.0, 26.0]) {
      for (final index in [0, 1]) {
        final own = layoutSection(await section(source, settings(size), index));
        final chosen = layoutSection(
          await section(source, settings(size, sizesMainText: true), index),
        );
        expect(
          [for (final page in chosen.pages) page.lineStarts],
          [for (final page in own.pages) page.lineStarts],
          reason: '$size px, section $index',
        );
      }
    }
  });

  test('the reading place stays on the same character when the book\'s '
      'main text starts to follow the reader\'s text size', () async {
    final publication = fixedBook();
    final source = sourceOf(publication);
    final pager = EpubPager(
      EpubDocument(publication),
      onPlace: (_) {},
      onWarning: (_) {},
      source: source,
      hop: _inline,
    );
    addTearDown(pager.dispose);
    scheduler.afterStep = pager.checkInvariants;

    /// Presents [value], and waits for a page of settings equal to it.
    Future<ShownPage> present(PageSettings value) {
      pager.present(value);
      return scheduler.until(() async {
        while (pager.shown.value?.page.settings != value) {
          await Future<void>.delayed(Duration.zero);
        }
        return pager.shown.value!;
      }());
    }

    await present(settings(20));
    for (var turn = 0; turn < 4; turn++) {
      await scheduler.until(pager.move(true));
    }
    final place = pager.shown.value!.page.startPlace!;
    final chosen = await present(settings(20, sizesMainText: true));
    final prepared = await scheduler.until(source.section(chosen.page.section));
    expect(chosen.page.settings.sizesMainText, isTrue);
    expect(chosen.page.start, lineStart(prepared, place));
  });

  group('once the size buttons are used, the book\'s type sizes', () {
    // The book's main text is 16 pixels and the reader's text size 32, so
    // every size that the book fixes doubles.
    final doubled = settings(32, sizesMainText: true);

    test('that the book fixes grow, in every unit, and sizes relative to '
        'another follow it', () {
      final styles = stylesOf(
        sized(
          '<p id="px">A</p><p id="pt">A</p><p id="keyword">A</p>'
              '<p id="initial">A</p><p id="viewport">A</p><p id="em">A</p>'
              '<p id="percent">A</p><p id="smaller">A</p><p id="rem">A</p>',
          '#px{font-size:12px} #pt{font-size:9pt} #keyword{font-size:small}'
              '#initial{font-size:initial} #viewport{font-size:2vw}'
              '#em{font-size:2em} #percent{font-size:50%}'
              '#smaller{font-size:smaller} #rem{font-size:1.5rem}',
        ),
        doubled,
      );
      double size(String id) => styles[id]!.fontSize;
      expect(size('px'), closeTo(24, 1e-9));
      expect(size('pt'), closeTo(24, 1e-9));
      expect(size('keyword'), closeTo(26, 1e-9));
      expect(size('initial'), closeTo(32, 1e-9));
      expect(size('viewport'), closeTo(2 * 412 / 100 * 2, 1e-9));
      expect(size('em'), closeTo(64, 1e-9));
      expect(size('percent'), closeTo(16, 1e-9));
      expect(size('smaller'), closeTo(32 / 1.2, 1e-9));
      expect(size('rem'), closeTo(48, 1e-9));
    });

    test('carry their line heights: an absolute one grows, and one in em or '
        'as a factor follows the grown size', () {
      final styles = stylesOf(
        sized(
          '<p id="absolute">A</p><p id="em">A</p><p id="factor">A</p>',
          'p{font-size:10px} #absolute{line-height:12px}'
              '#em{line-height:2em} #factor{line-height:1.5}',
        ),
        doubled,
      );
      expect(styles['absolute']!.lineHeightPx, closeTo(24, 1e-9));
      expect(styles['em']!.lineHeightPx, closeTo(40, 1e-9));
      expect(styles['factor']!.lineHeightPx, closeTo(30, 1e-9));
    });

    test('leave margins in absolute units as they are, and em margins follow '
        'the grown size', () {
      final styles = stylesOf(
        sized(
          '<p id="x">A</p>',
          '#x{font-size:10px; margin-top:10px; margin-bottom:1em}',
        ),
        doubled,
      );
      expect(styles['x']!.margin[0].value, 10);
      expect(styles['x']!.margin[2].value, closeTo(20, 1e-9));
    });

    test('keep the proportions that the book\'s own body size sets', () {
      final source = sized(
        '<p id="body">A</p><p id="fixed">A</p>',
        'body{font-size:10px} #fixed{font-size:20px}',
        mainTextSize: 10,
      );
      final own = stylesOf(source, settings(30));
      expect(own['body']!.fontSize, 30, reason: 'The reader sizes the body.');
      expect(own['fixed']!.fontSize, 20);
      final chosen = stylesOf(source, settings(30, sizesMainText: true));
      expect(chosen['body']!.fontSize, closeTo(30, 1e-9));
      expect(chosen['fixed']!.fontSize, closeTo(60, 1e-9));
    });
  });

  group('the main text size', () {
    double measure(List<SectionSource> samples) => measureMainTextSize(samples);

    test('is the size that covers the most characters, not the most '
        'elements', () {
      expect(
        measure([
          sized(
            '${'<h2>Short</h2>' * 20}<p>${prose(4)}</p>',
            'h2{font-size:30px} p{font-size:14px}',
          ),
        ]),
        14,
      );
    });

    test('counts the characters of every sample together', () {
      expect(
        measure([
          sized('<p>${prose(2)}</p>', 'p{font-size:14px}'),
          sized('<p>${prose(3)}</p>', 'p{font-size:18px}'),
          sized('<p>${prose(2)}</p>', 'p{font-size:14px}'),
        ]),
        14,
      );
    });

    test('leaves out text that the book\'s style hides', () {
      expect(
        measure([
          sized(
            '<div class="hidden"><p>${prose(6)}</p></div><p>${prose(1)}</p>',
            '.hidden{display:none} .hidden p{font-size:30px}'
                'p{font-size:14px}',
          ),
        ]),
        14,
      );
    });

    test('leaves out text of size 0, which no one can read', () {
      expect(
        measure([
          sized(
            '<p class="gone">${prose(6)}</p><p>${prose(1)}</p>',
            '.gone{font-size:0} p{font-size:14px}',
          ),
        ]),
        14,
      );
    });

    test('is the book\'s own size, not the reader\'s text size', () {
      final samples = [sized('<p>${prose(3)}</p>', 'p{font-size:0.9em}')];
      expect(measure(samples), closeTo(14.4, 1e-9));
    });

    test('is kept with the admitted book, which the page source sizes the '
        'main text by', () async {
      // The book's main text is 9 points, 12 pixels.
      final publication = book([
        _paragraphs(12, 'Planet'),
      ], css: 'p { font-size: 9pt }');
      expect(publication.mainTextSize, 12);
      final planet = await section(
        sourceOf(publication),
        settings(26, sizesMainText: true),
        0,
      );
      expect(styleOf(planet, 'Planet').size, closeTo(26, 1e-9));
    });

    test('is the browser\'s initial size for a book with no visible text, '
        'and a sample that does not parse counts nothing', () {
      expect(measure([sized('<p> </p>', '')]), defaultMainTextSize);
      expect(
        measure([
          SectionSource(
            index: 0,
            path: 'text/broken.xhtml',
            xhtml: '<html><body><p>Never closed',
            fontPrefix: testFontPrefix,
          ),
          sized('<p>${prose(2)}</p>', 'p{font-size:15px}'),
        ]),
        15,
      );
    });

    group('as a page shows it', () {
      test('is the book\'s fixed size before the size buttons are used', () {
        final samples = [sized('<p>${prose(3)}</p>', 'p{font-size:12pt}')];
        for (final size in [14.0, 20.0, 26.0]) {
          expect(shownMainTextSize(samples, settings(size)), 16);
        }
      });

      test('follows the reader\'s text size in a book that sizes its text '
          'relative to the body', () {
        final samples = [sized('<p>${prose(3)}</p>', 'p{font-size:0.9em}')];
        expect(shownMainTextSize(samples, settings(20)), closeTo(18, 1e-9));
      });

      test('is the reader\'s text size once the size buttons are used', () {
        final samples = [
          sized('<p>${prose(3)}</p>', 'p{font-size:12pt}', mainTextSize: 16),
        ];
        expect(
          shownMainTextSize(samples, settings(26, sizesMainText: true)),
          closeTo(26, 1e-9),
        );
      });

      test(
        'the page source gives it for pages of the shown settings',
        () async {
          final source = sourceOf(fixedBook());
          expect(await source.shownMainText(settings(26)), 16);
          expect(
            await source.shownMainText(settings(26, sizesMainText: true)),
            26,
          );
        },
      );
    });

    test('is measured on the three longest sections of the book', () {
      expect(mainTextSamples([5, 90, 10, 70, 80, 1]), [1, 3, 4]);
      expect(mainTextSamples([5, 9]), [0, 1]);
    });
  });
}

Future<R> _inline<M, R>(FutureOr<R> Function(M) work, M input) async =>
    work(input);
