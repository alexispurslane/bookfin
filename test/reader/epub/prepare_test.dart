import 'dart:isolate';

import 'package:bookfin/reader/epub/css.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'helpers.dart';

/// Each page of [chapter]: where it starts and ends on the strip, the
/// number of slices that it holds, and its start.
List<Object?> pagesOf(ChapterLayout chapter) => [
  for (final page in chapter.pages)
    (page.top, page.bottom, page.slices.length, page.start, page.startPlace),
];

/// Each strip slice of [chapter]: its top, bottom and start place.
List<Object?> slicesOf(ChapterLayout chapter) => [
  for (final slice in chapter.slices) (slice.top, slice.bottom, slice.start),
];

/// A section with most of what prepare builds: a heading, a block image, a
/// list, raised text, a hanging indent, an inline image and a shrink-to-fit
/// box.
SectionSource richSection() => section(
  '<h1>Harbour</h1><p>${prose(12)}</p><img src="map.png"/>'
  '<ol><li>First stop.</li><li>Second <sup>2</sup> stop.</li></ol>'
  '<p class="verse">${prose(4, 'Verse')}</p>'
  '<p>A small <img src="map.png" style="width:40px"/> map.</p>'
  '<div class="card">Card text</div><p>${prose(20)}</p>',
  css:
      '.verse{padding-left:2em;text-indent:-2em}'
      '.card{display:inline-block;border:1px solid}',
  files: {'text/map.png': img.encodePng(img.Image(width: 300, height: 200))},
);

/// A section at `epub/text/one.xhtml` whose body is [body] and whose head
/// links `epub/css/book.css`, which holds [css].
SectionSource bookSection(String body, String css) => SectionSource(
  index: 0,
  path: 'epub/text/one.xhtml',
  xhtml:
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>T</title>'
      '<link href="../css/book.css" rel="stylesheet"/></head>'
      '<body>$body</body></html>',
  fontPrefix: testFontPrefix,
  styleSheets: {'epub/css/book.css': css},
);

/// The run style of the first text run of [prepared] that holds [text].
RunStyle runStyleOf(PreparedSection prepared, String text) {
  for (final item in prepared.flow) {
    if (item is! ParagraphItem) continue;
    for (final run in item.text.runs) {
      if (run is TextRun && run.text.contains(text)) {
        return prepared.styles[run.style];
      }
    }
  }
  throw StateError('No run holds "$text".');
}

/// Faces of the family Book: regular, italic and bold italic, and a face
/// of another family that nothing uses.
const bookFaces =
    '@font-face{font-family:Book;src:url(../fonts/regular.woff)}'
    '@font-face{font-family:Book;src:url(../fonts/italic.woff);'
    'font-style:italic}'
    '@font-face{font-family:Book;src:url(../fonts/bold-italic.woff);'
    'font-style:italic;font-weight:700}'
    '@font-face{font-family:Other;src:url(../fonts/other.woff)}';

void main() {
  setUpAll(loadReaderFont);

  test(
    'a section prepared in a worker isolate lays out to the same pages',
    () async {
      final source = richSection();
      final here = prepareSections([source], readerPage).single;
      final worker = await Isolate.run(
        () => prepareSections([source], readerPage).single,
      );
      final expected = layoutSection(here);
      final actual = layoutSection(worker);
      expect(pagesOf(actual), pagesOf(expected));
      expect(slicesOf(actual), slicesOf(expected));
      expect(expected.pages.length, greaterThan(1));
    },
  );

  test('an image takes its size from the section source', () async {
    await loadReaderFont();
    const source = SectionSource(
      index: 0,
      path: 'text/one.xhtml',
      xhtml:
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>T</title>'
          '</head><body><img src="map.png" style="display:block"/></body>'
          '</html>',
      fontPrefix: testFontPrefix,
      imageSizes: {'text/map.png': (300, 200)},
    );
    final chapter = layoutSection(prepareSections([source], readerPage).single);
    final image = chapter.decorations.whereType<ImageDecoration>().single;
    expect(image.path, 'text/map.png');
    expect((image.rect.width, image.rect.height), (300, 200));
  });

  test("each prepared section's places carry its spine index", () async {
    await loadReaderFont();
    final sources = [
      for (final index in [3, 4])
        SectionSource(
          index: index,
          path: 'text/$index.xhtml',
          xhtml: section('<p>${prose(30)}</p>').xhtml,
          fontPrefix: testFontPrefix,
        ),
    ];
    final prepared = prepareSections(sources, readerPage);
    expect([for (final section in prepared) section.index], [3, 4]);
    final chapter = layoutSection(prepared[1]);
    expect(chapter.pages.length, greaterThan(1));
    for (final page in chapter.pages) {
      expect(page.startPlace!.section, 4);
      expect(chapter.section.dom.textAt(page.startPlace!), isA<DomText>());
    }
  });

  test('a run in an embedded face draws with the face family of its book, '
      'and other runs with the reader font or monospace', () {
    final prepared = prepareSections([
      bookSection(
        '<p class="book">Embedded <code>code</code> <em>generic</em>'
            ' <i>undeclared</i></p>',
        '$bookFaces .book{font-family:"Missing",BOOK,serif}'
            ' em{font-family:sans-serif} i{font-family:Missing}',
      ),
    ], readerPage).single;
    expect(runStyleOf(prepared, 'Embedded').family, '$testFontPrefix-book');
    expect(runStyleOf(prepared, 'code').family, 'monospace');
    expect(runStyleOf(prepared, 'generic').family, readerFontFamily);
    expect(runStyleOf(prepared, 'undeclared').family, readerFontFamily);
  });

  test('a section lists the faces that its runs use, the nearest weight in '
      'the style that each run asks for', () {
    final prepared = prepareSections([
      bookSection(
        '<p>Plain <em>slanted</em> <b>heavy</b> <b><em>both</em></b></p>',
        '$bookFaces p{font-family:Book}',
      ),
    ], readerPage).single;
    expect(
      prepared.fonts,
      unorderedEquals(const [
        FontFaceRule(family: 'book', path: 'epub/fonts/regular.woff'),
        FontFaceRule(
          family: 'book',
          path: 'epub/fonts/italic.woff',
          italic: true,
        ),
        FontFaceRule(
          family: 'book',
          path: 'epub/fonts/bold-italic.woff',
          weight: 700,
          italic: true,
        ),
      ]),
    );
  });

  test('a section without embedded faces lists none', () {
    final prepared = prepareSections([
      bookSection('<p>Plain</p>', bookFaces),
    ], readerPage).single;
    expect(prepared.fonts, isEmpty);
  });

  test('a section with imported sheets and faces prepares the same in a '
      'worker isolate', () async {
    final source = SectionSource(
      index: 0,
      path: 'epub/text/one.xhtml',
      xhtml: bookSection('<p>${prose(20)} <em>${prose(4)}</em></p>', '').xhtml,
      fontPrefix: testFontPrefix,
      styleSheets: {
        'epub/css/book.css': '@import "faces.css"; p{font-family:Book}',
        'epub/css/faces.css': bookFaces,
      },
    );
    final here = prepareSections([source], readerPage).single;
    final worker = await Isolate.run(
      () => prepareSections([source], readerPage).single,
    );
    expect(here.fonts, hasLength(2));
    expect(worker.fonts, here.fonts);
    expect(worker.styles, here.styles);
    expect(pagesOf(layoutSection(worker)), pagesOf(layoutSection(here)));
  });

  test('page settings with the same values are one cache key', () {
    // Built at run time, so that the values are equal but not identical.
    PageSettings settings({double fontSize = 20, bool night = false}) =>
        PageSettings(width: 412, height: 671, fontSize: fontSize, night: night);
    final cache = {readerPage: 'cream'};
    expect(cache[settings()], 'cream');
    expect(cache[settings(night: true)], isNull);
    expect(cache[settings(fontSize: 23)], isNull);
  });

  group('excerpt', () {
    /// The DOM text that the lines of [chapter] show, line by line.
    List<String> linesOf(ChapterLayout chapter) => [
      for (final slice in chapter.slices)
        if (slice.piece case final piece?)
          [
            for (var unit = slice.units.$1; unit < slice.units.$2; unit++)
              if (piece.map.textPlaceAt(unit) case final place?)
                String.fromCharCode(
                  chapter.section.dom
                      .textAt(place)!
                      .text
                      .codeUnitAt(place.offset),
                ),
          ].join().trim(),
    ];

    const notes =
        '<h1>Chapter</h1><p>Before the notes.</p><ol epub:type="endnotes">'
        '<li id="note-1" epub:type="endnote"><p>The first note.</p></li>'
        '<li id="note-2" epub:type="endnote"><p>The second note.</p>'
        '<p>Its second paragraph.</p></li></ol><p>After the notes.</p>';

    test('the excerpt of an element lays out only the element\'s text, on a '
        'page of the given settings', () async {
      await loadReaderFont();
      final whole = prepared(notes);
      const sheet = PageSettings(
        width: 300,
        height: 100000,
        fontSize: 20,
        night: true,
      );
      final excerpt = whole.excerpt(whole.dom.elementById('note-2')!, sheet)!;
      final chapter = layoutSection(excerpt);
      addTearDown(chapter.dispose);

      expect(linesOf(chapter), ['The second note.', 'Its second paragraph.']);
      expect(chapter.pages, hasLength(1));
      expect(chapter.settings, sheet);
      expect(excerpt.dom, same(whole.dom));
    });

    test('an excerpt keeps the boxes around the element, so its lines and '
        'its list marker sit as they do on the page', () async {
      await loadReaderFont();
      final whole = prepared(notes);
      final page = layoutSection(whole);
      addTearDown(page.dispose);
      final excerpt = layoutSection(
        whole.excerpt(whole.dom.elementById('note-2')!, readerPage)!,
      );
      addTearDown(excerpt.dispose);

      double leftOf(ChapterLayout chapter, String text) => chapter.slices
          .firstWhere(
            (slice) =>
                slice.start != null &&
                chapter.section.dom.textAt(slice.start!)?.text == text,
          )
          .piece!
          .x;
      expect(
        leftOf(excerpt, 'The second note.'),
        leftOf(page, 'The second note.'),
      );
      expect(excerpt.decorations.whereType<MarkerDecoration>(), hasLength(1));
    });

    test('an element that no flow item shows, such as one that the style '
        'hides, has no excerpt', () {
      final whole = prepared(
        '<p>Text.</p><aside id="n"><p>Hidden.</p></aside><aside id="e"/>',
        css: '#n { display: none }',
      );
      expect(whole.excerpt(whole.dom.elementById('n')!, readerPage), isNull);
      expect(whole.excerpt(whole.dom.elementById('e')!, readerPage), isNull);
    });
  });
}
