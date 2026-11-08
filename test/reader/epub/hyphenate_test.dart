import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/hyphenate.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const softHyphen = '­';

/// [word] with a hyphen at each of [breaks].
String hyphenated(String word, List<int> breaks) {
  final buffer = StringBuffer();
  var last = 0;
  for (final at in breaks) {
    buffer
      ..write(word.substring(last, at))
      ..write('-');
    last = at;
  }
  return (buffer..write(word.substring(last))).toString();
}

String us(String word) =>
    hyphenated(word, Hyphenator.forLanguage('en-US')!.breaks(word));

String gb(String word) =>
    hyphenated(word, Hyphenator.forLanguage('en-GB')!.breaks(word));

/// The text runs of the paragraphs of [prepared], in order.
List<TextRun> textRuns(PreparedSection prepared) => [
  for (final item in prepared.flow)
    if (item is ParagraphItem) ...item.text.runs.whereType<TextRun>(),
];

/// The text of the paragraphs of [prepared].
String textOf(PreparedSection prepared) =>
    textRuns(prepared).map((run) => run.text).join();

/// Long words that patterns break in several places.
const longWords =
    'The extraordinary typesetter considered the unbelievable hyphenation '
    'of characteristically incomprehensible representations, which '
    'nevertheless accommodated the administrative responsibilities of '
    'international communication. ';

/// A section of [longWords] in English, hyphenated when [hyphens] is
/// `auto`, aligned by [align].
PreparedSection longText(
  double width, {
  String hyphens = 'auto',
  String align = 'left',
}) => prepared(
  '<div lang="en">${'<p>${longWords * 3}</p>' * 3}</div>',
  css: 'p{hyphens:$hyphens;text-align:$align}',
  settings: PageSettings(width: width, height: 240, fontSize: 20, night: false),
);

bool isLetter(int code) =>
    (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);

/// The DOM character at [place], or -1 past its text.
int charAt(DomSection dom, EpubPlace place) {
  final text = dom.textAt(place)?.text ?? '';
  return place.offset < text.length ? text.codeUnitAt(place.offset) : -1;
}

/// Each line of [layout] that ends inside a word: the line, and the
/// place of the last character that it shows.
List<(Slice, EpubPlace)> linesEndingInWords(ChapterLayout layout) {
  final dom = layout.section.dom;
  return [
    for (final line in layout.slices)
      if (line.piece case final piece? when line.units.$2 > line.units.$1)
        if (piece.map.textPlaceAt(line.units.$2 - 1) case final last?)
          if (isLetter(charAt(dom, last)) &&
              isLetter(
                charAt(
                  dom,
                  EpubPlace(last.section, last.node, last.offset + 1),
                ),
              ))
            (line, last),
  ];
}

/// The width in pixels that code unit [unit] of [piece] draws.
double drawnWidth(Piece piece, int unit) => piece.paragraph
    .getBoxesForRange(unit, unit + 1)
    .fold(0.0, (width, box) => width + box.right - box.left);

void main() {
  setUpAll(loadReaderFont);

  group('Liang hyphenation with the TeX patterns', () {
    test('an English word breaks where the patterns allow', () {
      expect(us('hyphenation'), 'hy-phen-ation');
      expect(us('typesetter'), 'type-set-ter');
      expect(us('considered'), 'con-sid-ered');
    });

    test('the TeX exception lists win over the patterns', () {
      expect(us('associate'), 'as-so-ciate');
      expect(us('table'), 'ta-ble');
      expect(us('present'), 'present');
      expect(gb('manuscript'), 'ma-nu-script');
    });

    test('British English breaks with the British patterns', () {
      expect(us('manuscript'), 'man-u-script');
      expect(gb('hyphenation'), 'hy-phen-a-tion');
      for (final tag in ['en-GB', 'en-gb', 'EN-GB-oxendict']) {
        final breaks = Hyphenator.forLanguage(tag)!.breaks('manuscript');
        expect(hyphenated('manuscript', breaks), 'ma-nu-script', reason: tag);
      }
      for (final tag in ['en', 'en-US', 'en-AU', 'EN']) {
        final breaks = Hyphenator.forLanguage(tag)!.breaks('manuscript');
        expect(hyphenated('manuscript', breaks), 'man-u-script', reason: tag);
      }
    });

    test('a break keeps two letters before it and three after it', () {
      // The patterns allow u-ni-ver-si-ty.
      expect(us('university'), 'uni-ver-sity');
      expect(us('another'), 'an-other');
    });

    test('a word of fewer than five letters does not break', () {
      expect(us('also'), 'also');
      expect(us('table'), 'ta-ble');
    });

    test('a capitalized English word does not break, as in Chromium', () {
      expect(us('Hyphenation'), 'Hyphenation');
      expect(us('HYPHENATION'), 'HYPHENATION');
    });

    test('a word with a character that is not a letter does not break', () {
      expect(us("hyphenation's"), "hyphenation's");
      expect(us('hyphenation2'), 'hyphenation2');
      expect(us('hyphénation'), 'hyphénation');
      // CSS: a word with the book's own soft hyphen breaks only there.
      expect(us('hy${softHyphen}phenation'), 'hy${softHyphen}phenation');
    });

    test('a language without patterns does not hyphenate', () {
      expect(Hyphenator.forLanguage('fr'), isNull);
      expect(Hyphenator.forLanguage('english'), isNull);
      expect(Hyphenator.forLanguage(''), isNull);
      expect(Hyphenator.forLanguage(null), isNull);
    });

    test('the words of a text leave out the punctuation around them', () {
      const text = '“Hyphenation,” said the (well-known) typesetter—twice.';
      expect(
        [
          for (final (start, end) in hyphenationWords(text))
            text.substring(start, end),
        ],
        ['Hyphenation', 'said', 'the', 'well', 'known', 'typesetter', 'twice'],
      );
    });
  });

  group('prepare', () {
    test('text that asks for hyphens: auto gets soft hyphens where the '
        'patterns allow a break', () {
      final section = prepared(
        '<p lang="en">The hyphenation of a table.</p>',
        css: 'p{hyphens:auto}',
      );
      expect(
        textOf(section),
        'The hy${softHyphen}phen${softHyphen}ation of a ta${softHyphen}ble.',
      );
    });

    test('text that does not ask for hyphens: auto gets no soft hyphens', () {
      for (final css in ['', 'p{hyphens:manual}', 'p{hyphens:none}']) {
        final section = prepared(
          '<p lang="en">The hyphenation of a table.</p>',
          css: css,
        );
        expect(textOf(section), 'The hyphenation of a table.', reason: css);
      }
    });

    test('-webkit-hyphens asks for hyphenation as hyphens does', () {
      final section = prepared(
        '<p lang="en">The hyphenation.</p>',
        css: 'p{-webkit-hyphens:auto}',
      );
      expect(textOf(section), 'The hy${softHyphen}phen${softHyphen}ation.');
    });

    test('-webkit-hyphens and hyphens are one property, and a value that is '
        'not valid leaves the one before it', () {
      String text(String css) =>
          textOf(prepared('<p lang="en">The hyphenation.</p>', css: css));
      expect(text('p{hyphens:auto;-webkit-hyphens:none}'), 'The hyphenation.');
      expect(
        text('p{-webkit-hyphens:none;hyphens:auto}'),
        'The hy${softHyphen}phen${softHyphen}ation.',
      );
      expect(
        text('p{hyphens:auto} p{hyphens:sometimes}'),
        'The hy${softHyphen}phen${softHyphen}ation.',
      );
    });

    test('the language comes from xml:lang or lang, then from the package', () {
      PreparedSection inPackage(String body, String? language) =>
          prepareSections([
            SectionSource(
              index: 0,
              path: 'text/one.xhtml',
              xhtml:
                  '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>T'
                  '</title><style>p{hyphens:auto}</style></head>'
                  '<body>$body</body></html>',
              fontPrefix: testFontPrefix,
              language: language,
            ),
          ], readerPage).single;

      expect(
        textOf(inPackage('<p>manuscript</p>', 'en-GB')),
        'ma${softHyphen}nu${softHyphen}script',
      );
      expect(
        textOf(inPackage('<div lang="en-US"><p>manuscript</p></div>', 'en-GB')),
        'man${softHyphen}u${softHyphen}script',
      );
      expect(
        textOf(
          inPackage(
            '<div xml:lang="en-US" lang="en-GB"><p>manuscript</p></div>',
            null,
          ),
        ),
        'man${softHyphen}u${softHyphen}script',
        reason: 'xml:lang wins over lang, as in the :lang() selector',
      );
      expect(
        textOf(inPackage('<p lang="fr">manuscript</p>', 'en')),
        'manuscript',
      );
      expect(
        textOf(inPackage('<p lang="">manuscript</p>', 'en')),
        'manuscript',
      );
      expect(textOf(inPackage('<p>manuscript</p>', null)), 'manuscript');
    });

    test('a word split across elements breaks as one word', () {
      final section = prepared(
        '<p lang="en">hyphen<i>ation</i></p>',
        css: 'p{hyphens:auto}',
      );
      expect(
        [for (final run in textRuns(section)) run.text],
        ['hy${softHyphen}phen$softHyphen', 'ation'],
      );
    });

    test('soft hyphens leave the place of every other character unchanged, '
        'and each maps to the letter before it', () {
      const body =
          '<p lang="en">  The   hyphenation of\n extraordinary '
          '<b>characteristically</b> incomprehensible words.</p>';
      final plain = textRuns(prepared(body, css: 'p{hyphens:manual}'));
      final hyphenatedRuns = textRuns(prepared(body, css: 'p{hyphens:auto}'));
      expect(hyphenatedRuns.length, plain.length);
      for (final (index, run) in hyphenatedRuns.indexed) {
        final kept = <int>[];
        final text = StringBuffer();
        for (var unit = 0; unit < run.text.length; unit++) {
          if (run.text[unit] == softHyphen) {
            expect(run.offsets[unit], run.offsets[unit - 1]);
            expect(isLetter(run.text.codeUnitAt(unit - 1)), isTrue);
            continue;
          }
          text.write(run.text[unit]);
          kept.add(run.offsets[unit]);
        }
        expect(text.toString(), plain[index].text);
        expect(kept, plain[index].offsets);
        expect(run.node, plain[index].node);
      }
      expect(
        hyphenatedRuns.any((run) => run.text.contains(softHyphen)),
        isTrue,
      );
    });

    test("hyphens: none removes the book's own soft hyphens", () {
      const body = '<p lang="en">hy­phen­ation</p>';
      expect(textOf(prepared(body)), 'hy${softHyphen}phen${softHyphen}ation');
      expect(textOf(prepared(body, css: 'p{hyphens:none}')), 'hyphenation');
    });
  });

  group('layout', () {
    // Every word fits in a line at these widths, so a line breaks inside a
    // word only at a hyphen.
    const widths = [200.0, 214.0, 229.0, 245.0, 262.0, 281.0, 301.0];

    test('a long word at a line end breaks with a hyphen that fits in the '
        'line', () {
      var hyphens = 0;
      for (final align in ['left', 'justify', 'center']) {
        for (final width in widths) {
          final layout = layoutSection(longText(width, align: align));
          final where = '$align at $width px';
          for (final (line, _) in linesEndingInWords(layout)) {
            final piece = line.piece!;
            final last = line.units.$2 - 1;
            final boxes = piece.paragraph.getBoxesForRange(last, last + 1);
            expect(
              drawnWidth(piece, last),
              inInclusiveRange(4, 10),
              reason: '$where: no hyphen ends the line',
            );
            expect(
              boxes.last.right,
              lessThanOrEqualTo(piece.paragraph.width + 0.01),
              reason: '$where: the hyphen does not fit',
            );
            hyphens++;
          }
          layout.dispose();
        }
      }
      expect(hyphens, greaterThan(30));
    });

    test('justified text breaks its lines where left-aligned text does, as '
        'in Chromium', () {
      const body =
          '<div lang="en"><p>Mr.\u00A0Darcy considered the <i>extraordinary '
          'hyphenation</i> of incomprehensible representations, and '
          '<span style="letter-spacing:1px;word-spacing:3px">nevertheless '
          'accommodated the administrative</span> responsibilities of '
          'international communication. $longWords</p></div>';
      for (final width in widths) {
        List<EpubPlace?> starts(String align) {
          final layout = layoutSection(
            prepared(
              body,
              css: 'p{hyphens:auto;text-align:$align}',
              settings: PageSettings(
                width: width,
                height: 240,
                fontSize: 20,
                night: false,
              ),
            ),
          );
          final starts = [for (final line in layout.slices) line.start];
          layout.dispose();
          return starts;
        }

        expect(starts('justify'), starts('left'), reason: '$width px');
      }
    });

    test('no hyphen shows inside a line', () {
      for (final align in ['left', 'justify']) {
        for (final width in widths) {
          final layout = layoutSection(longText(width, align: align));
          for (final line in layout.slices) {
            final piece = line.piece;
            if (piece == null) continue;
            final (start, end) = line.units;
            for (var unit = start + 1; unit < end - 1; unit++) {
              final place = piece.map.textPlaceAt(unit);
              final before = piece.map.textPlaceAt(unit - 1);
              // A unit that maps to the place of the one before it is a
              // soft hyphen that prepare inserted.
              if (place != null && place == before) {
                expect(
                  drawnWidth(piece, unit),
                  lessThan(0.01),
                  reason: '$align at $width px, unit $unit',
                );
              }
            }
          }
          layout.dispose();
        }
      }
    });

    test(
      'text that does not ask for hyphenation never breaks inside a word',
      () {
        for (final hyphens in ['manual', 'none']) {
          for (final width in widths) {
            final layout = layoutSection(longText(width, hyphens: hyphens));
            expect(
              linesEndingInWords(layout),
              isEmpty,
              reason: '$hyphens at $width px',
            );
            layout.dispose();
          }
        }
      },
    );

    test('a page that ends inside a word ends at the letter before the '
        'hyphen, and the next page starts at the letter after it', () {
      var inside = 0;
      for (final width in widths) {
        final layout = layoutSection(longText(width, align: 'justify'));
        final dom = layout.section.dom;
        for (var index = 1; index < layout.pages.length; index++) {
          final end = layout.pages[index - 1].endPlace!;
          final start = layout.pages[index].startPlace!;
          if (!isLetter(charAt(dom, start)) ||
              start.offset == 0 ||
              !isLetter(
                charAt(
                  dom,
                  EpubPlace(start.section, start.node, start.offset - 1),
                ),
              )) {
            continue;
          }
          inside++;
          expect(end, EpubPlace(start.section, start.node, start.offset - 1));
          expect(quoteAt(dom, start), isNot(contains(softHyphen)));
          expect(quoteAt(dom, start), isNot(contains('‐')));
          expect(
            layout.pages[index].startVisible,
            layout.pages[index - 1].endVisible,
          );
        }
        layout.dispose();
      }
      expect(inside, greaterThan(0));
    });

    test('a run from any page start of hyphenated text cuts the same pages '
        'as the main run', () {
      for (final width in [214.0, 262.0]) {
        final section = longText(width, align: 'justify');
        final main = LayoutRun(section)..step(const Duration(days: 1));
        for (var page = 1; page < main.pages.length; page++) {
          final resumed = LayoutRun(section, from: main.pages[page].start)
            ..step(const Duration(days: 1));
          expect(
            keys(resumed.pages),
            keys(main.pages.skip(page)),
            reason: '$width px, page $page',
          );
          for (final laid in resumed.pages) {
            laid.dispose();
          }
          resumed.dispose();
        }
        for (final laid in main.pages) {
          laid.dispose();
        }
        main.dispose();
      }
    });
  });
}
