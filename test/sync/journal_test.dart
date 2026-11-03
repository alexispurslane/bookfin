import 'dart:convert';

import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';

String record(String kind, String id) => jsonEncode(['audio', kind, id]);

void main() {
  test(
    'two offline installations retain independent bookmarks and old history',
    () {
      final first = RecordJournal('alice', 'first');
      final second = RecordJournal('alice', 'second');
      first.change(record('bookmarks', 'one'), {'id': 'one', 'at': '2099'});
      second.change(record('history', 'two'), {'id': 'two', 'at': '1970'});
      first.receive(second.uploads);
      second.receive(first.uploads);
      expect(
        first.values.keys,
        unorderedEquals([record('bookmarks', 'one'), record('history', 'two')]),
      );
      expect(second.values, first.values);
      first.checkInvariants();
      second.checkInvariants();
    },
  );

  test('duplicate retries after restart cannot restore a deleted bookmark', () {
    final first = RecordJournal('alice', 'first');
    final key = record('bookmarks', 'one');
    first.change(key, {'id': 'one'});
    final stale = first.uploads;
    first.change(key, null);
    final restarted = RecordJournal('alice', 'first', first.encode());
    restarted.receive([...stale, ...stale]);
    expect(restarted.values, isEmpty);
    expect(restarted.uploads, hasLength(2));
    restarted.checkInvariants();
  });

  test(
    'concurrent reading places remain unresolved instead of using wall clocks',
    () {
      final first = RecordJournal('alice', 'first');
      final second = RecordJournal('alice', 'second');
      final key = record('resumes', 'recording');
      first.change(key, {'milliseconds': 900, 'at': '2099'});
      second.change(key, {'milliseconds': 100, 'at': '1970'});
      first.receive(second.uploads);
      second.receive(first.uploads);
      expect(first.values, isEmpty);
      expect(
        first.conflicts[key]!.map((action) => action['value']['milliseconds']),
        unorderedEquals([900, 100]),
      );
      second.change(key, {'milliseconds': 100}, resolve: true);
      first.receive(second.uploads);
      expect(first.conflicts, isEmpty);
      expect(first.values[key], {'milliseconds': 100});
    },
  );

  test(
    'a causally incomplete action waits across restart for the missing action',
    () {
      final first = RecordJournal('alice', 'first');
      first.change(record('history', 'one'), {'id': 'one'});
      first.change(record('history', 'two'), {'id': 'two'});
      final second = RecordJournal('alice', 'second');
      second.receive([first.uploads.last]);
      expect(second.values, isEmpty);
      final restarted = RecordJournal('alice', 'second', second.encode());
      restarted.receive([first.uploads.first]);
      expect(restarted.values, hasLength(2));
    },
  );

  test(
    'another account cannot inject actions or alter an immutable action',
    () {
      final first = RecordJournal('alice', 'first');
      first.change(record('bookmarks', 'one'), {'id': 'one'});
      expect(
        () => RecordJournal('bob', 'second').receive(first.uploads),
        throwsFormatException,
      );
      final altered = {
        ...first.uploads.single,
        'value': {'id': 'changed'},
      };
      expect(() => first.receive([altered]), throwsFormatException);
      expect(first.values.values.single, {'id': 'one'});
    },
  );

  test(
    'an unseen edit concurrent with deletion preserves both for a user choice',
    () {
      final first = RecordJournal('alice', 'first');
      final second = RecordJournal('alice', 'second');
      final key = record('bookmarks', 'one');
      first.change(key, {'id': 'one', 'title': 'Original'});
      second.receive(first.uploads);
      first.change(key, null);
      second.change(key, {'id': 'one', 'title': 'Edited offline'});
      first.receive(second.uploads);
      expect(first.values, isEmpty);
      expect(first.conflicts[key], hasLength(2));
    },
  );

  test(
    'continued listening does not silently choose between conflicting places',
    () {
      final first = RecordJournal('alice', 'first');
      final second = RecordJournal('alice', 'second');
      final key = record('resumes', 'recording');
      first.change(key, {'milliseconds': 900});
      second.change(key, {'milliseconds': 100});
      first.receive(second.uploads);
      first.change(key, {'milliseconds': 950});
      expect(first.conflicts[key], hasLength(2));
      expect(
        first.conflicts[key]!.map((action) => action['value']['milliseconds']),
        unorderedEquals([950, 100]),
      );
      expect(first.values, isEmpty);
    },
  );
}
