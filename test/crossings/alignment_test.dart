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

/// The visible characters of the twenty chapters of a novel, as uneven as
/// real chapters: from 7000 to 13000, so that no two neighbors differ by
/// a factor of two.
const _novel = [
  9000, 12500, 7200, 11000, 8300, 13000, 7600, 10400, 12100, 7000, //
  9800, 11800, 8000, 12800, 7400, 10900, 9100, 12300, 7800, 10000,
];

/// The milliseconds that a narrator takes to read [characters] at 12
/// visible characters a second.
int _read(int characters) => characters * 1000 ~/ 12;

/// Where each chapter of [_novel] starts in its ebook, after a title page
/// of 1500 characters and a preface of 1500.
final _chapterStarts = [
  for (var chapter = 0, start = 3000; chapter < _novel.length; chapter++)
    start += chapter == 0 ? 0 : _novel[chapter - 1],
];

/// Where each track or chapter of [_novel]'s recording starts: 30 s of
/// credits, then the preface, then each chapter.
final _trackStarts = [
  0,
  30000,
  for (final start in _chapterStarts) 30000 + _read(start - 1500),
];

/// The length of [_novel]'s recording.
final _recorded = 30000 + _read(3000 + _novel.reduce((a, b) => a + b) - 1500);

/// A recording of [_novel] whose 21 marks name tracks: track 01 holds the
/// credits and the preface, and track N holds chapter N - 1. The ebook
/// numbers its chapters, so track N pairs with chapter N by chance, as
/// book J of the user's library did ("Measured on the user's library").
(AudioOutline, TextOutline) offByOneTracks() => (
  recording([
    ('01 Book J', 0),
    for (final (index, start) in _trackStarts.skip(2).indexed)
      ('${(index + 2).toString().padLeft(2, '0')} Book J', start),
  ], _recorded),
  ebook([
    ('Title page', 0, 0),
    ('Preface', 0, 1500),
    for (final (index, start) in _chapterStarts.indexed)
      ('Chapter ${index + 1}', 0, start),
  ], 3000 + _novel.reduce((a, b) => a + b)),
);

/// The recording of [offByOneTracks] with marks that name its chapters.
AudioOutline namedTracks() => recording([
  ('Opening Credits', 0),
  ('Preface', 30000),
  for (final (index, start) in _trackStarts.skip(2).indexed)
    ('Chapter ${index + 1}', start),
], _recorded);

/// A recording of one short work in three chapters, and an anthology of
/// three works that each number their chapters from 1. Chapters 1, 2 and 3
/// of the recording pair with chapter 1 of the first work, chapter 2 of the
/// second and chapter 3 of the third, where their shares of the two
/// editions agree best, as book E of the user's library did.
(AudioOutline, TextOutline) storyInAnthology() {
  const works = [
    ('The First Work', [8000, 8000, 8000, 16000]),
    ('The Second Work', [8000, 8000, 8000, 8000]),
    ('The Third Work', [8000, 8000, 8000, 8000]),
  ];
  final entries = <(String, int, int)>[];
  var start = 0;
  for (final (title, chapters) in works) {
    entries.add((title, 0, start));
    for (final (index, characters) in chapters.indexed) {
      entries.add(('Chapter ${index + 1}', 1, start));
      start += characters;
    }
  }
  return (
    recording([
      ('Chapter 1', 0),
      ('Chapter 2', 1200000),
      ('Chapter 3', 2520000),
    ], 3600000),
    ebook(entries, start),
  );
}

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

    test('when the contents entries of matching chapters start at one '
        'place, so their spans do not move forward', () {
      final audio = recording([
        ('Chapter 1', 0),
        ('Chapter 2', 60000),
        ('Chapter 3', 120000),
        ('Chapter 4', 180000),
      ], 240000);
      final text = ebook([
        ('Chapter 1', 0, 0),
        ('Chapter 2', 0, 0),
        ('Chapter 3', 0, 0),
        ('Chapter 4', 0, 1800),
      ], 2400);

      expect(alignEditions(audio, text), isA<UnmatchedChapters>());
    });

    test('when the matched chapters cover less than three tenths of the '
        'recording', () {
      // Only chapters 1 to 3 pair, a quarter of the recording. Chapters 4
      // to 12 have no counterpart.
      final audio = recording([
        for (var chapter = 1; chapter <= 12; chapter++)
          ('Chapter $chapter', (chapter - 1) * 100000),
      ], 1200000);
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

  group('the self-check', () {
    test('every public recording whose chapters match passes it: each '
        'hidden chapter start lands near its known start', () {
      for (final (work, id) in [
        ('christmas-carol', '6014'),
        ('christmas-carol', '685'),
        ('emma', '1936'),
        ('moby-dick', '21919'),
        ('pride-and-prejudice', '253'),
        ('pride-and-prejudice', '1480'),
        ('walden', '8974'),
      ]) {
        final (audio, text) = fixture(work, id);

        expect(
          alignEditions(audio, text),
          isA<MatchedChapters>(),
          reason: '$work $id',
        );
      }
    });

    test('refuses track numbers that pair with chapter numbers by chance, '
        'one chapter late because track 01 holds the credits and the '
        'preface', () {
      final (audio, text) = offByOneTracks();

      expect(
        (alignEditions(audio, text) as UnmatchedChapters).reason,
        Refusal.misaligned,
      );
    });

    test('keeps the same recording when its marks name its chapters', () {
      final (_, text) = offByOneTracks();
      final audio = namedTracks();

      final alignment = matched(audio, text);

      expect(pairs(alignment, audio, text)['Chapter 7'], 'Chapter 7');
    });

    test('refuses a recording of one work against an anthology, whose '
        'numbered chapters match in three different works', () {
      final (audio, text) = storyInAnthology();

      expect(
        (alignEditions(audio, text) as UnmatchedChapters).reason,
        Refusal.misaligned,
      );
    });

    test('keeps two chapters whose titles share their words, though no '
        'third chapter can check them', () {
      final audio = recording([
        ("Marley's Ghost", 0),
        ('The First of the Three Spirits', 100000),
      ], 200000);
      final text = ebook([
        ('MARLEY’S GHOST.', 0, 0),
        ('THE FIRST OF THE THREE SPIRITS.', 0, 1000),
      ], 2000);

      expect(matched(audio, text).anchors, hasLength(2));
    });

    test('refuses two chapters that pair by their numbers alone, because no '
        'third chapter can check them', () {
      final audio = recording([('01', 0), ('02', 100000)], 200000);
      final text = ebook([('Chapter 1', 0, 0), ('Chapter 2', 0, 1000)], 2000);

      expect(
        (alignEditions(audio, text) as UnmatchedChapters).reason,
        Refusal.fewMatches,
      );
    });
  });

  test('matched chapters that cover a third of the recording match, as '
      'chapters numbered inside volumes can', () {
    // Chapters 1 to 4 pair. Chapters 5 to 12 have no counterpart.
    final audio = recording([
      for (var chapter = 1; chapter <= 12; chapter++)
        ('Chapter $chapter', (chapter - 1) * 100000),
    ], 1200000);
    final text = ebook([
      ('I', 0, 0),
      ('II', 0, 1000),
      ('III', 0, 2000),
      ('IV', 0, 3000),
    ], 4000);

    expect(matched(audio, text).anchors, hasLength(4));
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
