import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/hyphenate.dart';
import 'package:bookfin/reader/epub/hyphenation_en.dart';
import 'package:bookfin/reader/epub/hyphenation_en_tables.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_test/flutter_test.dart';

import 'epubjs_fixtures.dart' show immediateSource;
import 'helpers.dart';
import 'page_source_test.dart' show book;

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

/// The start of Darcy's letter in Pride and Prejudice: ordinary prose.
const darcysLetter =
    'Be not alarmed, madam, on receiving this letter, by the apprehension '
    'of its containing any repetition of those sentiments or renewal of '
    'those offers which were last night so disgusting to you. I write '
    'without any intention of paining you, or humbling myself, by dwelling '
    'on wishes which, for the happiness of both, cannot be too soon '
    'forgotten; and the effort which the formation and the perusal of this '
    'letter must occasion, should have been spared, had not my character '
    'required it to be written and read. You must, therefore, pardon the '
    'freedom with which I demand your attention; your feelings, I know, '
    'will bestow it unwillingly, but I demand it of your justice. ';

/// How many times layout lays out the text of [section], one paragraph,
/// at its width: the code units that it lays out over the paragraph's.
double passes(PreparedSection section) {
  final before = LayoutRun.laidOutUnits;
  layoutSection(section).dispose();
  return (LayoutRun.laidOutUnits - before) / textOf(section).length;
}

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

  group('the const tables of hyphenation_en_tables.dart', () {
    // tool/reader/hyphenation_tables.dart writes them from
    // hyphenation_en.dart. Run it again when either changes.
    for (final (name, patterns, exceptions, patternTable, exceptionTable) in [
      (
        'American',
        enUsPatterns,
        enUsExceptions,
        enUsPatternTable,
        enUsExceptionTable,
      ),
      (
        'British',
        enGbPatterns,
        enGbExceptions,
        enGbPatternTable,
        enGbExceptionTable,
      ),
    ]) {
      test('hold the $name patterns and exceptions', () {
        expect(patternTable, hyphenationPatterns(patterns));
        expect(exceptionTable, hyphenationExceptions(exceptions));
      });
    }
  });

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

    test('a book whose pages name no language hyphenates when its package '
        'names English', () async {
      Future<String> text(String? language) async {
        final source = immediateSource(
          book(
            ['<p>manuscript</p>'],
            css: 'p{hyphens:auto}',
            language: language,
          ),
        )..settings = readerPage;
        addTearDown(source.dispose);
        return textOf(await source.section(0));
      }

      expect(await text('en'), 'man${softHyphen}u${softHyphen}script');
      expect(await text(null), 'manuscript');
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

    test('a long justified paragraph keeps the hyphens and lines that it had '
        'when each word joiner laid out the whole paragraph again', () {
      // The visible-character index of each line start, recorded before
      // tb-a6zd marked the hyphens of a long paragraph a few lines at a
      // time. The paragraph places about 30 word joiners at 20 pixels and
      // 47 at 26 pixels.
      const recorded = {
        20:
            '0 36 70 108 143 180 215 252 289 324 358 396 430 463 500 537 572 '
            '608 644 679 716 751 787 823 859 895 934 966 1005 1041 1076 1112 '
            '1149 1185 1221 1256 1292 1328 1363 1398 1435 1471 1505 1543 1578 '
            '1615 1650 1687 1724 1759 1793 1831 1865 1898 1935 1972 2007 2043 '
            '2079 2114 2151 2186 2222 2258 2294 2330 2369 2401 2440 2476 2511 '
            '2547 2584 2620 2656 2691 2727 2763 2798 2833 2870 2906 2940 2978 '
            '3013 3050 3085 3122 3159 3194 3228 3266 3300 3333 3370 3407 3442 '
            '3478 3514 3549 3586 3621 3657 3693 3729 3765 3804 3836 3875 3911 '
            '3946 3982 4019 4055 4091 4126 4162 4198 4233 4268 4305 4341 4375 '
            '4413 4448 4485 4520 4557 4594 4629 4663 4701 4735 4768 4805 4842 '
            '4877 4913',
        26:
            '0 26 51 75 98 122 146 172 196 221 244 269 295 319 341 365 390 413 '
            '436 461 485 508 532 556 582 606 631 654 679 705 729 751 775 800 '
            '823 846 871 895 918 942 966 992 1016 1041 1064 1089 1115 1139 1161 '
            '1185 1210 1233 1256 1281 1305 1328 1352 1376 1402 1426 1451 1474 '
            '1499 1525 1549 1571 1595 1620 1643 1666 1691 1715 1738 1762 1786 '
            '1812 1836 1861 1884 1909 1935 1959 1981 2005 2030 2053 2076 2101 '
            '2125 2148 2172 2196 2222 2246 2271 2294 2319 2345 2369 2391 2415 '
            '2440 2463 2486 2511 2535 2558 2582 2606 2632 2656 2681 2704 2729 '
            '2755 2779 2801 2825 2850 2873 2896 2921 2945 2968 2992 3016 3042 '
            '3066 3091 3114 3139 3165 3189 3211 3235 3260 3283 3306 3331 3355 '
            '3378 3402 3426 3452 3476 3501 3524 3549 3575 3599 3621 3645 3670 '
            '3693 3716 3741 3765 3788 3812 3836 3862 3886 3911 3934 3959 3985 '
            '4009 4031 4055 4080 4103 4126 4151 4175 4198 4222 4246 4272 4296 '
            '4321 4344 4369 4395 4419 4441 4465 4490 4513 4536 4561 4585 4608 '
            '4632 4656 4682 4706 4731 4754 4779 4805 4829 4851 4875 4900',
      };
      for (final settings in [
        readerPage,
        const PageSettings(width: 360, height: 640, fontSize: 26, night: false),
      ]) {
        final layout = layoutSection(
          prepared(
            '<div lang="en"><p>${longWords * 24}</p></div>',
            css: 'p{hyphens:auto;text-align:justify}',
            settings: settings,
          ),
        );
        final dom = layout.section.dom;
        final starts = [
          for (final line in layout.slices) dom.visibleBefore(line.start!),
        ];
        expect(
          starts.join(' '),
          recorded[settings.fontSize.round()],
          reason: '${settings.fontSize} px',
        );
        layout.dispose();
      }
    });

    test('a hyphenated paragraph of ordinary prose lays out in about two '
        'passes at every width, however its hyphens kern', () {
      // One pass marks the line ends a few lines at a time, and one lays
      // out the paragraph with its hyphens. Each word joiner lays out a few
      // lines again. A hyphen whose kerning made it not fit after all cost
      // another pass over the paragraph, and the marks after it again: up
      // to 20 passes before tb-o242.
      for (final size in [20.0, 26.0]) {
        for (var width = 200.0; width <= 400; width += 5) {
          final section = prepared(
            '<div lang="en"><p>${darcysLetter * 8}</p></div>',
            css: 'p{hyphens:auto;text-align:justify}',
            settings: PageSettings(
              width: width,
              height: 640,
              fontSize: size,
              night: false,
            ),
          );
          expect(
            passes(section),
            lessThan(3.5),
            reason: '$width px wide at $size px',
          );
        }
      }
    });

    test('a hyphenated paragraph of long words lays out in a few passes at '
        'every width, however its hyphens kern', () {
      // Most lines of these words end in a word joiner, and each joiner
      // lays out a few lines again: 2 to 7 passes. A hyphen whose kerning
      // made it not fit after all cost up to 32 passes before tb-o242.
      for (final size in [20.0, 26.0]) {
        for (var width = 200.0; width <= 400; width += 7) {
          final section = prepared(
            '<div lang="en"><p>${longWords * 24}</p></div>',
            css: 'p{hyphens:auto;text-align:justify}',
            settings: PageSettings(
              width: width,
              height: 640,
              fontSize: size,
              night: false,
            ),
          );
          expect(
            passes(section),
            lessThan(8),
            reason: '$width px wide at $size px',
          );
        }
      }
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
