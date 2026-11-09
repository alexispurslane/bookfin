import 'dart:convert';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/showcase_media.dart' as media;
import 'helpers.dart';

/// The chapter of epub.js's layout test (engine/test/layout.test.cjs, which
/// tc-rap6 deleted), whose fifth harbour passage epub.js saved as
/// `epubcfi(/6/2!/4/26/1:0)`.
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

/// The section of [body], parsed.
DomSection dom(String body) => DomSection.parse(section(body).xhtml);

/// The section [xhtml], a whole document, parsed.
DomSection document(String xhtml) => DomSection.parse(
  '<html xmlns="http://www.w3.org/1999/xhtml">$xhtml</html>',
);

/// The place at [offset] in the text node of [dom] that starts with
/// [prefix].
EpubPlace at(DomSection dom, String prefix, [int offset = 0]) => EpubPlace(
  0,
  dom.texts.firstWhere((text) => text.text.startsWith(prefix)).order,
  offset,
);

/// The place of the element of [dom] whose id is [id].
EpubPlace element(DomSection dom, String id) {
  for (var order = 0; ; order++) {
    if (dom.nodeAt(order) case DomElement(id: final found) when found == id) {
      return EpubPlace(0, order, 0);
    }
  }
}

/// The number of characters of [text] that are not white space.
int visible(String text) => text.replaceAll(RegExp(r'\s'), '').length;

/// What the WebView reader saved for the books of tool/showcase_media.dart:
/// each page start that reader.js reported, each contents destination, and
/// one search hit per query, recorded from reader.js in headless Chromium
/// at 20 pixels on 2026-11-08 (ticket tc-sqp7).
const _savedByWebView =
    <(String book, String kind, String? href, Map<String, Object> location)>[
      (
        "frost",
        "page",
        null,
        {
          'cfi': "epubcfi(/6/2!/4/2/2/1:0)",
          'resource': "OEBPS/chapter1.xhtml",
          'quote': "One. The Grafted TreesWren came back to the orchard on the first cold morning of October, when the grass along the lane ",
          'progress': 0,
          'chapter': "One. The Grafted Trees",
        },
      ),
      (
        "frost",
        "page",
        null,
        {
          'cfi': "epubcfi(/6/2!/4/2/8/1:150)",
          'resource': "OEBPS/chapter1.xhtml",
          'quote': "put her hand on the nearest union and felt the ridge of it under the bark, warm in a way that the air was not.In the vil",
          'progress': 0.607022,
          'chapter': "One. The Grafted Trees",
        },
      ),
      (
        "frost",
        "page",
        null,
        {
          'cfi': "epubcfi(/6/4!/4/2/2/1:0)",
          'resource': "OEBPS/chapter2.xhtml",
          'quote': "Two. The Ledger in the BarnHer grandmother kept a ledger for the orchard, a long green book with a cloth spine, and Wren",
          'progress': 0,
          'chapter': "Two. The Ledger in the Barn",
        },
      ),
      (
        "frost",
        "page",
        null,
        {
          'cfi': "epubcfi(/6/4!/4/2/10/1:0)",
          'resource': "OEBPS/chapter2.xhtml",
          'quote': "The final page was dated two winters ago. The first frost was written in, and nothing else. No harvest. No blossom. And ",
          'progress': 0.75,
          'chapter': "Two. The Ledger in the Barn",
        },
      ),
      (
        "frost",
        "page",
        null,
        {
          'cfi': "epubcfi(/6/6!/4/2/2/1:0)",
          'resource': "OEBPS/chapter3.xhtml",
          'quote': "Three. What the Orchard RemembersThat night the wind turned and came down off the ridge, and Wren lay awake listening to",
          'progress': 0,
          'chapter': "Three. What the Orchard Remembers",
        },
      ),
      (
        "frost",
        "page",
        null,
        {
          'cfi': "epubcfi(/6/6!/4/2/8/1:159)",
          'resource': "OEBPS/chapter3.xhtml",
          'quote': "stove. Wren had thought it was a saying. Now she was not so sure.",
          'progress': 0.905282,
          'chapter': "Three. What the Orchard Remembers",
        },
      ),
      (
        "frost",
        "destination",
        "chapter1.xhtml",
        {
          'cfi': "epubcfi(/6/2!/4/2/2/1:0)",
          'resource': "OEBPS/chapter1.xhtml",
          'quote': "One. The Grafted TreesWren came back to the orchard on the first cold morning of October, when the grass along the lane ",
          'chapter': "One. The Grafted Trees",
        },
      ),
      (
        "frost",
        "destination",
        "chapter2.xhtml",
        {
          'cfi': "epubcfi(/6/4!/4/2/2/1:0)",
          'resource': "OEBPS/chapter2.xhtml",
          'quote': "Two. The Ledger in the BarnHer grandmother kept a ledger for the orchard, a long green book with a cloth spine, and Wren",
          'chapter': "Two. The Ledger in the Barn",
        },
      ),
      (
        "frost",
        "destination",
        "chapter3.xhtml",
        {
          'cfi': "epubcfi(/6/6!/4/2/2/1:0)",
          'resource': "OEBPS/chapter3.xhtml",
          'quote': "Three. What the Orchard RemembersThat night the wind turned and came down off the ridge, and Wren lay awake listening to",
          'chapter': "Three. What the Orchard Remembers",
        },
      ),
      (
        "frost",
        "hit",
        null,
        {
          'cfi': "epubcfi(/6/2!/4/2/2/1:5)",
          'resource': "OEBPS/chapter1.xhtml",
          'quote': "The Grafted TreesWren came back to the orchard on the first cold morning of October, when the grass along the lane was s",
          'chapter': "One. The Grafted Trees",
        },
      ),
      (
        "frost",
        "hit",
        null,
        {
          'cfi': "epubcfi(/6/2!/4/2/4/1:114)",
          'resource': "OEBPS/chapter1.xhtml",
          'quote': "and the sun had not yet cleared the ridge. She left the car at the gate and walked the last of it, the way her grandmoth",
          'chapter': "One. The Grafted Trees",
        },
      ),
      (
        "frost",
        "hit",
        null,
        {
          'cfi': "epubcfi(/6/2!/4/2/10/1:122)",
          'resource': "OEBPS/chapter1.xhtml",
          'quote': "said that the frost had come early this year, and looked at the floor while he said it.\"Who has been looking after the t",
          'chapter': "One. The Grafted Trees",
        },
      ),
      (
        "salt",
        "page",
        null,
        {
          'cfi': "epubcfi(/6/2!/4/2/2/1:0)",
          'resource': "OEBPS/chapter1.xhtml",
          'quote': "The Harbor LightThe lamp at the end of the harbor wall burned whale oil until the winter of the long ice, and then it bu",
          'progress': 0,
          'chapter': "The Harbor Light",
        },
      ),
      (
        "salt",
        "page",
        null,
        {
          'cfi': "epubcfi(/6/4!/4/2/2/1:0)",
          'resource': "OEBPS/chapter2.xhtml",
          'quote': "SaltIn the spring the salt traders came back from the south with their carts, and the town paid them in fish and in stor",
          'progress': 0,
          'chapter': "Salt",
        },
      ),
      (
        "salt",
        "destination",
        "chapter1.xhtml",
        {
          'cfi': "epubcfi(/6/2!/4/2/2/1:0)",
          'resource': "OEBPS/chapter1.xhtml",
          'quote': "The Harbor LightThe lamp at the end of the harbor wall burned whale oil until the winter of the long ice, and then it bu",
          'chapter': "The Harbor Light",
        },
      ),
      (
        "salt",
        "destination",
        "chapter2.xhtml",
        {
          'cfi': "epubcfi(/6/4!/4/2/2/1:0)",
          'resource': "OEBPS/chapter2.xhtml",
          'quote': "SaltIn the spring the salt traders came back from the south with their carts, and the town paid them in fish and in stor",
          'chapter': "Salt",
        },
      ),
      (
        "salt",
        "hit",
        null,
        {
          'cfi': "epubcfi(/6/2!/4/2/4/1:12)",
          'resource': "OEBPS/chapter1.xhtml",
          'quote': "the end of the harbor wall burned whale oil until the winter of the long ice, and then it burned whatever the town could",
          'chapter': "The Harbor Light",
        },
      ),
      (
        "salt",
        "hit",
        null,
        {
          'cfi': "epubcfi(/6/2!/4/2/4/1:90)",
          'resource': "OEBPS/chapter1.xhtml",
          'quote': "and then it burned whatever the town could spare. Tallow. Lard. Once, for three nights, the last of the church candles.A",
          'chapter': "The Harbor Light",
        },
      ),
      (
        "winter",
        "page",
        null,
        {
          'cfi': "epubcfi(/6/2!/4/2/2/1:0)",
          'resource': "OEBPS/chapter1.xhtml",
          'quote': "JanuaryThe snow keeps its own accounts.It writes the fox, the wren, the wheel,and every morning wipes the pagefor someon",
          'progress': 0,
          'chapter': "January",
        },
      ),
      (
        "winter",
        "page",
        null,
        {
          'cfi': "epubcfi(/6/4!/4/2/2/1:0)",
          'resource': "OEBPS/chapter2.xhtml",
          'quote': "FebruaryA thaw, and then a hard frost on the thaw.The yard is glass. The hens refuse it.I owe the woodpile more than I c",
          'progress': 0,
          'chapter': "February",
        },
      ),
      (
        "winter",
        "destination",
        "chapter1.xhtml",
        {
          'cfi': "epubcfi(/6/2!/4/2/2/1:0)",
          'resource': "OEBPS/chapter1.xhtml",
          'quote': "JanuaryThe snow keeps its own accounts.It writes the fox, the wren, the wheel,and every morning wipes the pagefor someon",
          'chapter': "January",
        },
      ),
      (
        "winter",
        "destination",
        "chapter2.xhtml",
        {
          'cfi': "epubcfi(/6/4!/4/2/2/1:0)",
          'resource': "OEBPS/chapter2.xhtml",
          'quote': "FebruaryA thaw, and then a hard frost on the thaw.The yard is glass. The hens refuse it.I owe the woodpile more than I c",
          'chapter': "February",
        },
      ),
      (
        "winter",
        "hit",
        null,
        {
          'cfi': "epubcfi(/6/2!/4/2/4/3:10)",
          'resource': "OEBPS/chapter1.xhtml",
          'quote': "the fox, the wren, the wheel,and every morning wipes the pagefor someone else to sign.I walk the lane to read itbefore t",
          'chapter': "January",
        },
      ),
      (
        "winter",
        "hit",
        null,
        {
          'cfi': "epubcfi(/6/4!/4/2/4/1:8)",
          'resource': "OEBPS/chapter2.xhtml",
          'quote': "and then a hard frost on the thaw.The yard is glass. The hens refuse it.I owe the woodpile more than I can payand the wo",
          'chapter': "February",
        },
      ),
    ];

/// The showcase book [name], admitted as Bookfin admits it.
Publication _showcase(String name) => Publication.admit(switch (name) {
  'frost' => media.epub(
    'frost',
    'First Frost',
    'Bookfin Showcase',
    media.firstFrost,
  ),
  'salt' => media.epub(
    'salt',
    'Salt and Lantern',
    'Bookfin Showcase',
    media.saltAndLantern,
  ),
  _ => media.epub(
    'winter',
    'The Winter Ledger',
    'Bookfin Showcase',
    media.winterLedger,
  ),
});

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

  test('the spine steps of a whole book come from one reading of its package '
      'document, in spine order', () {
    const opf =
        '<package><metadata/><manifest/><guide/><spine>'
        '<itemref idref="a" id="r1"/><itemref idref="b"/>'
        '<itemref idref="c" id=""/></spine></package>';
    expect(spineSteps(opf), ['/8/2[r1]', '/8/4', '/8/6']);
  });

  group('the saved start of a page', () {
    test('a page that starts at a node\'s first word saves the node start', () {
      final section = dom('<p>\n  Call me Ishmael.</p>');
      final start = at(section, '\n', 3);
      expect(wordStart(section, start), at(section, '\n'));
    });

    test('a text node that starts with white space saves the space before '
        'the page\'s first word, as epub.js does', () {
      // A Gutenberg paragraph starts with a line break, so epub.js's ranges
      // start one character before their words.
      final section = dom('<p>\nwe felt the speech</p>');
      final start = at(section, '\n', 9);
      expect(wordStart(section, start), at(section, '\n', 8));
    });

    test(
      'a range of white space alone before a page is on the line before',
      () {
        // Frankenstein, letter 4, and Pride and Prejudice, chapter 43, at 23
        // pixels: the page starts at "a", whose range holds only the space
        // before it, so epub.js saved the next range.
        final section = dom('<p>\nwe felt a speech coming</p>');
        final start = at(section, '\n', 9);
        expect(wordStart(section, start), at(section, '\n', 10));
      },
    );

    test('the word after a node\'s first space is never a saved start, as '
        'epub.js splits a node', () {
      final section = dom('<p>one two three four</p>');
      expect(wordStart(section, at(section, 'one', 4)), at(section, 'one', 8));
    });

    test('a page start with no later word start in its node keeps its own '
        'place, so it never moves to the page before', () {
      final section = dom('<p>one two</p>');
      expect(wordStart(section, at(section, 'one', 4)), at(section, 'one', 4));
    });
  });

  group('CFIs', () {
    test('a range resolves to its start', () {
      final section = dom('<p>Call me Ishmael.</p>');
      expect(
        placeOf(section, 0, 'epubcfi(/6/2!/4/2,/1:5,/1:7)'),
        at(section, 'Call', 5),
      );
    });

    test('an offset past the end of a text node stops at its end', () {
      final section = dom('<p>Call me Ishmael.</p>');
      expect(
        placeOf(section, 0, 'epubcfi(/6/2!/4/2/1:99)'),
        at(section, 'Call', 'Call me Ishmael.'.length),
      );
    });

    test('a path that does not exist names no place', () {
      final section = dom('<p>Call me Ishmael.</p>');
      expect(placeOf(section, 0, 'epubcfi(/6/2!/4/8/1:0)'), isNull);
    });
  });

  group('quotes and progress', () {
    test('a quote runs across text nodes and stops at 120 characters', () {
      final section = dom(
        '<p>Call <em>me</em> Ishmael.</p><p>${'Some years ago. ' * 10}</p>',
      );
      final quote = quoteAt(section, at(section, 'Call'));
      expect(quote, startsWith('Call me Ishmael.Some years ago.'));
      expect(quote.length, 120);
    });

    test('the quote of an element starts at its first text', () {
      final section = dom('<p id="first">Call me Ishmael.</p>');
      expect(quoteAt(section, element(section, 'first')), 'Call me Ishmael.');
    });

    test('progress counts only the characters that are not white space', () {
      final section = dom('<p>a  b</p>\n\n<p>c d</p>');
      expect(progressAt(section, at(section, 'c')), 0.5);
      expect(progressAt(section, at(section, 'c', 2)), 0.75);
    });

    test('a saved quote matches when the text at its place starts with it', () {
      final section = dom('<p>Call me Ishmael.</p><p>Some years ago.</p>');
      final place = at(section, 'Call', 5);
      expect(quoteMatches(section, place, 'me Ishmael.Some'), isTrue);
      expect(quoteMatches(section, place, 'Call me'), isFalse);
    });

    test('an empty saved quote matches any place', () {
      final section = dom('<p>Call me Ishmael.</p>');
      expect(quoteMatches(section, at(section, 'Call', 3), ''), isTrue);
    });
  });

  group('the place at a text progress', () {
    const text = '<p>\n  Call me</p>\n<p>Ishmael.</p>\n';

    test('progress 0 is the first visible character', () {
      final section = dom(text);
      expect(placeAt(section, 0, 0), at(section, '\n', 3));
    });

    test('progress 1 is the last visible character', () {
      final section = dom(text);
      expect(placeAt(section, 0, 1), at(section, 'Ishmael', 7));
    });

    test('a progress names the visible character that many characters in', () {
      final section = dom(text);
      // 14 visible characters: floor(0.45 × 14) = 6, the "I" of "Ishmael".
      expect(placeAt(section, 0, 0.45), at(section, 'Ishmael'));
      expect(progressAt(section, placeAt(section, 0, 0.45)), 0.428571);
    });

    test('a section without text starts at its body', () {
      final section = dom('<img src="cover.png" alt=""/>');
      expect(placeAt(section, 0, 0.5), EpubPlace(0, section.body.order, 0));
    });

    test('a progress outside 0 to 1 is refused', () {
      final section = dom(text);
      expect(() => placeAt(section, 0, 1.5), throwsArgumentError);
      expect(() => placeAt(section, 0, double.nan), throwsArgumentError);
    });
  });

  group('destinations', () {
    test('a fragment leads to the first text in its element, even white '
        'space', () {
      final section = dom(
        '<p>Before.</p><section id="two">\n<h2>Two</h2></section>',
      );
      final place = destination(section, 0, 'two')!;
      expect(place, at(section, '\n'));
      expect(cfiOf('/6/2', section, place), 'epubcfi(/6/2!/4/4[two]/1:0)');
    });

    test('no fragment leads to the first text of the body', () {
      final section = dom('<p>Call me Ishmael.</p>');
      expect(destination(section, 0, null), at(section, 'Call'));
      expect(destination(section, 0, ''), at(section, 'Call'));
    });

    test('a destination without text is its element', () {
      final section = dom('<p>Call me.</p><img id="map" src="map.png"/>');
      final place = destination(section, 0, 'map')!;
      expect(place, element(section, 'map'));
      expect(cfiOf('/6/2', section, place), 'epubcfi(/6/2!/4/4[map])');
    });

    test('a fragment that names no element has no destination', () {
      final section = dom('<p>Call me Ishmael.</p>');
      expect(destination(section, 0, 'missing'), isNull);
    });
  });

  group('chapter titles', () {
    const contents = [
      ContentsEntry('One', 'text/one.xhtml#one'),
      ContentsEntry('Two', 'text/one.xhtml#two'),
      ContentsEntry('Elsewhere', 'text/two.xhtml'),
    ];
    String title(DomSection section, EpubPlace place) =>
        chapterTitle(section, place, contents, 'content.opf', 'text/one.xhtml');

    test('a place takes the last contents entry of its section at or before '
        'it', () {
      final section = dom(
        '<p>Preface.</p><h2 id="one">One</h2><p>First.</p>'
        '<h2 id="two">Two</h2><p>Second.</p>',
      );
      expect(title(section, at(section, 'First')), 'One');
      expect(title(section, at(section, 'Two')), 'Two');
      expect(title(section, at(section, 'Second', 3)), 'Two');
    });

    test('contents hrefs resolve against the package document', () {
      final section = dom('<h2 id="one">One</h2><p>First.</p>');
      expect(
        chapterTitle(
          section,
          at(section, 'First'),
          const [ContentsEntry('One', 'one.xhtml#one')],
          'OEBPS/content.opf',
          'OEBPS/one.xhtml',
        ),
        'One',
      );
    });

    test('an entry without a fragment starts at the section start', () {
      final section = dom('<p>Call me Ishmael.</p>');
      expect(
        chapterTitle(
          section,
          at(section, 'Call', 5),
          const [ContentsEntry('Loomings', 'text/one.xhtml')],
          'content.opf',
          'text/one.xhtml',
        ),
        'Loomings',
      );
    });

    test('before every entry, the title element names the chapter', () {
      final section = dom('<p>Preface.</p><h2 id="one">One</h2>');
      expect(title(section, at(section, 'Preface')), 'Test');
    });

    test('the first h1 or title in document order names the chapter', () {
      final section = document(
        '<head></head><body><h1>\n The Harbour \n</h1><p>Text.</p></body>',
      );
      expect(title(section, at(section, 'Text')), 'The Harbour');
    });

    test('a section with neither is Chapter N', () {
      final section = document('<head></head><body><p>Text.</p></body>');
      final place = EpubPlace(4, at(section, 'Text').node, 0);
      expect(title(section, place), 'Chapter 5');
    });

    test('an empty title makes Chapter N, as reader.js reads only the first '
        'match', () {
      final section = document(
        '<head><title> </title></head><body><h1>Harbour</h1></body>',
      );
      expect(title(section, at(section, 'Harbour')), 'Chapter 1');
    });

    test('entries compare as epub.js compares CFIs: a sibling\'s index among '
        'its own kind', () {
      // The text "Intro " is the div's text child 0 and the span is its
      // element child 0, so epub.js counts the span as at the text.
      final section = dom(
        '<h2 id="one">One</h2><div>Intro <span id="two">Two</span></div>',
      );
      expect(title(section, at(section, 'Intro')), 'Two');
    });

    test('a long title is cut at 512 characters', () {
      final section = dom('<p>Call me Ishmael.</p>');
      final long = 'Loomings ' * 100;
      expect(
        chapterTitle(
          section,
          at(section, 'Call'),
          [ContentsEntry(long, 'text/one.xhtml')],
          'content.opf',
          'text/one.xhtml',
        ),
        long.substring(0, 512),
      );
    });
  });

  group('saved locations', () {
    test('a page saves the CFI, quote and progress of its word start', () {
      final section = dom('<p>\nwe felt a speech coming</p>');
      final location = pageLocation(
        '/6/2',
        'text/one.xhtml',
        section,
        at(section, '\n', 9),
        at(section, '\n', 22),
        'Harbour',
      );
      expect(location.cfi, 'epubcfi(/6/2!/4/2/1:10)');
      expect(location.resource, 'text/one.xhtml');
      expect(location.quote, ' speech coming');
      // "wefelta" comes before the word start, of 19 visible characters.
      expect(location.progress, 0.368421);
      expect(location.chapter, 'Harbour');
    });

    test('a page ends at the progress of its last visible character', () {
      final section = dom('<p>\nwe felt a speech coming</p>');
      final location = pageLocation(
        '/6/2',
        'text/one.xhtml',
        section,
        at(section, '\n'),
        at(section, '\n', 15),
        'Harbour',
      );
      // "wefeltaspee" comes before the "c" of "speech": 11 of 19.
      expect(location.end, 0.578947);
    });

    test('a search hit saves its match start, without a progress, as '
        'reader.js does', () {
      final section = dom('<p>\nwe felt a speech coming</p>');
      final location = hitLocation(
        '/6/2',
        'text/one.xhtml',
        section,
        at(section, '\n', 13),
        'Harbour',
      );
      expect(location.cfi, 'epubcfi(/6/2!/4/2/1:13)');
      expect(location.quote, 'eech coming');
      expect(location.progress, isNull);
      expect(location.chapter, 'Harbour');
    });

    test('the harbour passage page saves the CFI that epub.js saved', () {
      final section = DomSection.parse(
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>One'
        '</title></head><body>${harbour()}</body></html>',
      );
      final passage = section.texts.firstWhere(
        (text) => text.text.startsWith('Harbour passage 5.'),
      );
      final next = section.texts.firstWhere(
        (text) => text.text.startsWith('Harbour passage 6.'),
      );
      final location = pageLocation(
        '/6/2',
        'OPS/one.xhtml',
        section,
        EpubPlace(0, passage.order, 0),
        EpubPlace(0, next.order, 0),
        'The quiet harbour',
      );
      final document = EpubDocument(
        Publication.admit(
          media.epub('frost', 'First Frost', 'Bookfin', media.firstFrost),
        ),
      );
      final saved = document.save(EpubAddress(location));
      final before = harbour().split('<p>Harbour passage 5.').first;
      final whole = visible(harbour().replaceAll(RegExp('<[^>]*>'), ''));
      expect(saved, {
        'version': 1,
        'processed': document.identity,
        'original': document.originalDigest,
        'policy': document.policy,
        'engine': 'epubjs-0.3.93-bookfin.1',
        'cfi': 'epubcfi(/6/2!/4/26/1:0)',
        'resource': 'OPS/one.xhtml',
        'quote': quoteAt(section, EpubPlace(0, passage.order, 0)),
        'progress':
            (visible(before.replaceAll(RegExp('<[^>]*>'), '')) / whole * 1e6)
                .round() /
            1e6,
      });
      expect(saved['quote'], startsWith('Harbour passage 5.'));
      expect(document.restore(saved), isNull, reason: 'not in this spine');
    });

    test(
      'a saved location writes the same JSON as before, without its end',
      () {
        const location = ReadingLocation(
          'epubcfi(/6/2!/4/26/1:0)',
          'OPS/one.xhtml',
          'Harbour passage 5.',
          chapter: 'The quiet harbour',
          page: 3,
          pages: 5,
          progress: 0.25,
          end: 0.3,
        );
        expect(location.toJson(), {
          'cfi': 'epubcfi(/6/2!/4/26/1:0)',
          'resource': 'OPS/one.xhtml',
          'quote': 'Harbour passage 5.',
          'progress': 0.25,
        });
        expect(
          ReadingLocation.fromJson({...location.toJson(), 'end': 0.3}).end,
          isNull,
        );
      },
    );
  });

  test('every place that the WebView reader saved in the showcase books '
      'resolves to the same text and writes the same JSON', () {
    final books = {
      for (final name in ['frost', 'salt', 'winter']) name: _showcase(name),
    };
    for (final (book, kind, href, saved) in _savedByWebView) {
      final publication = books[book]!;
      final resource = saved['resource']! as String;
      final index = publication.spine.indexOf(resource);
      final section = DomSection.parse(
        utf8.decode(publication.resources[resource]!),
      );
      final spine = spineStep(
        utf8.decode(publication.resources[publication.packagePath]!),
        index,
      );
      final cfi = saved['cfi']! as String;
      final place = placeOf(section, index, cfi)!;
      final chapter = chapterTitle(
        section,
        place,
        publication.contents,
        publication.packagePath,
        resource,
      );
      final location = switch (kind) {
        'page' => pageLocation(spine, resource, section, place, place, chapter),
        'hit' => hitLocation(spine, resource, section, place, chapter),
        _ => hitLocation(
          spine,
          resource,
          section,
          destination(section, index, Uri.parse(href!).fragment)!,
          chapter,
        ),
      };
      expect(location.toJson(), {
        for (final MapEntry(:key, :value) in saved.entries)
          if (key != 'chapter') key: value,
      }, reason: '$book $kind $cfi');
      expect(location.chapter, saved['chapter'], reason: '$book $kind $cfi');
      expect(quoteMatches(section, place, saved['quote']! as String), isTrue);
    }
  });

  group('notes', () {
    /// The first `a` element of [section].
    DomElement link(DomSection section) => section.body.texts
        .map((text) => text.parent!)
        .firstWhere((element) => element.name == 'a');

    test('a link marked as a note reference by its epub:type or its role is '
        'a note reference, and other links are not', () {
      for (final (markup, reference) in [
        ('<a epub:type="noteref" href="#n">1</a>', true),
        ('<a epub:type="glossref noteref" href="#n">1</a>', true),
        ('<a role="doc-noteref" href="#n">1</a>', true),
        ('<a href="#n">1</a>', false),
        ('<a epub:type="backlink" href="#n">1</a>', false),
        ('<a epub:type="noterefs" href="#n">1</a>', false),
      ]) {
        expect(
          isNoteReference(link(dom('<p>Text$markup</p>'))),
          reference,
          reason: markup,
        );
      }
    });

    test('a link to a footnote, an endnote, a rearnote or a note shows that '
        'note, whatever marks the link', () {
      for (final type in ['footnote', 'endnote', 'rearnote', 'note']) {
        final section = dom(
          '<p>Text</p><aside id="n" epub:type="$type"><p>The note.</p>'
          '</aside>',
        );
        final note = section.elementById('n');
        expect(noteOf(note, reference: false), same(note), reason: type);
        expect(noteOf(note, reference: true), same(note), reason: type);
      }
      final aria = dom('<aside id="n" role="doc-endnote"><p>Aria.</p></aside>');
      expect(
        noteOf(aria.elementById('n'), reference: false),
        same(aria.elementById('n')),
      );
    });

    test('a link into a note shows the whole note that holds its target', () {
      final section = dom(
        '<ol epub:type="endnotes"><li id="note-1" epub:type="endnote">'
        '<p id="inner">The first part.</p><p>The second part.</p></li></ol>',
      );
      expect(
        noteOf(section.elementById('inner'), reference: false),
        same(section.elementById('note-1')),
      );
    });

    test(
      'a note reference to an element that is no note shows that '
      'element, and a link that is no note reference to it shows nothing',
      () {
        final section = dom('<p id="n">1. A note without a type.</p>');
        final target = section.elementById('n');
        expect(noteOf(target, reference: true), same(target));
        expect(noteOf(target, reference: false), isNull);
      },
    );

    test('a note reference to an anchor without text shows the element that '
        'holds the anchor', () {
      final section = dom(
        '<div><p><a id="n"/>The text after an empty anchor.</p></div>',
      );
      expect(
        noteOf(section.elementById('n'), reference: true),
        same(section.elementById('n')!.parent),
      );
    });

    test('a link to a section of notes, and a link without a target, show '
        'no note', () {
      final section = dom(
        '<section id="notes" epub:type="endnotes rearnotes"><p>Notes</p>'
        '</section>',
      );
      expect(noteOf(section.elementById('notes'), reference: false), isNull);
      expect(noteOf(null, reference: true), isNull);
    });
  });
}
