import 'dart:convert';
import 'dart:io';

import 'package:bookfin/sync/record_address.dart';
import 'package:bookfin/sync/transport.dart';
import 'package:bookfin/catalog/shelf.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/sync/labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/playback_test.dart' as audio;
import 'fixture.dart';

// Each saved change names the device that made it and when, so that a choice
// between saved places can say where each place came from. Records from
// before device names stay readable both ways.

const _settings = <String, dynamic>{
  'version': 3,
  'selected': 'recording',
  'speed': 1.0,
  'backward': 10,
  'forward': 30,
};

/// The change set that moves the place in the first file of the test
/// recording to [milliseconds].
ListeningChanges _place(int milliseconds) => ListeningChanges(
  _settings,
  resumes: {
    audio.recording.id: [
      {
        'source': audio.first.key,
        'revision': audio.first.revision,
        'milliseconds': milliseconds,
        'pendingOffline': false,
      },
    ],
  },
);

final _resume = jsonEncode([
  'audio',
  'resumes',
  jsonEncode([audio.recording.id, audio.first.key, audio.first.revision]),
]);

/// A place in the first file of the test recording, saved by an app from
/// before device names: the action has no device and no save time.
Map<String, dynamic> _olderAppPlace(String account, int milliseconds) => {
  'version': 1,
  'account': account,
  'replica': 'older-tablet',
  'sequence': 1,
  'context': <String, int>{},
  'record': _resume,
  'value': {
    'edition': audio.recording.id,
    'source': audio.first.key,
    'revision': audio.first.revision,
    'milliseconds': milliseconds,
  },
  'preserve': <String>[],
};

String _clock(DateTime at) => const DefaultMaterialLocalizations()
    .formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal()));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late SyncFixture fixture;
  late String account;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = await SyncFixture.open();
    account = fixture.session.scope.key;
  });
  tearDown(() => fixture.close());

  /// The actions on the server, as each device downloads them.
  List<Map<String, dynamic>> served() => [
    for (final object in fixture.objects.values)
      jsonDecode(object['Payload'] as String) as Map<String, dynamic>,
  ];

  test('a change names the device that made it and when it was saved', () {
    final journal = RecordJournal('alice', 'phone');
    final savedAt = DateTime.utc(2026, 11, 7, 21, 12);
    journal.change(
      _resume,
      {'milliseconds': 900},
      device: 'Pixel 8',
      savedAt: savedAt,
    );
    final action = journal.uploads.single;
    expect(action['device'], 'Pixel 8');
    expect(DateTime.parse(action['savedAt'] as String), savedAt);
  });

  test('each place that the phone saves carries its device name and save time to the server', () async {
    final store = LocalResumeStore(deviceName: () async => 'Pixel 8');
    final before = DateTime.now();
    await store.save(account, _place(9000));
    final after = DateTime.now();
    await RecordTransport(store).synchronize(fixture.session, fixture.client);
    final place = served().single;
    expect(place['device'], 'Pixel 8');
    final savedAt = DateTime.parse(place['savedAt'] as String);
    expect(savedAt.isBefore(before), isFalse);
    expect(savedAt.isAfter(after), isFalse);
  });

  test(
    'on a device without a name, each saved place still carries its save time',
    () async {
      final store = LocalResumeStore(deviceName: () async => null);
      await store.save(account, _place(9000));
      await RecordTransport(store).synchronize(fixture.session, fixture.client);
      final place = served().single;
      expect(place.containsKey('device'), isFalse);
      expect(DateTime.tryParse(place['savedAt'] as String), isNotNull);
    },
  );

  test('choosing a place keeps each other place as a bookmark titled as its choice said', () async {
    final phone = LocalResumeStore(deviceName: () async => 'Pixel 8');
    await phone.save(account, _place(45000));
    final tablet = RecordJournal(account, 'tablet')
      ..change(_resume, {
        'edition': audio.recording.id,
        'source': audio.first.key,
        'revision': audio.first.revision,
        'milliseconds': 5000,
      }, device: 'Pixel Tablet');
    fixture.publish(tablet);
    await RecordTransport(phone).synchronize(fixture.session, fixture.client);
    final versions = (await phone.conflicts(
      account,
    ))[RecordAddress.parse(_resume)]!;
    final labels = labelConflict(
      RecordAddress.parse(_resume),
      versions,
      books: CatalogLibrary.build([audio.title]).books,
      now: DateTime.now(),
      clock: _clock,
    );
    final chosen = labels.choices.firstWhere(
      (choice) => choice.source == 'Pixel Tablet',
    );
    expect(
      await phone.resolve(
        account,
        RecordAddress.parse(_resume),
        chosen.identity,
        bookmarkTitles: {
          for (final choice in labels.choices)
            choice.identity: choice.bookmarkTitle,
        },
      ),
      isTrue,
    );
    final bookmarks = (await phone.read(account))!['bookmarks'] as List;
    expect(
      bookmarks.map((bookmark) => bookmark['title']),
      unorderedEquals(['Pixel 8 · Arrival', 'Pixel Tablet · Opening']),
    );
  });

  test('this app reads places from an older app, and an older app reads this app\'s places unchanged', () async {
    fixture.objects['action.older-tablet.1'] = {
      'Id': 'action.older-tablet.1',
      'Sequence': 1,
      'Payload': jsonEncode(_olderAppPlace(account, 5000)),
      'Deleted': false,
    };
    final phone = LocalResumeStore(deviceName: () async => 'Pixel 8');
    await phone.save(account, _place(45000));
    await RecordTransport(phone).synchronize(fixture.session, fixture.client);

    final versions = (await phone.conflicts(
      account,
    ))[RecordAddress.parse(_resume)]!;
    final labels = labelConflict(
      RecordAddress.parse(_resume),
      versions,
      books: CatalogLibrary.build([audio.title]).books,
      now: DateTime.now(),
      clock: _clock,
    );
    expect(
      labels.choices.map((choice) => choice.source),
      unorderedEquals(['Pixel 8', 'Unknown device']),
    );

    // An older app's journal accepts the same actions, and keeps the
    // device name and save time of this app's action as they were.
    final older = RecordJournal(account, 'older-tablet')..receive(served());
    final phoneAction = served().singleWhere(
      (action) => action['device'] == 'Pixel 8',
    );
    expect(older.retained(RecordJournal.identity(phoneAction)), phoneAction);
    expect(older.conflicts[_resume], hasLength(2));
    older.checkInvariants();
  });
}
