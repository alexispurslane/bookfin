import 'dart:convert';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/records.dart';
import 'package:bookfin/reader/book_map.dart';
import 'package:bookfin/reader/book_pages.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/place_words.dart';
import 'package:flutter_test/flutter_test.dart';

import 'book_map_test.dart' show InlineHop, contents, threeSections;

// A reading place in words, by the rules of docs/plans/reading-history.md,
// "A reading place in words": the short place of a timeline row, the
// chapter and the quote of its detail line, and how far along the book it
// is, so that a move can say how far it went.

/// A saved place in [edition] whose anchor is [anchor].
TextPosition saved(Map<String, Object?> anchor, {String edition = 'epub'}) =>
    TextPosition(
      editionId: edition,
      sourceKey: 'file',
      revision: 'one',
      anchor: jsonEncode(anchor),
    );

/// The address of a place [progress] of the way through [resource].
EpubAddress inBook(String resource, double progress, {String quote = ''}) =>
    EpubAddress(
      ReadingLocation(
        'epubcfi(/6/4!/4/2/1:0)',
        resource,
        quote,
        progress: progress,
      ),
    );

void main() {
  const quote =
      'It was a bright cold day in April, and the clocks were striking '
      'thirteen.';
  final epubPlace = saved({
    'cfi': 'epubcfi(/6/4!/4/2/1:0)',
    'resource': 'OPS/two.xhtml',
    'quote': quote,
  });

  Future<BookMap> map() async => (await BookMap.of(
    EpubDocument(threeSections()),
    contents,
    hop: InlineHop().call,
  ))!;

  /// One laid-out section of [pages] pages of 100 visible characters.
  PartPages laid(int pages) => (
    count: pages,
    visible: (
      starts: [for (var page = 0; page < pages; page++) page * 100],
      length: pages * 100,
    ),
  );

  test('a place in the open book reads as its page once every page is '
      'known, with its chapter and its quote', () async {
    final book = (await map()).paged(BookPages([laid(2), laid(4), laid(2)]));

    final words = describeTextPlace(
      epubPlace,
      address: inBook('OPS/two.xhtml', .75, quote: quote),
      map: book,
    );

    // "two" holds pages 3 to 6, and three quarters through it is page 6.
    expect(words.short, 'p. 6');
    expect(words.chapter, 'Half');
    expect(words.quote, quote);
  });

  test('before every page is known, a place in the open book reads as its '
      'share of the book', () async {
    final book = (await map()).paged(BookPages([laid(2), null, null]));
    final address = inBook('OPS/two.xhtml', .25);

    final words = describeTextPlace(epubPlace, address: address, map: book);

    expect(words.short, '${(book.fractionOf(address)! * 100).round()}%');
    expect(words.chapter, 'Two');
  });

  test('a PDF place reads as its source page in any edition', () {
    final words = describeTextPlace(
      saved({'page': 12, 'character': 40, 'quote': 'Figure 3'}, edition: 'pdf'),
    );

    expect(words.short, 'p. 12');
    expect(words.chapter, isNull);
    expect(words.quote, 'Figure 3');
  });

  test('an EPUB place outside the open edition reads as the first words of '
      'its quote', () {
    final words = describeTextPlace(epubPlace);

    expect(words.short, '“It was a bright cold day…”');
    expect(words.chapter, isNull);
    expect(words.quote, quote);
  });

  test('a short quote reads whole, and white space in it reads as one '
      'space. It gives no separate quote, which would only repeat it', () {
    final words = describeTextPlace(
      saved({
        'cfi': 'epubcfi(/6/2)',
        'resource': 'a',
        'quote': ' Call\n me  Ishmael. ',
      }),
    );

    expect(words.short, '“Call me Ishmael.”');
    expect(words.quote, isNull);
  });

  test('a place without a quote outside the open edition still reads as '
      'something', () {
    final words = describeTextPlace(
      saved({'cfi': 'epubcfi(/6/2)', 'resource': 'a', 'quote': ''}),
    );

    expect(words.short, isNotEmpty);
    expect(words.quote, isNull);
  });

  test('how far along the book a place is follows what the open book '
      'knows', () async {
    final known = (await map()).paged(BookPages([laid(2), laid(4), laid(2)]));
    final unknown = (await map()).paged(BookPages([null, null, null]));
    final address = inBook('OPS/two.xhtml', .75);

    final paged = describeTextPlace(epubPlace, address: address, map: known);
    final shared = describeTextPlace(epubPlace, address: address, map: unknown);
    final pdf = describeTextPlace(
      saved({'page': 12, 'character': 0, 'quote': ''}),
    );
    final elsewhere = describeTextPlace(epubPlace);

    expect(paged.along, isA<AlongText>().having((at) => at.page, 'page', 6));
    expect(
      shared.along,
      isA<AlongText>()
          .having((at) => at.page, 'page', isNull)
          .having((at) => at.fraction, 'fraction', unknown.fractionOf(address)),
    );
    expect(pdf.along, isA<AlongText>().having((at) => at.page, 'page', 12));
    expect(elsewhere.along, isNull);
  });
}
