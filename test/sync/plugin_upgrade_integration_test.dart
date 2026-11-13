import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/sync/transport.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> snapshot(String identity, int milliseconds) => {
  'version': 3,
  'bookmarks': [
    {
      'id': identity,
      'position': {
        'edition': 'book',
        'source': 'audio',
        'revision': 'v1',
        'milliseconds': milliseconds,
      },
      'createdAt': '1970-01-01T00:00:00Z',
      'bookTitle': 'Upgrade fixture',
      'editionLabel': 'Audio',
      'title': identity,
    },
  ],
  'history': [
    {
      'id': 'history-$identity',
      'at': '1970-01-01T00:00:00Z',
      'kind': 'pause',
      'bookTitle': 'Upgrade fixture',
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  final fixture = Platform.environment['BOOKFIN_PRODUCTION_SYNC_FIXTURE'];
  final phase = Platform.environment['BOOKFIN_PLUGIN_UPGRADE_PHASE'];
  test(
    'durable ordinary-account records and offline changes survive plugin upgrade: $phase',
    () async {
      SharedPreferences.setMockInitialValues({});
      final config = jsonDecode(
        await File(fixture!).readAsString(),
      ) as Map<String, dynamic>;
      final session = JellyfinSession.fromJson(config);
      final client = JellyfinClient(
        session.scope.server,
        deviceId: 'upgrade-test',
      );
      addTearDown(client.close);
      final account = session.scope.key;
      final directory = File(fixture).parent;
      final firstDatabase = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/first.sqlite',
      );
      addTearDown(firstDatabase.close);
      final secondDatabase = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/second.sqlite',
      );
      addTearDown(secondDatabase.close);
      final first = LocalResumeStore(openDatabase: () async => firstDatabase);
      final second = LocalResumeStore(openDatabase: () async => secondDatabase);
      final savedBeforeUpgrade = File(
        '${directory.path}/pending-before-upgrade.json',
      );
      if (phase == 'prepare') {
        expect(await firstDatabase.read(account), isNull);
        expect(await secondDatabase.read(account), isNull);
        await first.write(account, snapshot('first', 900));
        await second.write(account, snapshot('second', 100));
        for (final entry in [(first, 'first'), (second, 'second')]) {
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
        await RecordTransport(second).synchronize(session, client);
        await RecordTransport(first).synchronize(session, client);
        await RecordTransport(second).synchronize(session, client);
        expect(await first.conflicts(account), hasLength(1));
        final deleted = (await second.read(account))!;
        second.acceptSnapshot(account, deleted);
        (deleted['bookmarks'] as List).removeWhere(
          (value) => value['id'] == 'first',
        );
        (deleted['history'] as List).removeWhere(
          (value) => value['id'] == 'history-first',
        );
        await second.write(account, deleted);
        await RecordTransport(second).synchronize(session, client);
        final offline = (await first.read(account))!;
        first.acceptSnapshot(account, offline);
        (offline['bookmarks'] as List).add(
          (snapshot('pending', 500)['bookmarks'] as List).single,
        );
        await first.write(account, offline);
        final saved = (await firstDatabase.read(account))!;
        final journal = (jsonDecode(saved) as Map)['sync'] as Map;
        expect(journal['pending'], hasLength(1));
        await savedBeforeUpgrade.writeAsString(saved);
      } else {
        expect(phase, 'verify');
        final saved = (await firstDatabase.read(account))!;
        expect(saved, await savedBeforeUpgrade.readAsString());
        expect((jsonDecode(saved) as Map)['sync']['pending'], hasLength(1));
        await RecordTransport(first).synchronize(session, client);
        final after = (await first.read(account))!;
        expect(
          (after['bookmarks'] as List).map((value) => value['id']),
          unorderedEquals(['second', 'pending']),
        );
        expect((after['history'] as List).map((value) => value['id']), [
          'history-second',
        ]);
        expect((await first.reading.read(account))!['bookmarks'], hasLength(2));
        final conflict = (await first.conflicts(account)).entries.single;
        expect(
          conflict.value.map(
            (action) => (action.value!.position as AudioPosition).milliseconds,
          ),
          unorderedEquals([900, 100]),
        );
        final chosen = conflict.value.firstWhere(
          (action) =>
              (action.value!.position as AudioPosition).milliseconds == 100,
        );
        await first.resolve(account, conflict.key, chosen.identity);
        await RecordTransport(first).synchronize(session, client);
        await RecordTransport(second).synchronize(session, client);
        expect(await first.conflicts(account), isEmpty);
        expect(await second.conflicts(account), isEmpty);
        expect((await first.read(account))!['bookmarks'], hasLength(4));
        final firstAudio = (await first.read(account))!;
        final secondAudio = (await second.read(account))!;
        expect(
          secondAudio['bookmarks'],
          unorderedEquals(firstAudio['bookmarks'] as List),
        );
        expect(
          secondAudio['history'],
          unorderedEquals(firstAudio['history'] as List),
        );
        expect(secondAudio['resumes'], firstAudio['resumes']);
        expect((firstAudio['resumes'] as Map)['book'][0]['milliseconds'], 100);
        final firstReading = (await first.reading.read(account))!;
        final secondReading = (await second.reading.read(account))!;
        expect(
          secondReading['bookmarks'],
          unorderedEquals(firstReading['bookmarks'] as List),
        );
        expect(secondReading['resumes'], firstReading['resumes']);
        final committed =
            (jsonDecode((await firstDatabase.read(account))!) as Map)['sync']
                as Map;
        expect(committed['pending'], isEmpty);
        await RecordTransport(first).synchronize(session, client);
        expect((await first.read(account))!['bookmarks'], hasLength(4));
      }
      await firstDatabase.checkInvariants();
      await secondDatabase.checkInvariants();
    },
    skip: fixture == null || phase == null
        ? 'Run tool/plugin/prove.py in the pinned shells.'
        : false,
  );
}
