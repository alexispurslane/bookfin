import 'dart:convert';
import 'dart:io';

import 'package:bookfin/sync/transport.dart';
import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../playback/incremental_save_test.dart' show bookmark;
import 'fixture.dart';

/// A reading bookmark of a remote device, as the reader saves one.
Map<String, dynamic> readingBookmark(String id) => {
  'id': id,
  'position': {
    'edition': 'book',
    'source': 'ebook',
    'revision': 'text-v1',
    'anchor': 'page-one',
  },
  'createdAt': '2026-11-07T12:00:00Z',
  'title': 'Remote reading mark',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  for (final durable in [false, true]) {
    group(durable ? 'SQLite' : 'preferences', () {
      late SyncFixture fixture;
      late LocalResumeStore records;
      late RecordJournal remote;
      late String account;

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        RecordDatabase? database;
        if (durable) {
          final directory = await Directory.systemTemp.createTemp(
            'bookfin-stale-domains-',
          );
          addTearDown(() => directory.delete(recursive: true));
          database = await RecordDatabase.open(
            factory: databaseFactoryFfi,
            path: '${directory.path}/records.sqlite',
          );
          addTearDown(() => database!.close());
        }
        fixture = await SyncFixture.open();
        addTearDown(fixture.close);
        records = LocalResumeStore(
          openDatabase: durable ? () async => database! : null,
        );
        account = fixture.session.scope.key;
        remote = RecordJournal(account, 'remote');
      });

      /// Playback and the reader each read the account and take in what
      /// the store handed them, as both do when they bind.
      Future<void> writersTakeIn({
        bool listening = true,
        bool reading = true,
      }) async {
        if (listening) {
          records.acceptSnapshot(account, await records.read(account));
        }
        if (reading) {
          records.reading.acceptSnapshot(
            account,
            await records.reading.read(account),
          );
        }
      }

      Future<({bool listening, bool reading})> sync() async {
        await RecordTransport(records)
            .synchronize(fixture.session, fixture.client);
        return (
          listening: records.staleNotifier(account).value,
          reading: records.reading.staleNotifier(account).value,
        );
      }

      test(
        'a sync that brings no new record leaves both writers current',
        () async {
          remote.change(jsonEncode(['audio', 'bookmarks', 'a']), bookmark('a'));
          fixture.publish(remote);
          await sync();
          await writersTakeIn();
          expect(await sync(), (listening: false, reading: false));
        },
      );

      test('a sync that brings back only this device\'s own uploads leaves both writers current', () async {
        await records.write(account, {
          'bookmarks': [bookmark('local')],
        });
        await writersTakeIn();
        expect(await sync(), (listening: false, reading: false));
        expect(await sync(), (listening: false, reading: false));
      });

      test('a sync that brings a remote listening bookmark marks only listening as behind', () async {
        await writersTakeIn();
        remote.change(jsonEncode(['audio', 'bookmarks', 'a']), bookmark('a'));
        fixture.publish(remote);
        expect(await sync(), (listening: true, reading: false));
      });

      test('a sync that brings a remote reading bookmark marks only reading as behind', () async {
        await writersTakeIn();
        remote.change(
          jsonEncode(['reading', 'bookmarks', 'r']),
          readingBookmark('r'),
        );
        fixture.publish(remote);
        expect(await sync(), (listening: false, reading: true));
      });

      test('listening stays behind until Playback takes in a read made after the change', () async {
        await writersTakeIn();
        final before = await records.read(account);
        remote.change(jsonEncode(['audio', 'bookmarks', 'a']), bookmark('a'));
        fixture.publish(remote);
        expect(await sync(), (listening: true, reading: false));
        // A refresh that read before the change and accepts late, or that
        // Playback discards because the user saved meanwhile, takes in
        // nothing.
        records.acceptSnapshot(account, before);
        expect(await sync(), (listening: true, reading: false));
        await records.read(account);
        expect(await sync(), (listening: true, reading: false));
        await writersTakeIn(reading: false);
        expect(await sync(), (listening: false, reading: false));
      });

      test('a remote record that a sync saved before it failed is still reported by the next sync', () async {
        await writersTakeIn();
        for (var index = 0; index < 6; index++) {
          remote.change(
            jsonEncode(['audio', 'bookmarks', 'a$index']),
            bookmark('a$index'),
          );
        }
        fixture.publish(remote);
        fixture.failDiscoveryAfter = 4;
        await expectLater(sync(), throwsA(anything));
        fixture.failDiscoveryAfter = null;
        expect(await sync(), (listening: true, reading: false));
        final saved = (await records.read(account))!;
        expect(saved['bookmarks'] as List, hasLength(6));
      });

      test('a choice between saved versions marks its domain as behind until the writer takes it in', () async {
        final record = jsonEncode(['audio', 'bookmarks', 'a']);
        final other = RecordJournal(account, 'other');
        remote.change(record, bookmark('a', title: 'Remote'));
        other.change(record, bookmark('a', title: 'Other'));
        fixture
          ..publish(remote)
          ..publish(other);
        await sync();
        await writersTakeIn();
        final chosen = (await records.conflicts(account))[record]!.first;
        expect(
          await records.resolve(
            account,
            record,
            RecordJournal.identity(chosen),
          ),
          isTrue,
        );
        expect(await sync(), (listening: true, reading: false));
        await writersTakeIn();
        expect(await sync(), (listening: false, reading: false));
      });
    });
  }
}
