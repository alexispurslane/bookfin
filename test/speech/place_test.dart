// Speech places a listening place in the ebook, and a reading place in the
// audiobook, from heard windows and a search of their words (docs/plans/
// cross-edition-places.md, "The two directions").
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bookfin/speech/book_words.dart';
import 'package:bookfin/speech/place.dart';
import 'package:bookfin/speech/search.dart';
import 'package:bookfin/speech/words.dart';
import 'package:flutter_test/flutter_test.dart';

/// A book of [length] words drawn from a vocabulary of [vocabulary] made-up
/// words, where the word of rank k comes about 1/k as often as the first,
/// as in a real book: a few common words, and a long tail of rare ones
/// that place a window.
BookWords zipfBook({int length = 30000, int vocabulary = 6000}) {
  final random = math.Random(11);
  final made = <String>{};
  while (made.length < vocabulary) {
    made.add(
      String.fromCharCodes([
        for (var letter = 0; letter < 3 + random.nextInt(6); letter++)
          0x61 + random.nextInt(26),
      ]),
    );
  }
  final ranked = made.toList();
  final words = [
    for (var word = 0; word < length; word++)
      ranked[math.pow(vocabulary, random.nextDouble()).floor() - 1],
  ];
  final offsets = Int32List(length);
  for (var word = 1; word < length; word++) {
    offsets[word] = offsets[word - 1] + words[word - 1].length + 1;
  }
  return BookWords(words, offsets, bodyEnd: length);
}

/// A narrator who reads [book] from its first word at [msPerWord], after
/// [leadMs] of credits, and who mishears every seventh word.
class Narrator {
  Narrator(this.book, {this.msPerWord = 400, this.leadMs = 0});
  final BookWords book;
  final int msPerWord;
  final int leadMs;

  /// The words heard in [lengthMs] from [startMs], with their times from
  /// the window's start.
  Heard hear(int startMs, int lengthMs) {
    final words = <String>[], ms = <int>[];
    final first = math.max(0, ((startMs - leadMs) / msPerWord).ceil());
    for (var word = first; ; word++) {
      final at = leadMs + word * msPerWord;
      if (at >= startMs + lengthMs || word >= book.words.length) break;
      words.add(word % 7 == 3 ? 'mumble' : book.words[word]);
      ms.add(at - startMs);
    }
    return Heard(words, ms);
  }

  /// When [word] is spoken.
  int timeOf(int word) => leadMs + word * msPerWord;
}

/// Runs the reading-place loop with [narrator]'s windows, centered on each
/// time that the loop asks for, as Crossings runs it with heard windows.
int? converge(
  BookWords book,
  Narrator narrator, {
  required int target,
  required int estimateMs,
  List<double> radii = nearRadii,
  double? msPerWord,
}) {
  final search = ReadingSearch(
    target: target,
    estimateMs: estimateMs,
    msPerWord: msPerWord ?? narrator.msPerWord.toDouble(),
    radii: radii,
  );
  while (!search.exhausted) {
    final start = math.max(0, search.nextMs - 4000);
    final heard = narrator.hear(start, 8000);
    final match = heard.words.isEmpty
        ? null
        : searchAround(
            book,
            heard.words,
            search.expectedWord(start),
            search.radii,
          );
    final landed = search.fold(start, heard, match);
    if (landed != null) return landed;
  }
  return null;
}

void main() {
  final book = zipfBook();

  group('a listening place in the ebook', () {
    test('lands on the book word heard at its time', () {
      final narrator = Narrator(book);
      final atMs = narrator.timeOf(5006) + 100;
      final heard = narrator.hear(atMs - 4000, 8000);
      final word = landHeard(
        book,
        heard,
        atMs: 4000,
        around: 5300,
        radii: nearRadii,
      );
      expect(word, 5006);
    });

    test('lands a place in the closing words after the book on its last '
        'word', () {
      // The narrator reads the book's last 14 words, then says 6 words of
      // the recording's own, such as "End of the book. Read by...".
      final narrator = Narrator(book);
      final last = narrator.hear(narrator.timeOf(29986), 5600);
      final closing = normalizeWords('end quantum zebra xylophone by nebula');
      final heard = Heard(
        [...last.words, ...closing],
        [...last.ms, for (var word = 0; word < 6; word++) 5600 + word * 400],
      );
      final word = landHeard(
        book,
        heard,
        atMs: 7600,
        around: 29990,
        radii: nearRadii,
      );
      expect(word, book.bodyEnd - 1);
    });

    test('refuses heard words that the book does not hold', () {
      final heard = Heard(
        normalizeWords('quantum zebra xylophone apparatus nebula vortex'),
        const [0, 300, 600, 900, 1200, 1500],
      );
      expect(
        landHeard(book, heard, atMs: 600, around: 0, radii: wholeBookRadii),
        isNull,
      );
    });
  });

  group('a reading place in the audiobook', () {
    test('converges on the time when its word is spoken', () {
      final narrator = Narrator(book, leadMs: 20000);
      final landed = converge(
        book,
        narrator,
        target: 12020,
        estimateMs: narrator.timeOf(12020) + 40000,
      )!;
      expect((landed - narrator.timeOf(12020)).abs(), lessThan(400));
    });

    test('finds the local rate of a narrator faster than the estimate', () {
      final narrator = Narrator(book, msPerWord: 300);
      final landed = converge(
        book,
        narrator,
        target: 20030,
        estimateMs: 20030 * 400,
        radii: wholeBookRadii,
        msPerWord: 400,
      )!;
      expect((landed - narrator.timeOf(20030)).abs(), lessThan(600));
    });

    test('gives up after six windows that find nothing', () {
      final search = ReadingSearch(
        target: 100,
        estimateMs: 50000,
        msPerWord: 400,
        radii: nearRadii,
      );
      var rounds = 0;
      while (!search.exhausted) {
        rounds++;
        expect(
          search.fold(search.nextMs, Heard(const [], const []), null),
          isNull,
        );
      }
      expect(rounds, 6);
    });
  });

  group('anchors of heard windows', () {
    test('place each found window at its time and its characters', () {
      final narrator = Narrator(book);
      final windows = [
        for (final word in [3000, 9000, 15000])
          (
            startMs: narrator.timeOf(word) - 4000,
            heard: narrator.hear(narrator.timeOf(word) - 4000, 8000),
            coarse: book.offsets[word].toDouble() + 3000,
          ),
      ];
      final anchors = findAnchors(book, windows);
      expect(anchors, hasLength(3));
      for (final (index, word) in [3000, 9000, 15000].indexed) {
        final anchor = anchors[index];
        // The anchor's word is spoken at the anchor's time.
        final spoken = book.wordAt(anchor.characters.toDouble());
        expect((narrator.timeOf(spoken) - anchor.ms).abs(), lessThan(800));
        expect((spoken - word).abs(), lessThan(12));
      }
    });

    test('leave out a window that the book does not hold', () {
      final narrator = Narrator(book);
      final anchors = findAnchors(book, [
        (
          startMs: 0,
          heard: Heard(
            normalizeWords('quantum zebra xylophone apparatus nebula vortex'),
            const [0, 300, 600, 900, 1200, 1500],
          ),
          coarse: 0,
        ),
        (
          startMs: narrator.timeOf(9000) - 4000,
          heard: narrator.hear(narrator.timeOf(9000) - 4000, 8000),
          coarse: book.offsets[9000].toDouble(),
        ),
      ]);
      expect(anchors, hasLength(1));
    });

    // Two anchors 40 s apart, 100 words and 500 characters apart: 400 ms
    // a word.
    const before = (ms: 60000, word: 1000, characters: 5000);
    const after = (ms: 100000, word: 1100, characters: 5500);

    test('place a time between them, and a place between them', () {
      expect(charactersBetween([before, after], 70000), 5125);
      expect(millisecondsBetween([before, after], 5125), 70000);
    });

    test('place the time and the place of one anchor', () {
      expect(charactersBetween([before, after], 60000), 5000);
      expect(millisecondsBetween([after, before], 5500), 100000);
    });

    test('do not place what lies outside them', () {
      expect(charactersBetween([before, after], 50000), isNull);
      expect(millisecondsBetween([before, after], 5600), isNull);
    });

    test('do not place what lies between two anchors more than 10 minutes '
        'apart', () {
      const later = (ms: 700000, word: 2700, characters: 13500);
      expect(charactersBetween([before, later], 70000), isNull);
      expect(millisecondsBetween([before, later], 6000), isNull);
    });

    test('do not place what lies between two anchors that no narrator reads '
        'so fast or so slowly', () {
      // 40 s for 20 words, and 40 s for 1000 words.
      const slow = (ms: 100000, word: 1020, characters: 5100);
      const fast = (ms: 100000, word: 2000, characters: 10000);
      expect(charactersBetween([before, slow], 70000), isNull);
      expect(charactersBetween([before, fast], 70000), isNull);
    });
  });
}
