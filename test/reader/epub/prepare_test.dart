import 'dart:isolate';

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

  test('page settings with the same values are one cache key', () {
    // Built at run time, so that the values are equal but not identical.
    PageSettings settings({double fontSize = 20, bool night = false}) =>
        PageSettings(width: 412, height: 671, fontSize: fontSize, night: night);
    final cache = {readerPage: 'cream'};
    expect(cache[settings()], 'cream');
    expect(cache[settings(night: true)], isNull);
    expect(cache[settings(fontSize: 23)], isNull);
  });
}
