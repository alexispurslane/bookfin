import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  final fixture = Platform.environment['BOOKFIN_PRODUCTION_SYNC_FIXTURE'];
  test(
    'two durable ordinary-account clients merge offline edits through the actual plugin',
    () async {
      SharedPreferences.setMockInitialValues({});
      final config = jsonDecode(
        await File(fixture!).readAsString(),
      ) as Map<String, dynamic>;
      final session = JellyfinSession.fromJson(config);
      final client = JellyfinClient(
        session.scope.server,
        deviceId: 'production-store-test',
      );
      addTearDown(client.close);
      final account = session.scope.key;
      final directory = await Directory.systemTemp.createTemp(
        'bookfin-plugin-clients-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final firstPath = '${directory.path}/first.sqlite';
      final secondPath = '${directory.path}/second.sqlite';
      final firstDatabase = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: firstPath,
      );
      final secondDatabase = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: secondPath,
      );
      final firstStore = LocalResumeStore(
        openDatabase: () async => firstDatabase,
      );
      final secondStore = LocalResumeStore(
        openDatabase: () async => secondDatabase,
      );

      Map<String, dynamic> snapshot(String id, int milliseconds) => {
        'version': 3,
        'bookmarks': [
          {
            'id': id,
            'position': {
              'edition': 'book',
              'source': 'audio',
              'revision': 'v1',
              'milliseconds': milliseconds,
            },
            'createdAt': id == 'first'
                ? '2099-01-01T00:00:00Z'
                : '1970-01-01T00:00:00Z',
            'bookTitle': 'Fixture',
            'editionLabel': 'Audio',
            'title': id,
          },
        ],
        'history': [
          {
            'id': 'history-$id',
            'at': id == 'first'
                ? '2099-01-01T00:00:00Z'
                : '1970-01-01T00:00:00Z',
            'kind': 'pause',
            'bookTitle': 'Fixture',
            'editionLabel': 'Audio',
            'before': {
              'edition': 'book',
              'source': 'audio',
              'revision': 'v1',
              'milliseconds': milliseconds,
            },
            'after': {
              'edition': 'book',
              'source': 'audio',
              'revision': 'v1',
              'milliseconds': milliseconds,
            },
          },
        ],
        'resumes': {
          'book': [
            {
              'source': 'audio',
              'revision': 'v1',
              'sources': 'same-recording',
              'milliseconds': milliseconds,
            },
          ],
        },
      };

      await firstStore.write(account, snapshot('first', 900));
      await secondStore.write(account, snapshot('second', 100));
      for (final entry in [(firstStore, 'first'), (secondStore, 'second')]) {
        await entry.$1.reading.write(account, {
          'version': 1,
          'resumes': [],
          'bookmarks': [
            {
              'id': entry.$2,
              'position': {
                'edition': 'book',
                'source': 'ebook',
                'revision': 'text-v1',
                'anchor': 'page-one',
              },
              'createdAt': '1970-01-01T00:00:00Z',
              'title': 'Reading ${entry.$2}',
            },
          ],
        });
      }
      await secondStore.synchronize(session, client);
      await firstStore.synchronize(session, client);
      expect((await firstStore.read(account))!['bookmarks'], hasLength(2));
      expect((await firstStore.read(account))!['history'], hasLength(2));
      expect(
        (await firstStore.reading.read(account))!['bookmarks'],
        hasLength(2),
      );
      final conflicts = await firstStore.conflicts(account);
      expect(conflicts, hasLength(1));
      expect(
        conflicts.values.single.map(
          (action) => action['value']['milliseconds'],
        ),
        unorderedEquals([900, 100]),
      );

      await secondStore.synchronize(session, client);
      final secondSaved = (await secondStore.read(account))!;
      secondStore.acceptSnapshot(account, secondSaved);
      (secondSaved['bookmarks'] as List).removeWhere(
        (value) => value['id'] == 'first',
      );
      (secondSaved['history'] as List).removeWhere(
        (value) => value['id'] == 'history-first',
      );
      await secondStore.write(account, secondSaved);
      await secondStore.synchronize(session, client);
      await firstDatabase.close();

      final reopened = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: firstPath,
      );
      addTearDown(reopened.close);
      final restarted = LocalResumeStore(openDatabase: () async => reopened);
      await restarted.synchronize(session, client);
      expect((await restarted.read(account))!['bookmarks'], hasLength(1));
      expect((await restarted.read(account))!['history'], hasLength(1));
      final conflict = (await restarted.conflicts(account)).entries.single;
      final chosen = conflict.value.firstWhere(
        (action) => action['value']['milliseconds'] == 100,
      );
      await restarted.resolve(
        account,
        conflict.key,
        RecordJournal.identity(chosen),
      );
      await restarted.synchronize(session, client);
      expect(await restarted.conflicts(account), isEmpty);
      final resolved = (await restarted.read(account))!;
      expect((resolved['resumes'] as Map)['book'][0]['milliseconds'], 100);
      expect(
        resolved['bookmarks'],
        hasLength(3),
        reason: 'Choosing must keep both conflicting places as bookmarks.',
      );
      expect(
        (await restarted.reading.read(account))!['bookmarks'],
        hasLength(2),
      );
      await reopened.checkInvariants();
      await secondDatabase.close();

      final otherReopened = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: secondPath,
      );
      addTearDown(otherReopened.close);
      final otherRestarted = LocalResumeStore(
        openDatabase: () async => otherReopened,
      );
      await otherRestarted.synchronize(session, client);
      expect(await otherRestarted.conflicts(account), isEmpty);
      expect((await otherRestarted.read(account))!['bookmarks'], hasLength(3));
      await otherRestarted.synchronize(session, client);
      expect((await otherRestarted.read(account))!['bookmarks'], hasLength(3));
      await otherReopened.checkInvariants();
    },
    skip: fixture == null
        ? 'Run tool/sync_fixture.py in the pinned shells.'
        : false,
  );
}
