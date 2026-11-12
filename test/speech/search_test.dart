import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bookfin/speech/book_words.dart';
import 'package:bookfin/speech/search.dart';
import 'package:bookfin/speech/words.dart';
import 'package:flutter_test/flutter_test.dart';

const _common = [
  'the', 'of', 'and', 'to', 'a', 'in', 'that', 'he', 'was', 'it', 'his', //
  'her', 'with', 'as', 'had', 'for', 'she', 'not', 'at', 'but', 'on', 'him',
  'you', 'be', 'all', 'by', 'which', 'they', 'said', 'from', 'this', 'so',
  'were', 'have', 'one', 'my', 'what', 'there', 'would', 'me', 'no', 'when',
  'an', 'if', 'been', 'their', 'out', 'up', 'could', 'more', 'some', 'into',
  'them', 'very', 'then', 'man', 'time', 'little', 'about', 'than', 'like',
  'over', 'only', 'must', 'upon', 'house', 'door', 'night', 'great', 'old',
  'came', 'went', 'long', 'own', 'hand', 'eyes', 'face', 'room', 'never',
];

const passage =
    'alice was beginning to get very tired of sitting by her sister on the '
    'bank and of having nothing to do';

/// A book of [length] common words in a seeded random order, with [inserts]
/// written at their word indices, and back matter from [bodyEnd] on. Each
/// word takes its letters as visible characters.
BookWords syntheticBook({
  int length = 30000,
  Map<int, String> inserts = const {},
  int? bodyEnd,
}) {
  final random = math.Random(7);
  final words = <String>[];
  while (words.length < length) {
    final at = words.length;
    if (inserts[at] case final text?) {
      words.addAll(normalizeWords(text));
      continue;
    }
    // A Zipf-like draw: early words of the list are much more frequent.
    final index = (math.pow(random.nextDouble(), 2.2) * _common.length).floor();
    words.add(_common[index]);
  }
  final offsets = Int32List(words.length);
  for (var index = 1; index < words.length; index++) {
    offsets[index] = offsets[index - 1] + words[index - 1].length;
  }
  return BookWords(words, offsets, bodyEnd: bodyEnd ?? words.length);
}

void main() {
  test('finds heard words at their place though whisper mishears a few', () {
    final book = syntheticBook(inserts: {12000: passage});
    // Two words misheard and one left out.
    final heard = normalizeWords(
      'alice was beginning to get vary tired of sitting buy her sister on '
      'the bank and having nothing to do',
    );
    final match = searchAround(book, heard, 0, const [double.infinity])!;
    expect(match.confident, isTrue);
    expect(match.pairs.first.$2, 12000);
    expect(match.bookWordOf(heard.indexOf('sister')), 12011);
  });

  test('refuses a passage that the book holds twice alike', () {
    final book = syntheticBook(inserts: {5000: passage, 20000: passage});
    final match = searchAround(book, normalizeWords(passage), 0, const [
      double.infinity,
    ]);
    expect(match?.confident, isNot(isTrue));
  });

  test('never trusts fewer than six matched words', () {
    final book = syntheticBook(inserts: {12000: passage});
    final match = searchAround(
      book,
      normalizeWords('alice was beginning to get'),
      12000,
      const [double.infinity],
    );
    expect(match?.confident, isNot(isTrue));
  });

  test("a narrator's spelling of a long word matches the book's", () {
    final book = syntheticBook(
      inserts: {
        9000:
            'mister jones painted the colour of his neighbour and honour was '
            'gained by careful labour',
      },
    );
    final heard = normalizeWords(
      'mister jones painted the color of his neighbor and honor was gained '
      'by careful labor',
    );
    final match = searchAround(book, heard, 9000, const [3])!;
    expect(match.confident, isTrue);
    // color, neighbor, honor and labor.
    expect(match.pairs.map((pair) => pair.$1), containsAll([4, 7, 9, 14]));
  });

  test('the estimate decides between two copies of a passage', () {
    final book = syntheticBook(inserts: {5000: passage, 20000: passage});
    final match = searchAround(book, normalizeWords(passage), 20030, const [
      3,
      24,
      double.infinity,
    ])!;
    expect(match.confident, isTrue);
    expect(match.pairs.first.$2, 20000);
  });

  test('a search far from the place widens until the place is clear', () {
    final book = syntheticBook(inserts: {25000: passage});
    final match = searchAround(
      book,
      normalizeWords(passage),
      1000,
      wholeBookRadii,
    )!;
    expect(match.confident, isTrue);
    expect(match.pairs.first.$2, 25000);
  });

  test('the back matter is never searched', () {
    final book = syntheticBook(inserts: {28000: passage}, bodyEnd: 27000);
    final match = searchAround(
      book,
      normalizeWords(passage),
      28000,
      wholeBookRadii,
    );
    expect(match?.confident, isNot(isTrue));
  });

  test('words that the book lacks find nothing', () {
    final book = syntheticBook();
    expect(
      searchAround(
        book,
        normalizeWords('quantum zebra xylophone'),
        0,
        wholeBookRadii,
      ),
      isNull,
    );
  });
}
