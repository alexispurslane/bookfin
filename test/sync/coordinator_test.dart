import 'dart:async';
import 'dart:convert';

import 'package:bookfin/app/account_binding.dart';
import 'package:bookfin/catalog/controller.dart';

import 'package:bookfin/catalog/jellyfin.dart';

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
import '../catalog/controller_test.dart'
    show FixtureClient, MemoryCredentials, MemoryCatalogStore;
import 'fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  for (final durable in [false, true]) {
    group(durable ? 'SQLite' : 'preferences', () {
      RecordDatabase? database;
      Directory? directory;
      late SyncFixture fixture;
      late LocalResumeStore records;
      late audio.TestEngine engine;
      late audio.LocalFiles downloads;
      late Playback player;
      late RecordSync sync;

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        if (durable) {
          directory = await Directory.systemTemp.createTemp(
            'bookfin-coordinator-',
          );
          database = await RecordDatabase.open(
            factory: databaseFactoryFfi,
            path: '${directory!.path}/records.sqlite',
          );
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
        sync = RecordSync(records: records)..bind(fixture.session);
        await sync.synchronize();
        expect(sync.conflicts, hasLength(1));
        expect(player.position!.milliseconds, 900);
      });

      tearDown(() async {
        sync.dispose();
        await player.close();
        downloads.dispose();
        await fixture.close();
        await database?.close();
        await directory?.delete(recursive: true);
      });

      Future<int> savedMilliseconds() async {
        final saved = (await records.read(fixture.session.scope.key))!;
        return ((saved['resumes'] as Map)[audio.recording.id] as List)
                .single['milliseconds']
            as int;
      }

      test('a saved conflict choice remains usable while the credential is rejected', () async {
        fixture.session.rejectCredential();
        final conflict = sync.conflicts.entries.single;
        final chosen = conflict.value.singleWhere(
          (action) => action['value']['milliseconds'] == 900,
        );
        final requests = fixture.requests;
        await sync.resolve(conflict.key, RecordJournal.identity(chosen));
        expect(await savedMilliseconds(), 900);
        expect(sync.conflicts, isEmpty);
        expect(
          await records.pendingUploads(fixture.session.scope.key),
          isNotEmpty,
        );
        expect(fixture.requests, requests);
      });

      test('401 suspends sync while local actions remain durable and replacement uploads them', () async {
        fixture.rejectCredential = true;
        await sync.syncNow();
        final requests = fixture.requests;
        expect(fixture.session.needsSignIn, isTrue);
        engine.emit(0, 3400);
        await player.pause();
        await player.flush();
        sync.suspend();
        sync.resume();
        await sync.synchronize();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(fixture.requests, requests);
        expect(player.position!.milliseconds, 3400);
        expect(
          (await records.pendingUploads(fixture.session.scope.key))
              .where((action) => action['value']?['milliseconds'] == 3400),
          isNotEmpty,
        );
        fixture.rejectCredential = false;
        final replacement = JellyfinSession.fromJson({
          ...fixture.session.toJson(),
          'needsSignIn': false,
        });
        sync.bind(replacement);
        await sync.synchronize();
        expect(
          await records.pendingUploads(fixture.session.scope.key),
          isEmpty,
        );
        expect(player.position!.milliseconds, 3400);
        sync.checkInvariants();
      });

      test(
        'same-token sign-in rebinds sync before an obsolete rejection',
        () async {
          final replacement = JellyfinSession.fromJson(
            fixture.session.toJson(),
          );
          final client = FixtureClient(fixture.session.scope.server)
            ..pendingSignIn = (Completer<JellyfinSession>()
              ..complete(replacement));
          final catalog = CatalogController(
            credentials: MemoryCredentials()..value = fixture.session,
            store: MemoryCatalogStore(),
            clientFactory: (_, _) => client,
          );
          addTearDown(client.close);
          addTearDown(catalog.dispose);
          await catalog.restore();
          final binding = AccountBinding(catalog: catalog, sync: sync);
          addTearDown(binding.dispose);
          expect(
            await catalog.connect(
              fixture.session.scope.server.toString(),
              'alice',
              'password',
            ),
            isTrue,
          );
          await sync.synchronize();
          fixture.session.rejectCredential();
          engine.emit(0, 4500);
          await player.pause();
          await player.flush();
          final requests = fixture.requests;
          expect(
            await records.pendingUploads(replacement.scope.key),
            isNotEmpty,
          );
          await sync.syncNow();
          expect(fixture.requests, greaterThan(requests));
          expect(await records.pendingUploads(replacement.scope.key), isEmpty);
          expect(player.position!.milliseconds, 4500);
          expect(catalog.session!.needsSignIn, isFalse);
          binding.checkInvariants();
          sync.checkInvariants();
        },
      );

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
