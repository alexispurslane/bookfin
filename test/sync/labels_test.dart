import 'dart:convert';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/sync/labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _hour = 3600000;
const _minute = 60000;

const _file = SourceFile(
  itemId: 'winter',
  displayName: 'Winter Road.m4b',
  mediaSourceId: 'm1',
  revision: 'r1',
  durationMs: 5 * _hour,
  container: 'm4b',
  sizeBytes: 42,
  chapters: [
    AudioChapter('Chapter 7', 2 * _hour + 30 * _minute),
    AudioChapter('Chapter 12', 4 * _hour + 10 * _minute),
  ],
);
const _edition = Edition(
  id: 'winter-audio',
  kind: EditionKind.audio,
  label: 'Ada Narrator',
  files: [_file],
  memberIds: ['winter:m1'],
);
const _book = Book(
  id: 'winter',
  title: 'Winter Road',
  author: 'A. Writer',
  editions: [_edition],
);

/// 2:33:16.313 into the file, in Chapter 7.
const _chapterSeven = 2 * _hour + 33 * _minute + 16313;

/// 4:12:47 into the file, in Chapter 12.
const _chapterTwelve = 4 * _hour + 12 * _minute + 47000;

final _record = jsonEncode([
  'audio',
  'resumes',
  jsonEncode([_edition.id, _file.key, _file.revision]),
]);

/// Sunday 8 November 2026, 10:00 local time.
final _now = DateTime(2026, 11, 8, 10);

String _clock(DateTime at) => const DefaultMaterialLocalizations()
    .formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal()));

Map<String, dynamic> _place(
  String replica,
  int milliseconds, {
  String? device,
  DateTime? savedAt,
}) => {
  'version': 1,
  'account': 'alice',
  'replica': replica,
  'sequence': 1,
  'context': <String, int>{},
  'record': _record,
  'value': {
    'edition': _edition.id,
    'source': _file.key,
    'revision': _file.revision,
    'milliseconds': milliseconds,
  },
  'preserve': <String>[],
  'device': ?device,
  'savedAt': ?savedAt?.toUtc().toIso8601String(),
};

ConflictLabels _label(
  List<Map<String, dynamic>> versions, {
  String? record,
  List<Book> books = const [_book],
}) => labelConflict(
  record ?? _record,
  versions,
  books: books,
  now: _now,
  clock: _clock,
);

void main() {
  test('a choice names the device that saved the place, the time to the second, and the chapter', () {
    final labels = _label([
      _place('phone', _chapterSeven, device: 'Pixel 8'),
      _place('tablet', _chapterTwelve, device: 'Pixel Tablet'),
    ]);
    expect(labels.choices.map((choice) => choice.text), [
      'Pixel 8 · 2:33:16 · Chapter 7',
      'Pixel Tablet · 4:12:47 · Chapter 12',
    ]);
  });

  test(
    'the book title appears once, as the title, and no choice repeats it',
    () {
      final labels = _label([
        _place('phone', _chapterSeven, device: 'Pixel 8'),
        _place('tablet', _chapterTwelve, device: 'Pixel Tablet'),
      ]);
      expect(labels.title, 'Winter Road');
      expect(labels.kind, 'Listening saved place');
      for (final choice in labels.choices) {
        expect(choice.text, isNot(contains('Winter Road')));
        expect(choice.text, isNot(contains('Ada Narrator')));
        expect(choice.text, isNot(contains('.m4b')));
      }
    },
  );

  group('without a device name, a choice says when its place was saved', () {
    String source(DateTime savedAt) =>
        _label([_place('phone', _chapterSeven, savedAt: savedAt)])
            .choices
            .single
            .source;

    test('earlier today', () {
      expect(source(DateTime(2026, 11, 8, 9, 12)), 'Saved 9:12 AM today');
    });

    test('yesterday', () {
      expect(source(DateTime(2026, 11, 7, 21, 12)), 'Saved 9:12 PM yesterday');
    });

    test('earlier this week, by its weekday', () {
      expect(source(DateTime(2026, 11, 3, 21, 12)), 'Saved 9:12 PM on Tuesday');
    });

    test('longer ago, by its date', () {
      expect(source(DateTime(2026, 10, 12, 21, 12)), 'Saved 9:12 PM on 12 Oct');
    });
  });

  test(
    'a place in a book outside the library shows its time without a chapter',
    () {
      final labels = _label([
        _place('phone', _chapterSeven, device: 'Pixel 8'),
      ], books: const []);
      expect(labels.choices.single.text, 'Pixel 8 · 2:33:16');
      expect(labels.choices.single.bookmarkTitle, 'Pixel 8');
    },
  );

  test('a place before the first chapter of a file is in a chapter named after the file', () {
    final labels = _label([_place('phone', 12 * _minute, device: 'Pixel 8')]);
    expect(labels.choices.single.text, 'Pixel 8 · 12:00 · Winter Road.m4b');
  });

  test(
    'two places from devices with the same name also say when each was saved',
    () {
      final labels = _label([
        _place(
          'phone',
          _chapterSeven,
          device: 'Pixel 8',
          savedAt: DateTime(2026, 11, 7, 21, 12),
        ),
        _place(
          'reinstalled',
          _chapterTwelve,
          device: 'Pixel 8',
          savedAt: DateTime(2026, 11, 8, 9, 5),
        ),
      ]);
      expect(labels.choices.map((choice) => choice.source), [
        'Pixel 8, saved 9:12 PM yesterday',
        'Pixel 8, saved 9:05 AM today',
      ]);
    },
  );

  group('records from before devices were named', () {
    test('an old saved place with neither device nor time names no device', () {
      final labels = _label([
        _place('phone', _chapterSeven),
        _place('tablet', _chapterTwelve, device: 'Pixel Tablet'),
      ]);
      expect(labels.choices.map((choice) => choice.text), [
        'Unknown device · 2:33:16 · Chapter 7',
        'Pixel Tablet · 4:12:47 · Chapter 12',
      ]);
    });

    test('an old bookmark says when it was made', () {
      final record = jsonEncode(['audio', 'bookmarks', 'mark']);
      final labels = _label(record: record, [
        {
          ..._place('phone', 0),
          'record': record,
          'value': {
            'id': 'mark',
            'position': _place('phone', _chapterSeven)['value'],
            'createdAt': DateTime(
              2026,
              11,
              7,
              21,
              12,
            ).toUtc().toIso8601String(),
            'bookTitle': 'Winter Road',
            'editionLabel': 'Ada Narrator',
            'title': 'Snow at the pass',
          },
        },
      ]);
      expect(
        labels.choices.single.text,
        'Saved 9:12 PM yesterday · 2:33:16 · Chapter 7 · Snow at the pass',
      );
    });
  });

  test('the bookmark that keeps a place is titled with its device or save time, and its chapter', () {
    final labels = _label([
      _place('phone', _chapterSeven, device: 'Pixel 8'),
      _place('tablet', _chapterTwelve, savedAt: DateTime(2026, 11, 7, 21, 12)),
    ]);
    expect(labels.choices.map((choice) => choice.bookmarkTitle), [
      'Pixel 8 · Chapter 7',
      'Saved 9:12 PM yesterday · Chapter 12',
    ]);
    expect(labels.choices.map((choice) => choice.identity), [
      'action.phone.1',
      'action.tablet.1',
    ]);
  });

  test('a saved place shows its time apart from the chapter', () {
    final choice = _label([_place('phone', _chapterSeven, device: 'Pixel 8')])
        .choices
        .single;
    expect(choice.time, '2:33:16');
    expect(choice.detail, 'Chapter 7');
  });

  test('the labels name the book of the current library', () {
    final labels = _label([_place('phone', _chapterSeven, device: 'Pixel 8')]);
    expect(labels.book, same(_book));
    final outside = _label([
      _place('phone', _chapterSeven, device: 'Pixel 8'),
    ], books: const []);
    expect(outside.book, isNull);
  });

  group('the track of the whole book', () {
    test('holds every saved place where it lies in the edition', () {
      final track = _label([
        _place('phone', _chapterSeven, device: 'Pixel 8'),
        _place('tablet', _chapterTwelve, device: 'Pixel Tablet'),
      ]).track!;
      expect(track.places, [
        _chapterSeven / (5 * _hour),
        _chapterTwelve / (5 * _hour),
      ]);
      expect(track.length, '5 h 0 m');
    });

    test('marks where each chapter after the first begins', () {
      final track = _label([
        _place('phone', _chapterSeven, device: 'Pixel 8'),
        _place('tablet', _chapterTwelve, device: 'Pixel Tablet'),
      ]).track!;
      expect(track.chapters, [0.5, (4 * _hour + 10 * _minute) / (5 * _hour)]);
    });

    test('places a place in a later file after the files before it', () {
      const later = SourceFile(
        itemId: 'winter-2',
        displayName: 'Winter Road 2.m4b',
        mediaSourceId: 'm2',
        revision: 'r1',
        durationMs: 3 * _hour,
        container: 'm4b',
        sizeBytes: 42,
      );
      const edition = Edition(
        id: 'winter-audio',
        kind: EditionKind.audio,
        label: 'Ada Narrator',
        files: [_file, later],
        memberIds: ['winter:m1', 'winter-2:m2'],
      );
      const book = Book(
        id: 'winter',
        title: 'Winter Road',
        author: 'A. Writer',
        editions: [edition],
      );
      final inLater = {
        ..._place('tablet', _hour, device: 'Pixel Tablet'),
        'value': {
          'edition': edition.id,
          'source': later.key,
          'revision': later.revision,
          'milliseconds': _hour,
        },
      };
      final track = _label(
        [_place('phone', _chapterSeven, device: 'Pixel 8'), inLater],
        books: const [book],
      ).track!;
      expect(track.places, [_chapterSeven / (8 * _hour), 6 / 8]);
      expect(track.chapters, contains(5 / 8));
    });

    test('is missing when the edition is not in the library', () {
      expect(
        _label([
          _place('phone', _chapterSeven, device: 'Pixel 8'),
          _place('tablet', _chapterTwelve, device: 'Pixel Tablet'),
        ], books: const []).track,
        isNull,
      );
    });

    test('is missing for a bookmark, which is no saved place', () {
      final record = jsonEncode(['audio', 'bookmarks', 'mark']);
      Map<String, dynamic> mark(String replica, String title) => {
        ..._place(replica, 0, device: replica),
        'record': record,
        'value': {
          'id': 'mark',
          'position': _place(replica, _chapterSeven)['value'],
          'createdAt': '2026-11-07T21:12:00Z',
          'title': title,
        },
      };
      final labels = _label(record: record, [
        mark('phone', 'Snow at the pass'),
        mark('tablet', 'The pass'),
      ]);
      expect(labels.track, isNull);
      expect(labels.choices.map((choice) => choice.detail), [
        'Chapter 7 · Snow at the pass',
        'Chapter 7 · The pass',
      ]);
    });

    test('is missing when one device deleted what the other changed', () {
      final labels = _label([
        _place('phone', _chapterSeven, device: 'Pixel 8'),
        {..._place('tablet', 0, device: 'Pixel Tablet'), 'value': null},
      ]);
      expect(labels.track, isNull);
      expect(labels.choices.last.detail, 'Keep deletion');
      expect(labels.choices.last.time, isNull);
    });
  });

  test('a book holds only the conflicts of its own editions', () {
    final other = jsonEncode([
      'audio',
      'resumes',
      jsonEncode(['other-audio', 'other:m1', 'r1']),
    ]);
    final ours = [_place('phone', _chapterSeven, device: 'Pixel 8')];
    final theirs = [
      {
        ..._place('phone', 0),
        'record': other,
        'value': {
          'edition': 'other-audio',
          'source': 'other:m1',
          'revision': 'r1',
          'milliseconds': 0,
        },
      },
    ];
    expect(bookConflicts({_record: ours, other: theirs}, _book).keys, [
      _record,
    ]);
  });
}
