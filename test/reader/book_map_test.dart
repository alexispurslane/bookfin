import 'dart:async';
import 'dart:convert';

import 'package:bookfin/reader/book_map.dart';
import 'package:bookfin/reader/document.dart';
import 'package:flutter_epub_viewer/navigation.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_test/flutter_test.dart';

import 'publication_test.dart' show epub;

/// Three sections: "one" with one chapter, "two" with a second chapter
/// that starts half way through its text, and "three". Its navigation
/// document lists [contents], so the reader lists them too.
Publication threeSections({String? two}) => Publication.admit(
  epub(
    extra: {
      'OPS/book.opf': utf8.encode(
        '<package version="3.0"><metadata/><manifest>'
        '<item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="two" href="two.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="three" href="three.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
        'properties="nav"/>'
        '</manifest><spine><itemref idref="one"/><itemref idref="two"/>'
        '<itemref idref="three"/></spine></package>',
      ),
      'OPS/one.xhtml': utf8.encode(
        section('<h1 id="one">One</h1><p>${'o' * 200}</p>'),
      ),
      // 96 letters come before the heading "Half", and 96 from it on.
      'OPS/two.xhtml': utf8.encode(
        two ??
            section(
              '<h1 id="two">Two</h1>\n  <p>${'a' * 93}</p>\n'
              '  <h2 id="half">Half</h2>\n  <p>${'b ' * 92}</p>',
            ),
      ),
      'OPS/three.xhtml': utf8.encode(section('<p>${'t' * 600}</p>')),
      'OPS/nav.xhtml': utf8.encode(navigation(contents)),
    },
  ),
);

String section(String body) =>
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Part</title></head>'
    '<body>\n  $body\n</body></html>';

/// A navigation document whose toc lists [entries], nested by depth.
String navigation(List<ContentsEntry> entries) {
  final items = StringBuffer();
  var depth = 0;
  for (final (index, entry) in entries.indexed) {
    if (index > 0) {
      if (entry.depth > depth) {
        items.write('<ol>');
      } else {
        items.write('</li>');
        for (; depth > entry.depth; depth--) {
          items.write('</ol></li>');
        }
      }
    }
    depth = entry.depth;
    items.write('<li><a href="${entry.href}">${entry.title}</a>');
  }
  items.write('</li>');
  for (; depth > 0; depth--) {
    items.write('</ol></li>');
  }
  return '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents'
      '</title></head><body><nav epub:type="toc"><ol>$items</ol></nav>'
      '</body></html>';
}

const contents = [
  ContentsEntry('One', 'one.xhtml'),
  ContentsEntry('Two', 'two.xhtml#two'),
  ContentsEntry('Half', 'two.xhtml#half', depth: 1),
  ContentsEntry('Three', 'three.xhtml'),
  ContentsEntry('Notes', 'notes.xhtml'),
];

/// Runs the work in this isolate, and counts the hops.
class InlineHop {
  var hops = 0;
  Future<R> call<M, R>(FutureOr<R> Function(M) work, M input) async {
    hops++;
    return work(input);
  }
}

EpubAddress place(String resource, {double? progress}) => EpubAddress(
  ReadingLocation('epubcfi(/6/2!/4/2/1:0)', resource, '', progress: progress),
);

void main() {
  final publication = threeSections();
  int size(String resource) => publication.resources[resource]!.length;
  final whole =
      size('OPS/one.xhtml') + size('OPS/two.xhtml') + size('OPS/three.xhtml');

  /// Where a place [progress] of the way through "two" sits in the book.
  double inTwo(double progress) =>
      (size('OPS/one.xhtml') + size('OPS/two.xhtml') * progress) / whole;

  Future<BookMap> map() async => (await BookMap.of(
    EpubDocument(publication),
    contents,
    hop: InlineHop().call,
  ))!;

  test('an EPUB place sits after the sections before it, at its progress '
      'through its own section', () async {
    final book = await map();
    expect(book.fractionOf(place('OPS/one.xhtml', progress: 0)), 0);
    expect(
      book.fractionOf(place('OPS/two.xhtml', progress: .5)),
      closeTo(inTwo(.5), 1e-9),
    );
    expect(
      book.fractionOf(place('OPS/three.xhtml', progress: 1)),
      closeTo(1, 1e-9),
    );
  });

  test('an EPUB place saved without its progress sits at the start of its '
      'section', () async {
    final book = await map();
    expect(book.fractionOf(place('OPS/two.xhtml')), closeTo(inTwo(0), 1e-9));
  });

  test('a part and a progress through it sit where the bar would put them, '
      'in an EPUB and a PDF', () async {
    final book = await map();
    expect(book.fractionAt((part: 1, progress: .5)), closeTo(inTwo(.5), 1e-9));
    for (final fraction in [0.0, .3, inTwo(.25), .99]) {
      final target = book.targetAt(fraction);
      expect(
        book.fractionAt((part: target.part, progress: target.progress)),
        closeTo(fraction, 1e-9),
      );
    }
    expect(BookMap.pages(4).fractionAt((part: 2, progress: .5)), .625);
    expect(BookMap.pages(4).fractionAt((part: 9, progress: 0)), 1);
  });

  test('a PDF place counts its shown source page as read, so the last '
      'page fills the bar', () {
    final book = BookMap.pages(4);
    expect(book.fractionOf(PdfAddress(1, 0)), .25);
    expect(book.fractionOf(PdfAddress(3, 40)), .75);
    expect(book.fractionOf(PdfAddress(4, 0)), 1);
  });

  test('chapters start where the contents point, also inside a section, '
      'and entries outside the reading order mark nothing', () async {
    final book = await map();
    expect(book.chapters.map((chapter) => chapter.title), [
      'One',
      'Two',
      'Half',
      'Three',
    ]);
    final starts = [for (final chapter in book.chapters) chapter.start];
    expect(starts[0], 0);
    expect(starts[1], closeTo(inTwo(0), 1e-9));
    expect(starts[2], closeTo(inTwo(.5), 1e-9));
    expect(starts[3], closeTo(inTwo(1), 1e-9));
  });

  test(
    'a contents entry whose fragment is missing starts at its section',
    () async {
      final book = await BookMap.of(EpubDocument(publication), const [
        ContentsEntry('Lost', 'two.xhtml#nowhere'),
      ], hop: InlineHop().call);
      expect(book!.chapters.single.start, closeTo(inTwo(0), 1e-9));
    },
  );

  test('a fraction of an EPUB names its section, the progress through it '
      'and the chapter there', () async {
    final book = await map();
    final late = book.targetAt(inTwo(.75));
    expect(late.part, 1);
    expect(late.progress, closeTo(.75, 1e-9));
    expect(late.chapter, 'Half');
    expect(late.fraction, closeTo(inTwo(.75), 1e-9));
    expect(book.targetAt(inTwo(.25)).chapter, 'Two');
    expect(book.targetAt(0).chapter, 'One');
  });

  test('a fraction of a PDF names its source page and no chapter', () {
    final book = BookMap.pages(4);
    final target = book.targetAt(.6);
    expect(target.part, 2, reason: 'The third source page holds 0.5 to 0.75.');
    expect(target.progress, closeTo(.4, 1e-9));
    expect(target.chapter, isNull);
    expect(book.pages, 4);
  });

  test('the end of the book is the end of its last part', () async {
    final book = await map();
    final end = book.targetAt(1);
    expect((end.part, end.progress, end.chapter), (2, 1.0, 'Three'));
    expect(BookMap.pages(4).targetAt(1).part, 3);
    expect(book.targetAt(-.5).fraction, 0);
    expect(book.targetAt(1.5).fraction, 1);
  });

  test('a large section measures its chapters in another isolate', () async {
    final hop = InlineHop();
    final large = threeSections(
      two: section('<h1 id="two">Two</h1><p>${'a' * (80 << 10)}</p>'),
    );
    await BookMap.of(EpubDocument(large), contents, hop: hop.call);
    expect(hop.hops, 1);
    final small = InlineHop();
    await BookMap.of(EpubDocument(publication), contents, hop: small.call);
    expect(small.hops, 0, reason: 'A small book costs less than the hop.');
  });

  test('a saved EPUB place keeps its progress, so a bookmark knows where it '
      'sits in the book', () async {
    final document = EpubDocument(publication);
    final reported = EpubAddress(
      ReadingLocation.fromJson({
        'cfi': 'epubcfi(/6/4!/4/2/1:0)',
        'resource': 'OPS/two.xhtml',
        'quote': '',
        'progress': .5,
      }),
    );
    final restored = document.restore(
      jsonDecode(jsonEncode(document.save(reported))) as Map<String, dynamic>,
    )!;
    expect((await map()).fractionOf(restored), closeTo(inTwo(.5), 1e-9));
  });

  group('the chapter arrows', () {
    /// A shown page of "two" from [start] to [end] through its text.
    EpubAddress page(double start, {double? end}) => EpubAddress(
      ReadingLocation(
        'epubcfi(/6/4!/4/2/1:0)',
        'OPS/two.xhtml',
        '',
        progress: start,
        end: end,
      ),
    );

    test('next chapter skips a chapter that starts in the middle of the '
        'shown page', () async {
      final book = await map();
      expect(
        book.chapterStep(page(.25, end: .75), forward: true),
        closeTo(inTwo(1), 1e-9),
        reason: '"Half" starts on the shown page, so next goes to "Three".',
      );
    });

    test('next chapter skips a chapter whose first character is the last '
        'one of the shown page', () async {
      final book = await map();
      expect(
        book.chapterStep(page(.25, end: .5), forward: true),
        closeTo(inTwo(1), 1e-9),
      );
    });

    test('next chapter goes to a chapter that starts just after the shown '
        'page', () async {
      final book = await map();
      expect(
        book.chapterStep(page(.25, end: .49), forward: true),
        closeTo(inTwo(.5), 1e-9),
      );
    });

    test('next chapter steps from the start of a page whose end is not '
        'known, such as a place that epub.js reported', () async {
      final book = await map();
      expect(
        book.chapterStep(page(.25), forward: true),
        closeTo(inTwo(.5), 1e-9),
      );
    });

    test('previous chapter steps from the start of the shown page, not its '
        'end', () async {
      final book = await map();
      expect(
        book.chapterStep(page(.25, end: .75), forward: false),
        closeTo(inTwo(0), 1e-9),
        reason: 'The page starts in "Two", before "Half".',
      );
      expect(
        book.chapterStep(page(.5, end: .75), forward: false),
        closeTo(inTwo(0), 1e-9),
        reason: 'At the start of "Half", back goes to the chapter before.',
      );
    });

    test('a shown page outside the book has no chapter step', () async {
      final book = await map();
      final elsewhere = EpubAddress(
        ReadingLocation('epubcfi(/6/2!/4/2/1:0)', 'OPS/notes.xhtml', ''),
      );
      expect(book.chapterStep(elsewhere, forward: true), isNull);
      expect(book.chapterStep(elsewhere, forward: false), isNull);
    });
  });

  test('a reported progress outside the section is not a place', () {
    for (final progress in [-.1, 1.1, 'half']) {
      expect(
        () => ReadingLocation.fromJson({
          'cfi': 'epubcfi(/6/4!/4/2/1:0)',
          'resource': 'OPS/two.xhtml',
          'quote': '',
          'progress': progress,
        }),
        throwsFormatException,
      );
    }
  });
}
