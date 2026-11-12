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

  test('a page that draws with a font of the book is not kept', () {
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

    expect(KeptPage.encode(pages.first), isNull);
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
