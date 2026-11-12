// With speech, Crossings lands a place of the other edition on the word
// that the narrator speaks there (docs/plans/cross-edition-places.md,
// "How Crossings lands a place by speech"). Matched chapters give the
// estimate while speech works, and the landing when speech refuses.
import 'dart:typed_data';

import 'package:bookfin/crossings/crossings.dart';
import 'package:bookfin/speech/book_search.dart';
import 'package:bookfin/speech/book_words.dart';
import 'package:bookfin/speech/heard_windows.dart';
import 'package:bookfin/speech/words.dart';
import 'package:flutter_test/flutter_test.dart';

import '../speech/heard_windows_test.dart'
    show FakeHearing, MemoryStore, inline;
import '../speech/place_test.dart' show zipfBook;
import 'crossings_test.dart'
    show MemoryOutlines, audio, book, ebookEdition, listening, reading;

/// The words of [book], the test outline: 1000 words of 5 characters each.
final words = BookWords(
  zipfBook(length: 1000).words,
  Int32List.fromList([for (var word = 0; word < 1000; word++) word * 5]),
  bodyEnd: 1000,
);

/// When the narrator speaks [word], in milliseconds from the recording's
/// start, or null for the front matter, which the narrator does not read.
/// The narrator reads 10 characters a second, as the chapters of [audio]
/// match the entries of [book], except that entry II starts 10 s after its
/// chapter, after a spoken heading, and so reads faster.
int? spoken(int word) {
  final characters = word * 5;
  if (characters < 1000) return null;
  if (characters < 2000) return 30000 + (characters - 1000) * 100;
  if (characters < 4000) return 140000 + (characters - 2000) * 95;
  return 330000 + (characters - 4000) * 100;
}

/// The words that the narrator speaks in the 8 s from [startMs] of the
/// file at [path]. Whisper mishears every seventh word.
Heard narrated(String path, int startMs) {
  final from = (path.endsWith('two.mp3') ? 130000 : 0) + startMs;
  final heard = <String>[], ms = <int>[];
  for (var word = 0; word < words.words.length; word++) {
    final at = spoken(word);
    if (at == null || at < from || at >= from + 8000) continue;
    heard.add(word % 7 == 3 ? 'mumble' : words.words[word]);
    ms.add(at - from);
  }
  return Heard(heard, ms);
}

/// Reads [words] in the worker of the book's words. A top-level function,
/// so that the reader captures only the words.
ReadBook readsOf(BookWords words) =>
    () async => words;

void main() {
  final two = audio.files[1];
  late FakeHearing hearing;
  late HeardWindows heard;
  late bool downloaded;
  late BookWords? readable;
  late bool broken;
  final made = <Crossings>[];

  setUp(() {
    hearing = FakeHearing()..answer = narrated;
    downloaded = true;
    readable = words;
    broken = false;
    heard = HeardWindows(
      hear: hearing.call,
      store: MemoryStore(),
      localPath: (file) async =>
          downloaded ? '/media/${file.itemId}.mp3' : null,
      hop: inline,
    );
  });
  tearDown(() {
    for (final crossings in made) {
      crossings.dispose();
    }
    made.clear();
  });

  Crossings crossings() {
    final made_ = Crossings(
      store: MemoryOutlines(),
      measure: (text) async => book,
      hop: inline,
      speech: (
        heard: heard,
        words: (text) async {
          if (broken) throw StateError('A bug in speech.');
          return switch (readable) {
            final words? => readsOf(words),
            null => null,
          };
        },
      ),
    );
    made.add(made_);
    return made_;
  }

  /// The characters before the landing of a listening place in the ebook.
  double charactersOf(Crossing found) =>
      (found as TextLanding).share * book.length;

  group('a listening place', () {
    // 100 s into disc two, 230 s into the recording: the narrator speaks
    // word 589, at 2945 characters, 225 ms before. Matched chapters
    // estimate 3000.
    final place = listening(two, 100000);

    test('lands on the word that the narrator speaks at its time', () async {
      final found = await crossings().landing(
        place,
        from: audio,
        into: ebookEdition(),
      );
      expect(found, isA<TextLanding>());
      expect((found as TextLanding).matchedBy, MatchedBy.speech);
      expect(charactersOf(found), closeTo(2945, 5));
      expect(found.from, place);
    });

    test(
      'lands between two found windows without hearing at the tap',
      () async {
        // Windows at 200 s and 260 s into the recording.
        await heard.hear(audio, listening(two, 70000));
        await heard.hear(audio, listening(two, 130000));
        hearing.calls.clear();

        final found = await crossings().landing(
          place,
          from: audio,
          into: ebookEdition(),
        );
        expect((found as TextLanding).matchedBy, MatchedBy.speech);
        expect(charactersOf(found), closeTo(2945, 10));
        expect(hearing.calls, isEmpty);
      },
    );

    test('shows the estimate of matched chapters while speech works, then '
        'the word', () async {
      hearing.gated = true;
      final crossings_ = crossings();
      Crossing? now() =>
          crossings_.landingNow(place, from: audio, into: ebookEdition());

      now();
      await pumpEventQueue();
      final refining = now();
      expect(refining, isA<Refining>());
      final estimate = (refining as Refining).estimate! as TextLanding;
      expect(estimate.matchedBy, MatchedBy.chapters);
      expect(charactersOf(estimate), closeTo(3000, 1));

      var changed = false;
      crossings_.changes.addListener(() => changed = true);
      hearing.gates.first.complete();
      // The search runs in a worker isolate, so the test waits for the
      // speech work itself, which a landing shares.
      await crossings_.landing(place, from: audio, into: ebookEdition());
      expect(changed, isTrue);
      final landed = now();
      expect((landed as TextLanding).matchedBy, MatchedBy.speech);
      expect(charactersOf(landed), closeTo(2945, 5));
    });

    test('keeps the landing of matched chapters when the book does not hold '
        'the heard words', () async {
      hearing.answer = (_, _) => Heard(
        normalizeWords('quantum zebra xylophone apparatus nebula vortex'),
        const [0, 1000, 2000, 3000, 4000, 5000],
      );
      final found = await crossings().landing(
        place,
        from: audio,
        into: ebookEdition(),
      );
      expect((found as TextLanding).matchedBy, MatchedBy.chapters);
      expect(charactersOf(found), closeTo(3000, 1));
    });

    test('of an audiobook that this phone streams keeps the landing of '
        'matched chapters', () async {
      downloaded = false;
      final found = await crossings().landing(
        place,
        from: audio,
        into: ebookEdition(),
      );
      expect((found as TextLanding).matchedBy, MatchedBy.chapters);
      expect(hearing.calls, isEmpty);
    });

    test('fails with a bug in speech, and the next landing tries speech '
        'again', () async {
      broken = true;
      final crossings_ = crossings();
      await expectLater(
        crossings_.landing(place, from: audio, into: ebookEdition()),
        throwsStateError,
      );
      broken = false;
      final found = await crossings_.landing(
        place,
        from: audio,
        into: ebookEdition(),
      );
      expect((found as TextLanding).matchedBy, MatchedBy.speech);
    });

    test('in an ebook whose words speech cannot read keeps the landing of '
        'matched chapters', () async {
      readable = null;
      final found = await crossings().landing(
        place,
        from: audio,
        into: ebookEdition(),
      );
      expect((found as TextLanding).matchedBy, MatchedBy.chapters);
    });
  });

  group('a reading place', () {
    // 30% into the second section: 3250 characters, word 650, which the
    // narrator speaks 258.75 s into the recording, 128.75 s into disc two.
    // Matched chapters estimate 125 s into disc two.
    final place = reading('OPS/b.xhtml', 0.3);

    test('lands at the time when the narrator speaks its word', () async {
      final found = await crossings().landing(
        place,
        from: ebookEdition(),
        into: audio,
      );
      expect(found, isA<AudioLanding>());
      final landing = found as AudioLanding;
      expect(landing.matchedBy, MatchedBy.speech);
      expect(landing.place.sourceKey, two.key);
      expect(landing.place.milliseconds, closeTo(128750, 500));
      expect(landing.from, place);
    });

    test('shows the estimate of the found windows around it while speech '
        'works', () async {
      // Windows at 230 s and 290 s into the recording. A landing between
      // them, without hearing, searches them for the anchor map.
      await heard.hear(audio, listening(two, 100000));
      await heard.hear(audio, listening(two, 160000));
      final crossings_ = crossings();
      await crossings_.landing(
        listening(two, 130000),
        from: audio,
        into: ebookEdition(),
      );

      hearing.gated = true;
      crossings_.landingNow(place, from: ebookEdition(), into: audio);
      final refining = crossings_.landingNow(
        place,
        from: ebookEdition(),
        into: audio,
      );
      final estimate = (refining as Refining).estimate! as AudioLanding;
      expect(estimate.place.sourceKey, two.key);
      expect(estimate.place.milliseconds, closeTo(128750, 500));
      hearing.gates.firstOrNull?.complete();
    });

    test(
      'keeps the landing of matched chapters when speech finds nothing',
      () async {
        hearing.answer = (_, _) => null;
        final found = await crossings().landing(
          place,
          from: ebookEdition(),
          into: audio,
        );
        final landing = found as AudioLanding;
        expect(landing.matchedBy, MatchedBy.chapters);
        expect(landing.place.milliseconds, closeTo(125000, 1));
      },
    );
  });
}
