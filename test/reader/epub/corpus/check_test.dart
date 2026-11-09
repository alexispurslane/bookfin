// Tool code: tests of the checks that the corpus run makes on each book.
import 'dart:typed_data';

import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../helpers.dart';
import 'book.dart';
import 'check.dart';

/// A book whose section [broken] cannot be read.
class _BrokenBook extends CorpusBook {
  _BrokenBook(Uint8List bytes, this.broken)
    : super(CorpusBook.open(bytes).publication);
  final int broken;

  @override
  SectionSource source(int index) =>
      index == broken ? throw StateError('unreadable') : super.source(index);
}

/// A clock that moves on by [step] each time that it is read.
Duration Function() _ticking(Duration step) {
  var now = Duration.zero;
  return () => now += step;
}

Future<CorpusBook> Function() _made(Uint8List bytes) =>
    () async => CorpusBook.open(bytes);

void main() {
  setUpAll(loadReaderFont);

  test('a showcase book passes every check at both page settings', () async {
    final report = await checkBook(
      'showcase-frost',
      _made(showcaseBooks()['showcase-frost']!),
    );
    expect(report.exceptions, isEmpty);
    expect(report.passed, isTrue);
    expect(report.settings.map((each) => each.settings), corpusSettings);
    for (final each in report.settings) {
      expect(each.pageStarts, greaterThan(1));
      expect(each.samePage, each.pageStarts);
      expect(each.runs, greaterThan(0));
      expect(each.drawMs, isNotEmpty);
      expect(each.layoutMsPer10k, greaterThan(0));
    }
  });

  test('a run starts from every page start of a short section', () async {
    final report = await checkBook(
      'short',
      _made(madeUpEpub(['<p>${prose(60)}</p>'])),
      settings: [readerPage],
    );
    final found = report.settings.single;
    expect(found.pages, greaterThan(2));
    expect(found.runs, found.pages - 1);
  });

  test('a page that shows only the border of an empty block after an '
      'overflowing page is not blank, as Chromium shows it too', () async {
    final report = await checkBook(
      'border',
      _made(
        madeUpEpub([
          '<p style="line-height:700px">Tall</p>'
              '<div style="border-top:2px solid"></div>',
        ]),
      ),
    );
    expect(report.exceptions, isEmpty);
    for (final each in report.settings) {
      expect(each.pages, 2);
      expect(each.blankPages, isEmpty);
    }
  });

  test('a page that shows only an image is not blank', () async {
    final tall = img.encodePng(img.Image(width: 100, height: 1000));
    final report = await checkBook(
      'image',
      _made(
        madeUpEpub(
          ['<p>Before.</p><div><img src="tall.png" alt=""/></div><p>After.</p>'],
          images: {'tall.png': tall},
        ),
      ),
    );
    expect(report.exceptions, isEmpty);
    for (final each in report.settings) {
      expect(each.pages, greaterThanOrEqualTo(2));
      expect(each.blankPages, isEmpty);
    }
  });

  test('a smaller page with larger text cuts more pages', () async {
    final report = await checkBook(
      'showcase-frost',
      _made(showcaseBooks()['showcase-frost']!),
    );
    expect(report.settings[1].pages, greaterThan(report.settings[0].pages));
  });

  test(
    'a book that admission refuses is one exception and no layout',
    () async {
      final report = await checkBook(
        'broken',
        () async => CorpusBook.open(Uint8List.fromList([1, 2, 3])),
      );
      expect(report.exceptions.single.check, 'admit');
      expect(report.settings, isEmpty);
      expect(report.passed, isFalse);
    },
  );

  test('an exception in one section names the section and the page settings, '
      'and the other sections are still checked', () async {
    final bytes = madeUpEpub([
      '<p>${prose(3, 'First')}</p>',
      '<p>${prose(3, 'Second')}</p>',
      '<p>${prose(3, 'Third')}</p>',
    ]);
    final report = await checkBook('broken', () async => _BrokenBook(bytes, 1));
    expect(
      [
        for (final caught in report.exceptions)
          (caught.check, caught.section, caught.settings),
      ],
      [
        // The support report reads every section too.
        ('support', null, null),
        for (final settings in corpusSettings) ('prepare', 1, settings),
      ],
    );
    for (final each in report.settings) {
      expect(each.pageStarts, greaterThanOrEqualTo(2));
      expect(each.samePage, each.pageStarts);
    }
  });

  test('a paragraph whose layout takes longer than the threshold is listed '
      'with its section and its text', () async {
    final report = await checkBook(
      'slow',
      _made(madeUpEpub(['<p>One slow paragraph.</p>', '<p>Another.</p>'])),
      settings: [readerPage],
      clock: _ticking(const Duration(milliseconds: 9)),
    );
    expect(
      [
        for (final item in report.settings.single.slow)
          (item.section, item.kind, item.text),
      ],
      [(0, 'paragraph', 'One slow paragraph.'), (1, 'paragraph', 'Another.')],
    );
  });

  test('a slow paragraph lists its text without the soft hyphens of '
      'hyphenation', () async {
    final report = await checkBook(
      'hyphens',
      _made(
        madeUpEpub([
          '<p lang="en">Extraordinarily incomprehensible characteristics.</p>',
        ], css: 'p{hyphens:auto}'),
      ),
      settings: [readerPage],
      clock: _ticking(const Duration(milliseconds: 9)),
    );
    expect(
      report.settings.single.slow.single.text,
      'Extraordinarily incomprehensible characteristics.',
    );
  });

  test('a paragraph within the threshold is not listed', () async {
    final report = await checkBook(
      'fast',
      _made(madeUpEpub(['<p>One fast paragraph.</p>'])),
      settings: [readerPage],
      clock: _ticking(const Duration(milliseconds: 8)),
    );
    expect(report.settings.single.slow, isEmpty);
  });

  test('a slow table is listed with the text of its first cell', () async {
    final report = await checkBook(
      'table',
      _made(
        madeUpEpub([
          '<table><tr><td>Name</td><td>Price</td></tr>'
              '<tr><td>Bread</td><td>2</td></tr></table>',
        ]),
      ),
      settings: [readerPage],
      clock: _ticking(const Duration(milliseconds: 9)),
    );
    expect(
      report.settings.single.slow.map((item) => (item.kind, item.text)),
      contains(('table', 'Name')),
    );
  });

  test(
    'the approximations of the support report are listed by section',
    () async {
      final report = await checkBook(
        'float',
        _made(
          madeUpEpub([
            '<p>Plain.</p>',
            '<p class="aside">Floated.</p>',
          ], css: '.aside{float:right}'),
        ),
        settings: [readerPage],
      );
      expect(report.toJson()['approximations'], {
        'float drawn as a block': [1],
      });
    },
  );
}
