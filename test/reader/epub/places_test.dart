import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// The chapter of the engine's layout test (engine/test/layout.test.cjs),
/// whose fifth harbour passage epub.js saves as `epubcfi(/6/2!/4/26/1:0)`.
String harbour() {
  final paragraphs = List.generate(
    16,
    (index) =>
        '<p>Harbour passage ${index + 1}. The reader followed the shoreline '
        'and watched the small boats return. A bookmark could keep this place '
        'while the room grew dark.</p>',
  ).join();
  return '<h1>The quiet harbour</h1><p>This book was written for a '
      'disposable Bookfin reading test. No private library or published '
      'story is used.</p><p>Morning light filled the quiet harbour. Mira '
      'carried a lantern to the old reading room, where every shelf held a '
      'different journey.</p><p>The sepia square below is a local PNG '
      'image.</p><img src="/image.png" alt="A sepia PNG square"/><p>The next '
      'square is a local JPEG image.</p><img src="/image.png" alt="A sepia '
      'JPEG square"/><p><a href="two.xhtml">Visit the lantern room</a></p>'
      '$paragraphs';
}

void main() {
  setUpAll(loadReaderFont);

  test('a text place gets the CFI that epub.js gives it', () {
    final dom = DomSection.parse(section(harbour()).xhtml);
    final passage = dom.texts.firstWhere(
      (text) => text.text.startsWith('Harbour passage 5.'),
    );
    expect(
      cfiOf('/6/2', dom, EpubPlace(0, passage.order, 0)),
      'epubcfi(/6/2!/4/26/1:0)',
    );
  });

  test('a CFI names the text place that it was made from', () {
    final dom = DomSection.parse(section(harbour()).xhtml);
    for (final text in dom.texts) {
      for (final offset in [0, text.text.length ~/ 2]) {
        final cfi = cfiOf('/6/2', dom, EpubPlace(0, text.order, offset));
        final back = placeOf(dom, 0, cfi)!;
        expect(back, EpubPlace(0, text.order, offset), reason: cfi);
      }
    }
  });

  test('element ids become CFI assertions, as epub.js writes them', () {
    final dom = DomSection.parse(
      section('<section id="chapter-1"><p>Call me Ishmael.</p></section>')
          .xhtml,
    );
    final cfi = cfiOf('/6/4[c1]', dom, EpubPlace(1, dom.texts.single.order, 0));
    expect(cfi, 'epubcfi(/6/4[c1]!/4/2[chapter-1]/2/1:0)');
    expect(spineIndexOf(cfi), 1);
  });

  test('every page start opens on its own page again', () async {
    final chapter = await lay(
      '<h1>Harbour</h1>${[for (var i = 0; i < 25; i++) '<p>${prose(3, 'Part $i')}</p>'].join()}',
    );
    expect(chapter.pages.length, greaterThan(2));
    for (var page = 0; page < chapter.pages.length; page++) {
      final dom = chapter.section.dom;
      final start = chapter.pages[page].startPlace!;
      final cfi = cfiOf('/6/2', dom, wordStart(dom, start));
      final back = placeOf(dom, 0, cfi)!;
      expect(chapter.pageAt(back), page, reason: cfi);
    }
  });

  test('the quote and progress of a place follow reader.js', () {
    final dom = DomSection.parse(section('<p>One two</p>\n<p>three</p>').xhtml);
    final second = dom.texts.first;
    final place = EpubPlace(0, second.order, 4);
    // Range.toString keeps the white space between the paragraphs.
    expect(quoteAt(dom, place), 'two\nthree');
    expect(progressAt(dom, place), (3 / 11 * 1e6).round() / 1e6);
  });

  test('the spine step names the itemref position and its id', () {
    const opf =
        '<package><metadata/><manifest/><spine>'
        '<itemref idref="a"/><itemref idref="b" id="r2"/></spine></package>';
    expect(spineStep(opf, 0), '/6/2');
    expect(spineStep(opf, 1), '/6/4[r2]');
  });
}
