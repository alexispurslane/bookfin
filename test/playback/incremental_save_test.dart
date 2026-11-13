import 'dart:convert';
import 'dart:io';

import 'package:bookfin/sync/record_address.dart';
import 'package:bookfin/sync/transport.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../sync/fixture.dart';
import 'history_test.dart' show FailingRecordStore;
import 'playback_test.dart';

const settings = <String, dynamic>{
  'version': 3,
  'selected': 'edition',
  'speed': 1.0,
  'backward': 10,
  'forward': 30,
};

AudioPosition at(int milliseconds) => AudioPosition(
  editionId: 'edition',
  sourceKey: 'source',
  revision: 'revision',
  milliseconds: milliseconds,
);

Map<String, dynamic> event(String id, int milliseconds) => HistoryEvent(
  id: id,
  at: DateTime.utc(2026, 11, 7, 12),
  kind: HistoryAction.seek,
  before: at(0),
  after: at(milliseconds),
  bookTitle: 'Book',
  editionLabel: 'Audio',
).toJson();

Map<String, dynamic> bookmark(String id, {String? title}) => Bookmark(
  id: id,
  position: at(5000),
  createdAt: DateTime.utc(2026, 11, 7, 12),
  bookTitle: 'Book',
  editionLabel: 'Audio',
  title: title,
).toJson();

Map<String, List<Map<String, dynamic>>> resume(int milliseconds) => {
  'edition': [
    {
      'source': 'source',
      'revision': 'revision',
      'sources': '[["source","revision"]]',
      'milliseconds': milliseconds,
      'pendingOffline': false,
    },
  ],
};

/// A memory store that keeps every change set that Playback hands it.
class RecordingStore extends MemoryResume {
  final saves = <ListeningChanges>[];
  @override
  Future<void> save(String accountKey, ListeningChanges changes) {
    saves.add(changes);
    return super.save(accountKey, changes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  HttpOverrides.global = null;

  group('listening changes', () {
    test('a later change of a record replaces the earlier one and keeps the other records', () {
      final earlier = ListeningChanges(
        settings,
        history: {'one': event('one', 1000)},
        bookmarks: {'mark': bookmark('mark', title: 'Old')},
        resumes: resume(1000),
      );
      final later = ListeningChanges(
        {...settings, 'speed': 1.5},
        bookmarks: {
          'mark': bookmark('mark', title: 'New'),
          'gone': null,
        },
        resumes: resume(2000),
      );
      final combined = earlier.followedBy(later);
      expect(combined.settings['speed'], 1.5);
      expect(combined.history, {'one': event('one', 1000)});
      expect(combined.bookmarks, {
        'mark': bookmark('mark', title: 'New'),
        'gone': null,
      });
      expect(combined.resumes, resume(2000));
    });

    test('applied to a saved snapshot, changes replace records in place, append new ones and remove deleted ones', () {
      final saved = {
        ...settings,
        'speed': 2.0,
        'history': [event('one', 1000), event('two', 2000)],
        'bookmarks': [bookmark('first'), bookmark('second')],
        'resumes': resume(1000),
      };
      final applied = ListeningChanges(
        settings,
        history: {'one': null, 'three': event('three', 3000)},
        bookmarks: {'first': bookmark('first', title: 'Renamed')},
        resumes: resume(4000),
      ).applyTo(saved);
      expect(applied['speed'], 1.0);
      expect(applied['history'], [event('two', 2000), event('three', 3000)]);
      expect(applied['bookmarks'], [
        bookmark('first', title: 'Renamed'),
        bookmark('second'),
      ]);
      expect(applied['resumes'], resume(4000));
      expect(
        ListeningChanges(
          settings,
          history: {'one': event('one', 1000)},
        ).applyTo(null),
        {
          ...settings,
          'history': [event('one', 1000)],
          'bookmarks': <dynamic>[],
          'resumes': <String, dynamic>{},
        },
      );
    });
  });

  group('Playback hands the store only what changed', () {
    late LocalFiles downloads;
    late TestEngine engine;
    late RecordingStore store;
    late Playback playback;
    setUp(() async {
      downloads = LocalFiles();
      engine = TestEngine();
      store = RecordingStore();
      playback = Playback(downloads: downloads, engine: engine, store: store);
      await playback.bind(account(), [title]);
      await playback.open(title, recording);
      await playback.seekEdition(30000);
      await playback.addBookmark(title: 'Kept');
      await playback.flush();
      store.saves.clear();
    });
    tearDown(() async {
      await playback.close();
      downloads.dispose();
    });

    test('moving the position by a whole second saves only the open edition resume', () async {
      engine.emit(0, 31000, playing: true);
      engine.emit(0, 32000, playing: true);
      await playback.flush();
      expect(store.saves, isNotEmpty);
      for (final changes in store.saves) {
        expect(changes.history, isEmpty);
        expect(changes.bookmarks, isEmpty);
        expect(changes.resumes.keys, ['recording']);
      }
      expect(
        store
            .values[account().scope.key]!['resumes']['recording']
            .single['milliseconds'],
        32000,
      );
      expect(
        store.values[account().scope.key]!['history'],
        hasLength(playback.history.length),
      );
      playback.checkInvariants();
    });

    test('a new history event is saved as that one event', () async {
      await playback.pause();
      await playback.flush();
      final paused = playback.history.first;
      expect(paused.kind, HistoryAction.pause);
      expect(store.saves.expand((changes) => changes.history.keys), [
        paused.id,
      ]);
      expect(store.saves.last.history[paused.id], paused.toJson());
      expect(store.saves.expand((changes) => changes.bookmarks.keys), isEmpty);
    });

    test(
      'adding, editing and deleting a bookmark saves only that bookmark',
      () async {
        await playback.addBookmark(title: 'Added');
        final added = playback.bookmarks.first;
        expect(store.saves.last.bookmarks, {added.id: added.toJson()});
        await playback.editBookmark(added.id, title: 'Edited');
        expect(store.saves.last.bookmarks, {
          added.id: playback.bookmarks.first.toJson(),
        });
        await playback.deleteBookmark(added.id);
        expect(store.saves.last.bookmarks, {added.id: null});
        expect(store.saves.expand((changes) => changes.history.keys), isEmpty);
        expect(
          (store.values[account().scope.key]!['bookmarks'] as List).map(
            (mark) => mark['title'],
          ),
          ['Kept'],
        );
        playback.checkInvariants();
      },
    );

    test(
      'unsaved changes survive an account switch whose restore read fails',
      () async {
        final failing = FailingRecordStore();
        await playback.close();
        playback = Playback(
          downloads: downloads,
          engine: TestEngine(),
          store: failing,
        );
        await playback.bind(account(), [title]);
        await playback.open(title, recording);
        failing.fail = true;
        await playback.addBookmark(title: 'Keep me');
        await playback.bind(account(user: 'bob'), [title]);
        failing.failRead = true;
        await playback.bind(account(), [title]);
        expect(playback.message, contains('Cannot restore'));
        expect(playback.unsavedChanges, isTrue);
        failing
          ..fail = false
          ..failRead = false;
        await playback.flush();
        expect(playback.unsavedChanges, isFalse);
        await playback.bind(null, []);
        await playback.bind(account(), [title]);
        expect(playback.bookmarks.single.title, 'Keep me');
        playback.checkInvariants();
      },
    );

    test('deleting a history event saves only its deletion', () async {
      final seek = playback.history.firstWhere(
        (event) => event.kind == HistoryAction.seek,
      );
      await playback.deleteHistory(seek.id);
      expect(store.saves.last.history, {seek.id: null});
      expect(store.saves.last.bookmarks, isEmpty);
      expect(
        (store.values[account().scope.key]!['history'] as List).map(
          (event) => event['id'],
        ),
        isNot(contains(seek.id)),
      );
    });
  });

  group('the record store saves change sets', () {
    late String path;
    late RecordDatabase records;
    late Database sql;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp('bookfin-sets-');
      addTearDown(() => directory.delete(recursive: true));
      path = '${directory.path}/records.sqlite';
      records = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      sql = await databaseFactoryFfi.openDatabase(path);
      addTearDown(() async {
        await sql.close();
        await records.close();
      });
    });

    Future<List<Map<String, dynamic>>> actions(String account) async =>
        ((jsonDecode((await records.read(account))!) as Map)['sync']['actions']
                as List)
            .cast<Map<String, dynamic>>();

    test(
      'a saved position adds one resume action and writes no history record',
      () async {
        final store = LocalResumeStore(openDatabase: () async => records);
        await store.save(
          'alice',
          ListeningChanges(
            settings,
            history: {
              for (final id in ['one', 'two', 'three'])
                id: event(id, id.length * 1000),
            },
            bookmarks: {'mark': bookmark('mark')},
            resumes: resume(1000),
          ),
        );
        final before = await actions('alice');
        await sql.execute('CREATE TABLE written (record TEXT NOT NULL)');
        await sql.execute(
          'CREATE TRIGGER audit_versions AFTER INSERT ON record_versions BEGIN INSERT INTO written VALUES (NEW.record); END',
        );
        await store.save(
          'alice',
          ListeningChanges(settings, resumes: resume(2000)),
        );
        final after = await actions('alice');
        expect(after, hasLength(before.length + 1));
        expect(
          RecordAddress.parse(after.last['record'] as String).collection,
          'resumes',
        );
        expect(
          (await sql.query('written')).map(
            (row) => RecordAddress.parse(row['record'] as String).collection,
          ),
          ['resumes'],
        );
        final saved = (await store.read('alice'))!;
        expect(saved['history'], hasLength(3));
        expect(saved['bookmarks'], [bookmark('mark')]);
        expect(saved['resumes']['edition'].single['milliseconds'], 2000);
        await store.checkInvariants();
      },
    );

    test('history and bookmark changes persist across restart and sync as their own actions', () async {
      final fixture = await SyncFixture.open();
      addTearDown(fixture.close);
      final account = fixture.session.scope.key;
      final store = LocalResumeStore(openDatabase: () async => records);
      await store.save(
        account,
        ListeningChanges(
          settings,
          history: {'one': event('one', 1000), 'two': event('two', 2000)},
          bookmarks: {'mark': bookmark('mark', title: 'Old')},
        ),
      );
      await store.save(
        account,
        ListeningChanges(
          {...settings, 'speed': 1.5},
          history: {'one': null},
          bookmarks: {'mark': bookmark('mark', title: 'New')},
        ),
      );
      await RecordTransport(store).synchronize(fixture.session, fixture.client);
      final uploaded = [
        for (final object in fixture.objects.values)
          jsonDecode(object['Payload'] as String) as Map<String, dynamic>,
      ];
      expect(
        uploaded.map(
          (action) => [
            RecordAddress.parse(action['record'] as String).id,
            action['value'],
          ],
        ),
        [
          ['one', event('one', 1000)],
          ['two', event('two', 2000)],
          ['mark', bookmark('mark', title: 'Old')],
          ['one', null],
          ['mark', bookmark('mark', title: 'New')],
        ],
      );
      await records.close();
      records = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      final restarted = LocalResumeStore(openDatabase: () async => records);
      final saved = (await restarted.read(account))!;
      expect(saved['speed'], 1.5);
      expect(saved['history'], [event('two', 2000)]);
      expect(saved['bookmarks'], [bookmark('mark', title: 'New')]);
      await restarted.checkInvariants();
    });

    test('saving changes that were already saved adds no action', () async {
      final store = LocalResumeStore(openDatabase: () async => records);
      final changes = ListeningChanges(
        settings,
        history: {'one': event('one', 1000)},
        resumes: resume(1000),
      );
      await store.save('alice', changes);
      final count = (await actions('alice')).length;
      await store.save('alice', changes);
      expect(await actions('alice'), hasLength(count));
    });

    test('a repeated earlier change cannot undo a newer change from another installation', () async {
      final fixture = await SyncFixture.open();
      addTearDown(fixture.close);
      final account = fixture.session.scope.key;
      final store = LocalResumeStore(openDatabase: () async => records);
      final local = ListeningChanges(
        settings,
        bookmarks: {'mark': bookmark('mark', title: 'Local')},
      );
      await store.save(account, local);
      await RecordTransport(store).synchronize(fixture.session, fixture.client);
      final remote = RecordJournal(account, 'remote', {
        'version': 1,
        'replica': 'remote',
        'actions': [
          for (final object in fixture.objects.values)
            jsonDecode(object['Payload'] as String),
        ],
        'pending': <String>[],
        'cursor': 0,
      });
      remote.change(
        jsonEncode(['audio', 'bookmarks', 'mark']),
        bookmark('mark', title: 'Remote'),
      );
      fixture.publish(remote);
      await RecordTransport(store).synchronize(fixture.session, fixture.client);
      await store.save(
        account,
        local.followedBy(ListeningChanges(settings, resumes: resume(3000))),
      );
      final saved = (await store.read(account))!;
      expect((saved['bookmarks'] as List).single['title'], 'Remote');
      expect(saved['resumes']['edition'].single['milliseconds'], 3000);
    });
  });
}
