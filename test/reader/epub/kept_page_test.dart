// The kept page: the drawn form of a laid page, kept as the inputs of its
// drawing, so that a reopen of the book can draw it before the book loads
// (boo-sy2d). It must draw the same pixels as the page that it keeps, or
// nothing.
import 'dart:convert';

import 'package:bookfin/reader/epub/kept_page.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'layout_run_test.dart' show pixels, runToEnd, sampleSections, smallPage;
import 'table_test.dart' show etymology, etymologyCss;

/// The pixels of [kept] at its page size.
Future<List<int>> keptPixels(KeptPage kept) async {
  final image = await kept.picture!.toImage(
    kept.settings.width.round(),
    kept.settings.height.round(),
  );
  final bytes = await image.toByteData();
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// The pages that the tests keep: at most [limit] pages of each sample
/// section, in both themes, and a table.
List<LaidPage> samplePages({int limit = 6}) => [
  for (final section in [
    ...sampleSections(),
    ...prepareSections([
      section(prose(30)),
    ], const PageSettings(width: 360, height: 640, fontSize: 18, night: true)),
    ...prepareSections([section(etymology, css: etymologyCss)], smallPage),
  ])
    ...() {
      final pages = runToEnd(section);
      for (final page in pages.skip(limit)) {
        page.dispose();
      }
      return pages.take(limit);
    }(),
];

void main() {
  setUpAll(loadReaderFont);

  test('a kept page draws the same pixels as the page that it keeps', () async {
    final pages = samplePages();
    addTearDown(() {
      for (final page in pages) {
        page.dispose();
      }
    });
    expect(pages, hasLength(greaterThan(40)));
    for (final (index, page) in pages.indexed) {
      final kept = KeptPage.decode(KeptPage.encode(page)!)!;
      addTearDown(kept.dispose);
      expect(
        await keptPixels(kept),
        await pixels(page),
        reason: 'page $index of section ${page.section}',
      );
    }
  });

  test('a kept page of a page of text takes at most 20 KB', () {
    final pages = samplePages(limit: 3);
    addTearDown(() {
      for (final page in pages) {
        page.dispose();
      }
    });
    for (final page in pages) {
      expect(utf8.encode(KeptPage.encode(page)!).length, lessThan(20 << 10));
    }
  });

  test('a kept page depicts the page that it keeps and no other', () {
    final pages = runToEnd(
      prepareSections([section(prose(30))], readerPage).single,
    );
    addTearDown(() {
      for (final page in pages) {
        page.dispose();
      }
    });
    final kept = KeptPage.decode(KeptPage.encode(pages[1])!)!;
    addTearDown(kept.dispose);

    expect(kept.depicts(pages[1]), isTrue);
    expect(kept.depicts(pages[0]), isFalse);
    expect(kept.depicts(pages[2]), isFalse);
  });

  test('a kept page depicts its page when a run from that page cut it, as '
      'a reopen does, at settings whose sums do not round evenly', () {
    const odd = PageSettings(
      width: 411.42857142857144,
      height: 843.43,
      fontSize: 19.8,
      night: false,
      sizesMainText: true,
    );
    for (final section in [
      ...sampleSections(),
      ...prepareSections([
        section(
          [
            for (var i = 0; i < 60; i++)
              '<p>${prose(2, 'Part $i')}</p>'
                  '${i % 7 == 0 ? '<h2>Heading $i</h2>' : ''}',
          ].join(),
          css: 'p{margin:.37em 0 .61em} h2{margin:1.13em 0 .7em}',
        ),
      ], odd),
    ]) {
      final main = runToEnd(section);
      for (var at = 1; at < main.length; at++) {
        final resumed = runToEnd(section, from: main[at].start);
        final kept = KeptPage.decode(KeptPage.encode(main[at])!)!;
        expect(
          kept.depicts(resumed.first),
          isTrue,
          reason: 'page $at of section ${section.index} at ${section.settings}',
        );
        kept.dispose();
        for (final page in resumed) {
          page.dispose();
        }
      }
      for (final page in main) {
        page.dispose();
      }
    }
  });

  test('a run style keeps each of its fields through its JSON', () {
    const style = RunStyle(
      family: 'monospace',
      size: 17.5,
      weight: 700,
      italic: true,
      letterSpacing: .25,
      wordSpacing: 1.5,
      lineHeight: 26.25,
      underline: true,
      lineThrough: true,
      smallCaps: true,
      oldstyleFigures: true,
    );

    expect(RunStyle.fromJson(jsonDecode(jsonEncode(style.toJson()))), style);
  });

  test('a page that uses no book font is still kept, though its book styles '
      'its text with its own font', () {
    final pages = runToEnd(
      prepareSections([
        section(
          '<p>${prose(6)}</p>',
          css:
              '@font-face{font-family:Outfit;src:url(../fonts/outfit.woff)}'
              'p{font-family:Outfit,serif}',
        ),
      ], readerPage).single,
    );
    addTearDown(() {
      for (final page in pages) {
        page.dispose();
      }
    });

    final body = KeptPage.encode(pages.first);
    expect(body, isNotNull);
    final kept = KeptPage.decode(body!);
    addTearDown(() => kept?.dispose());
    expect(kept!.depicts(pages.first), isTrue);
  });

  test('a page that draws with a font of the book is not kept, and a later '
      'page of the same section without it is kept', () {
    final pages = runToEnd(
      prepareSections([
        section(
          '<p class="star">A star \u2605 here.</p><p>${prose(60)}</p>',
          css:
              '@font-face{font-family:Star;src:url(../fonts/star.woff)}'
              '.star{font-family:Star,serif}',
          faces: {'fonts/star.woff': 'kept-page-star'},
        ),
      ], readerPage).single,
    );
    addTearDown(() {
      for (final page in pages) {
        page.dispose();
      }
    });
    expect(pages, hasLength(greaterThan(1)));

    expect(KeptPage.encode(pages.first), isNull);
    expect(KeptPage.encode(pages.last), isNotNull);
  });

  test('a kept page whose bytes are damaged decodes to nothing', () {
    final pages = runToEnd(
      prepareSections([section(prose(10))], readerPage).single,
    );
    addTearDown(() {
      for (final page in pages) {
        page.dispose();
      }
    });
    final body = KeptPage.encode(pages.first)!;

    for (final damaged in [
      '',
      'not a page',
      body.substring(0, body.length ~/ 2),
      body.replaceFirst('"pieces"', '"places"'),
      '[]',
    ]) {
      expect(KeptPage.decode(damaged), isNull, reason: damaged);
    }
  });
}
