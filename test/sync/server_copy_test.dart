import 'dart:convert';
import 'dart:io';

import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../playback/incremental_save_test.dart' show bookmark;
import 'fixture.dart';

// Damage that changes a saved action but leaves it valid goes unseen until
// a sync meets the server's copy of the same action. The server's copy was
// uploaded before the damage, so it wins. The damaged copy is kept aside.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  for (final durable in [false, true]) {
    group(durable ? 'SQLite' : 'preferences', () {
      late SyncFixture fixture;
      late String account;
      String? path;
      late RecordDatabase? database;
      late LocalResumeStore records;
      final record = jsonEncode(['audio', 'bookmarks', 'mark']);

      LocalResumeStore storeOver() => LocalResumeStore(
        openDatabase: durable ? () async => database! : null,
      );

      /// Drops what the app held in memory and starts again from storage.
      Future<void> restart() async {
        if (durable) {
          await database!.close();
          database = await RecordDatabase.open(
            factory: databaseFactoryFfi,
            path: path,
          );
        }
        records = storeOver();
      }

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        database = null;
        if (durable) {
          final directory = await Directory.systemTemp.createTemp(
            'bookfin-server-copy-',
          );
          addTearDown(() => directory.delete(recursive: true));
          path = '${directory.path}/records.sqlite';
          database = await RecordDatabase.open(
            factory: databaseFactoryFfi,
            path: path,
          );
          addTearDown(() => database!.close());
        }
        fixture = await SyncFixture.open();
        addTearDown(fixture.close);
        account = fixture.session.scope.key;
        records = storeOver();
      });

      Future<SyncReport> sync() =>
          records.synchronize(fixture.session, fixture.client);

      /// Changes the saved copy of the action of the bookmark `mark` to the
      /// title [title], keeps it valid, and sets the discovery cursor to
      /// [cursor] and its upload state to [pending], as damage that the
      /// store cannot see would.
      Future<void> damage({
        required String title,
        int? cursor,
        bool? pending,
      }) async {
        await restart();
        if (durable) {
          final sql = await databaseFactoryFfi.openDatabase(
            path!,
            options: OpenDatabaseOptions(singleInstance: false),
          );
          final row = (await sql.query('record_actions')).singleWhere(
            (row) =>
                (jsonDecode(row['payload'] as String) as Map)['record'] ==
                record,
          );
          final action = jsonDecode(row['payload'] as String) as Map;
          action['value']['title'] = title;
          await sql.update(
            'record_actions',
            {
              'payload': jsonEncode(action),
              if (pending != null) 'pending': pending ? 1 : 0,
            },
            where: 'identity = ?',
            whereArgs: [row['identity']],
          );
          if (cursor != null) {
            await sql.update('record_accounts', {'cursor': cursor});
          }
          await sql.close();
        } else {
          final preferences = await SharedPreferences.getInstance();
          final key = 'bookfin.playback.v1.$account';
          final saved = jsonDecode(preferences.getString(key)!) as Map;
          final sync = saved['sync'] as Map;
          final action = (sync['actions'] as List).cast<Map>().singleWhere(
            (action) => action['record'] == record,
          );
          action['value']['title'] = title;
          final identity = RecordJournal.identity(action.cast());
          if (pending == true) {
            sync['pending'] = [...sync['pending'] as List, identity];
          }
          if (cursor != null) sync['cursor'] = cursor;
          await preferences.setString(key, jsonEncode(saved));
        }
        await restart();
      }

      Future<String?> savedTitle() async {
        final saved = await records.read(account);
        final marks = (saved!['bookmarks'] as List).cast<Map>();
        return marks.singleWhere((mark) => mark['id'] == 'mark')['title']
            as String?;
      }

      /// The damaged copies that the store kept aside, as text.
      Future<List<String>> keptAside() async {
        if (durable) {
          final sql = await databaseFactoryFfi.openDatabase(
            path!,
            options: OpenDatabaseOptions(singleInstance: false),
          );
          addTearDown(sql.close);
          return [
            for (final row in await sql.query('set_aside_record_actions'))
              row['payload'] as String,
          ];
        }
        final preferences = await SharedPreferences.getInstance();
        return [
          for (final key in preferences.getKeys())
            if (key.startsWith('bookfin.damaged-records.v1.'))
              preferences.getString(key)!,
        ];
      }

      test('a received action whose saved copy differs takes the server copy, and sync continues', () async {
        final remote = RecordJournal(account, 'remote');
        remote.change(record, bookmark('mark', title: 'Server title'));
        remote.change(
          jsonEncode(['audio', 'bookmarks', 'later']),
          bookmark('later'),
        );
        fixture.publish(remote);
        await sync();
        await damage(title: 'Damaged title', cursor: 0);

        final report = await sync();
        expect(report.replaced, 1);
        expect(report.stale.listening, isTrue);
        expect(await savedTitle(), 'Server title');
        expect(
          (await keptAside()).any((text) => text.contains('Damaged title')),
          isTrue,
        );
        expect((await sync()).replaced, 0);
        await records.checkInvariants();
      });

      test('an upload that the server refuses because it holds another copy takes the server copy', () async {
        await records.write(account, {
          'bookmarks': [bookmark('mark', title: 'Uploaded title')],
        });
        await sync();
        await damage(title: 'Damaged title', pending: true);

        final report = await sync();
        expect(report.replaced, 1);
        expect(await savedTitle(), 'Uploaded title');
        expect(
          (await keptAside()).any((text) => text.contains('Damaged title')),
          isTrue,
        );
        expect((await sync()).replaced, 0);
        await records.checkInvariants();
      });

      test(
        'a place saved after the server copy won survives a restart',
        () async {
          final remote = RecordJournal(account, 'remote');
          remote.change(record, bookmark('mark', title: 'Server title'));
          fixture.publish(remote);
          await sync();
          await damage(title: 'Damaged title', cursor: 0);
          await sync();

          await records.write(account, {
            ...?await records.read(account),
            'resumes': {
              'edition': [
                {
                  'source': 'source',
                  'revision': 'revision',
                  'sources': '[["source","revision"]]',
                  'milliseconds': 20000,
                  'pendingOffline': false,
                },
              ],
            },
          });
          await restart();
          final saved = (await records.read(account))!;
          expect(
            (((saved['resumes'] as Map)['edition'] as List).single
                as Map)['milliseconds'],
            20000,
          );
          expect(await savedTitle(), 'Server title');
        },
      );

      if (durable) {
        test('a kill while the server copy replaces the damaged one leaves the saved rows, and the next sync replaces it', () async {
          final remote = RecordJournal(account, 'remote');
          remote.change(record, bookmark('mark', title: 'Server title'));
          fixture.publish(remote);
          await sync();
          await damage(title: 'Damaged title', cursor: 0);
          final sql = await databaseFactoryFfi.openDatabase(
            path!,
            options: OpenDatabaseOptions(singleInstance: false),
          );
          await sql.execute(
            "CREATE TRIGGER cut AFTER INSERT ON record_actions BEGIN SELECT RAISE(ABORT, 'killed'); END",
          );
          await expectLater(sync(), throwsA(anything));
          await sql.execute('DROP TRIGGER cut');
          await sql.close();

          await restart();
          expect(await savedTitle(), 'Damaged title');
          expect((await sync()).replaced, 1);
          expect(await savedTitle(), 'Server title');
        });
      }
    });
  }
}
