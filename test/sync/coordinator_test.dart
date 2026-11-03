import 'dart:convert';
import 'dart:io';

import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/playback/database.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../playback/playback_test.dart' as audio;
import 'fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  for (final durable in [false, true]) {
    group(durable ? 'SQLite' : 'preferences', () {
      RecordDatabase? database;
      late SyncFixture fixture;
      late LocalResumeStore records;
      late audio.TestEngine engine;
      late audio.LocalFiles downloads;
      late Playback player;
      late RecordSync sync;

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        if (durable) {
          final directory = await Directory.systemTemp.createTemp(
            'bookfin-coordinator-',
          );
          addTearDown(() => directory.delete(recursive: true));
          database = await RecordDatabase.open(
            factory: databaseFactoryFfi,
            path: '${directory.path}/records.sqlite',
          );
          addTearDown(() => database!.close());
        }
        fixture = await SyncFixture.open();
        records = LocalResumeStore(
          openDatabase: durable ? () async => database! : null,
        );
        engine = audio.TestEngine();
        downloads = audio.LocalFiles();
        player = Playback(downloads: downloads, engine: engine, store: records);
        await player.bind(fixture.session, [audio.title]);
        await player.open(audio.title, audio.recording, autoplay: false);
        await player.seekEdition(900);
        await player.flush();
        final preferences = await SharedPreferences.getInstance();
        final saved = jsonDecode(
          durable
              ? (await database!.read(fixture.session.scope.key))!
              : preferences.getString(
                  'bookfin.playback.v1.${fixture.session.scope.key}',
                )!,
        ) as Map;
        final action = (saved['sync']['actions'] as List).lastWhere(
          (action) =>
              (jsonDecode(action['record'] as String) as List)[1] == 'resumes',
        ) as Map;
        final remote = RecordJournal(fixture.session.scope.key, 'remote');
        remote.change(action['record'] as String, {
          ...Map<String, dynamic>.from(action['value'] as Map),
          'milliseconds': 100,
        });
        fixture.publish(remote);
        sync = RecordSync(records: records, playback: player)
          ..bind(fixture.session);
        await sync.synchronize();
        expect(sync.conflicts, hasLength(1));
        expect(player.position!.milliseconds, 900);
      });

      tearDown(() async {
        sync.dispose();
        await player.close();
        downloads.dispose();
        await fixture.close();
      });

      Future<int> savedMilliseconds() async {
        final saved = (await records.read(fixture.session.scope.key))!;
        return ((saved['resumes'] as Map)[audio.recording.id] as List)
                .single['milliseconds']
            as int;
      }

      for (final chosen in [900, 100]) {
        test(
          'choosing the $chosen ms resume survives coordinator flushes without moving paused audio',
          () async {
            final conflict = sync.conflicts.entries.single;
            final selected = conflict.value.singleWhere(
              (action) => action['value']['milliseconds'] == chosen,
            );
            await expectLater(
              sync.resolve(conflict.key, RecordJournal.identity(selected)),
              completes,
            );
            expect(player.position!.milliseconds, 900);
            expect(engine.milliseconds, 900);
            expect(await savedMilliseconds(), chosen);
            expect(sync.conflicts, isEmpty);
            expect(
              player.bookmarks.map((mark) => mark.position.milliseconds),
              unorderedEquals([900, 100]),
            );
            await sync.synchronize();
            await player.pause();
            await sync.synchronize();
            expect(await savedMilliseconds(), chosen);
            engine.emit(0, 1900);
            await player.flush();
            expect(await savedMilliseconds(), 1900);
          },
        );
      }

      test('a displayed conflict that changed before the tap gives a recoverable result', () async {
        final conflict = sync.conflicts.entries.single;
        final selected = conflict.value.singleWhere(
          (action) => action['value']['milliseconds'] == 100,
        );
        final identity = RecordJournal.identity(selected);
        await records.resolve(
          fixture.session.scope.key,
          conflict.key,
          identity,
        );
        await expectLater(sync.resolve(conflict.key, identity), completes);
        expect(sync.busy, isFalse);
        expect(sync.message, contains('changed'));
        expect(sync.conflicts, isEmpty);
        expect(await savedMilliseconds(), 100);
        expect(player.position!.milliseconds, 900);
      });
    });
  }
}
