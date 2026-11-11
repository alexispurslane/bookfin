// The alignment of an audio edition with an ebook edition by matched
// chapters: design A of docs/plans/cross-edition-places.md. The matcher
// pairs audio chapter starts with contents entry starts (anchors), and
// places a time or a text place at the same share of the span between two
// anchors. The real fixtures hold LibriVox section lists and the text
// outlines of public-domain EPUB editions, the data that the design
// measured.
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/crossings/alignment.dart';
import 'package:bookfin/playback/audio_outline.dart';
import 'package:bookfin/reader/text_outline.dart';
import 'package:flutter_test/flutter_test.dart';

/// The audio outline of a one-file recording of [length] milliseconds with
/// [chapters], each a title and its start in milliseconds.
AudioOutline recording(List<(String, int)> chapters, int length) =>
    audioOutline(
      Edition(
        id: 'recording',
        kind: EditionKind.audio,
        label: 'Narrator',
        files: [
          SourceFile(
            itemId: 'audio',
            displayName: 'Recording',
            mediaSourceId: 'm',
            revision: 'r',
            durationMs: length,
            container: 'm4b',
            sizeBytes: 1,
            chapters: [
              for (final (title, start) in chapters) AudioChapter(title, start),
            ],
          ),
        ],
        memberIds: const ['audio:m'],
      ),
    );

/// The text outline of a one-part book of [length] visible characters with
/// [entries], each a title, a depth and a start.
TextOutline ebook(List<(String, int, int)> entries, int length) => TextOutline(
  parts: [(path: 'book.xhtml', characters: length)],
  entries: [
    for (final (title, depth, start) in entries)
      (title: title, depth: depth, start: start),
  ],
);

/// The ebook outline and the LibriVox recording [id] of fixture [work].
(AudioOutline, TextOutline) fixture(String work, String id) {
  final value = jsonDecode(
    File('test/crossings/fixtures/$work.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final audio = value['recordings'][id] as Map<String, dynamic>;
  return (
    recording([
      for (final chapter in audio['chapters'] as List)
        (chapter[0] as String, chapter[1] as int),
    ], audio['length'] as int),
    TextOutline.fromJson(value['text'] as Map<String, dynamic>),
  );
}

/// The alignment of [audio] and [text], which must match chapters, after a
/// check of its invariants.
MatchedChapters matched(AudioOutline audio, TextOutline text) {
  final alignment = alignEditions(audio, text);
  expect(alignment, isA<MatchedChapters>());
  return (alignment as MatchedChapters)..checkInvariants();
}

/// The title of the contents entry of [text] that [alignment] pairs with
/// each audio chapter of [audio], by the chapter's title.
Map<String, String> pairs(
  MatchedChapters alignment,
  AudioOutline audio,
  TextOutline text,
) => {
  for (final anchor in alignment.anchors)
    audio.chapters
        .firstWhere(
          (chapter) => chapter.editionMilliseconds == anchor.milliseconds,
        )
        .name: text.entries
        .firstWhere((entry) => entry.start == anchor.characters)
        .title,
};

/// A recording with 30 s of opening credits and three chapters, and a book
/// with 1000 characters of front matter and three chapters. Every chapter
/// reads at 10 characters a second.
final steadyAudio = recording([
  ('Opening Credits', 0),
  ('Chapter 1', 30000),
  ('Chapter 2', 130000),
  ('Chapter 3', 330000),
], 430000);
final steadyText = ebook([
  ('Title page', 0, 0),
  ('I', 0, 1000),
  ('II', 0, 2000),
  ('III', 0, 4000),
], 5000);

void main() {
  group('a chapter title', () {
    test('gives the number after "chapter", "stave" or "letter"', () {
      expect(readTitle('Chapter 1, Part 2').number, (1, 1));
      expect(readTitle('Volume 2, Chapter 3').number, (3, 3));
      expect(readTitle('Stave I: Marley\'s Ghost').number, (1, 1));
    });

    test('without such a word, gives its last number', () {
      expect(readTitle('01 - Loomings').number, (1, 1));
      expect(readTitle('Book 2, Part 3').number, (3, 3));
    });

    test('reads Roman numerals and number words', () {
      expect(readTitle('CHAPTER XIX.').number, (19, 19));
      expect(readTitle('STAVE ONE.').number, (1, 1));
      expect(readTitle('XLII').number, (42, 42));
      expect(readTitle('Chapter Twenty-One').number, (21, 21));
    });

    test('reads a range of chapters as a range', () {
      expect(readTitle('Chapters 1-3').number, (1, 3));
      expect(readTitle('Chapters 1 & 2').number, (1, 2));
    });

    test('keeps its content words without stop words', () {
      expect(readTitle('Down the Rabbit-Hole').words, {
        'down',
        'rabbit',
        'hole',
      });
      expect(
        readTitle('Marley’s Ghost').words,
        readTitle("Marley's Ghost").words,
      );
    });
  });

  test('chapters pair with contents entries by number, in order', () {
    final alignment = matched(steadyAudio, steadyText);

    expect(pairs(alignment, steadyAudio, steadyText), {
      'Chapter 1': 'I',
      'Chapter 2': 'II',
      'Chapter 3': 'III',
    });
  });

  test('a recording with chapter titles in words pairs with the entries of '
      'the same words, not with illustrations of the same name', () {
    final (audio, text) = fixture('christmas-carol', '6014');

    final alignment = matched(audio, text);

    expect(pairs(alignment, audio, text), {
      "Marley's Ghost": 'MARLEY’S GHOST.',
      'The First of the Three Spirits': 'THE FIRST OF THE THREE SPIRITS.',
      'The Second of the Three Spirits': 'THE SECOND OF THE THREE SPIRITS.',
      'The Last of the Spirits': 'THE LAST OF THE SPIRITS.',
      'The End of It': 'THE END OF IT.',
    });
  });

  test('a recording of numbered chapters with titles pairs every chapter '
      'of the novel', () {
    final (audio, text) = fixture('moby-dick', '21919');

    final alignment = matched(audio, text);
    final found = pairs(alignment, audio, text);

    expect(found['1: Loomings'], 'I: Loomings');
    expect(found['10: A bosom friend'], 'X: A Bosom Friend');
    expect(found.length, greaterThanOrEqualTo(135));
  });

  test('ranges of chapters pair with the first chapter of their range', () {
    final (audio, text) = fixture('pride-and-prejudice', '253');

    final found = pairs(matched(audio, text), audio, text);

    expect(found['Chapters 1-3'], 'I');
    expect(found['Chapters 4-5'], 'IV');
    expect(found['Chapter 6'], 'VI');
  });

  test('chapters numbered inside volumes pair in order with chapters '
      'numbered through the book', () {
    final (audio, text) = fixture('emma', '1936');

    final found = pairs(matched(audio, text), audio, text);

    expect(found['Volume 1, Chapter 18'], 'XVIII');
    expect(found['Volume 2, Chapter 01'], 'XIX');
    expect(found['Volume 3, Chapter 19'], 'LV');
  });

  test('a chapter mark whose spans read at an implausible rate loses its '
      'anchor, and its neighbors keep theirs', () {
    // The mark of chapter 3 sits 10 s after chapter 2, so the span before
    // it reads at 100 characters a second against 10 for the others.
    final audio = recording([
      ('Chapter 1', 0),
      ('Chapter 2', 100000),
      ('Chapter 3', 110000),
      ('Chapter 4', 300000),
      ('Chapter 5', 400000),
    ], 500000);
    final text = ebook([
      ('1', 0, 0),
      ('2', 0, 1000),
      ('3', 0, 2000),
      ('4', 0, 3000),
      ('5', 0, 4000),
    ], 5000);

    final found = pairs(matched(audio, text), audio, text);

    expect(found.keys, ['Chapter 1', 'Chapter 2', 'Chapter 4', 'Chapter 5']);
  });

  group('no landing exists', () {
    test('when the recording numbers parts where the ebook names chapters', () {
      final (audio, text) = fixture('walden', '549');

      expect(
        alignEditions(audio, text),
        isA<UnmatchedChapters>().having(
          (alignment) => alignment.reason,
          'reason',
          Refusal.fewMatches,
        ),
      );
    });

    test('when the recording is a stage adaptation in acts', () {
      final (audio, text) = fixture('pride-and-prejudice', '6415');

      expect(
        (alignEditions(audio, text) as UnmatchedChapters).reason,
        Refusal.fewMatches,
      );
    });

    test('when the recording has no chapter marks', () {
      final audio = recording(const [], 3600000);

      expect(
        (alignEditions(audio, steadyText) as UnmatchedChapters).reason,
        Refusal.noChapters,
      );
    });

    test('when the matched chapters cover less than half of the '
        'recording', () {
      // Only chapters 1 to 3 pair. Chapters 4 to 9 have no counterpart.
      final audio = recording([
        for (var chapter = 1; chapter <= 9; chapter++)
          ('Chapter $chapter', (chapter - 1) * 100000),
      ], 900000);
      final text = ebook([
        ('I', 0, 0),
        ('II', 0, 1000),
        ('III', 0, 2000),
      ], 3000);

      expect(
        (alignEditions(audio, text) as UnmatchedChapters).reason,
        Refusal.partCovered,
      );
    });
  });

  group('placement', () {
    test('a time inside a span lands at the same share of its characters', () {
      final alignment = matched(steadyAudio, steadyText);

      // A quarter of the way through chapter 2: 50 s of 200 s.
      expect(alignment.charactersAt(180000), 2500);
    });

    test('a text place inside a span lands at the same share of its time', () {
      final alignment = matched(steadyAudio, steadyText);

      expect(alignment.millisecondsAt(2500), 180000);
    });

    test('a place in the last matched chapter lands inside that chapter', () {
      final alignment = matched(steadyAudio, steadyText);

      expect(alignment.charactersAt(380000), 4500);
      expect(alignment.millisecondsAt(4500), 380000);
    });

    test('a place at most one page outside every span lands beside the '
        'nearest span, at its rate', () {
      final alignment = matched(steadyAudio, steadyText);

      // 20 s of opening credits before chapter 1: 200 characters.
      expect(alignment.charactersAt(10000), 800);
    });

    test('a place more than one page outside every span has no landing', () {
      final alignment = matched(steadyAudio, steadyText);

      // The title page: 1000 characters before chapter 1.
      expect(alignment.millisecondsAt(0), isNull);
    });
  });
}
