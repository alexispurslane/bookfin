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
    'the book title appears once, in the heading, and no choice repeats it',
    () {
      final labels = _label([
        _place('phone', _chapterSeven, device: 'Pixel 8'),
        _place('tablet', _chapterTwelve, device: 'Pixel Tablet'),
      ]);
      expect(labels.heading, startsWith('Winter Road · '));
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
}
