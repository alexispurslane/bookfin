import 'dart:async';
import 'dart:convert';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/record_codec.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/sync/transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../playback/held_engine.dart';
import '../playback/playback_test.dart' as audio;
import 'batch_api_test.dart' show BatchApi, ConnectedTransport;
import 'event_upload_test.dart' show otherBook, otherEdition;
import 'phone.dart';

// These waits detect a dependency on a gate that the test has not released.
// They are deadlock watchdogs, not device latency requirements.
const _deadline = Duration(seconds: 5);

/// Delays or fails only the owner's next storage boundary. Registration,
/// snapshot acceptance, journaling and persistence remain the real store's.
class _Records extends LocalResumeStore {
  _Records({super.openDatabase});
  Completer<void>? readStarted;
  Completer<void>? readRelease;
  Completer<void>? writeStarted;
  Completer<void>? writeRelease;
  Completer<void>? nextSaved;
  Object? readFailure;
  bool failWrites = false;

  void holdRead() {
    readStarted = Completer<void>();
    readRelease = Completer<void>();
  }

  void holdWrite() {
    writeStarted = Completer<void>();
    writeRelease = Completer<void>();
  }

  @override
  Future<Map<String, dynamic>?> read(String accountKey) async {
    if (readFailure case final failure?) throw failure;
    final saved = await super.read(accountKey);
    if (readStarted case final started? when !started.isCompleted) {
      started.complete();
      await readRelease!.future;
    }
    return saved;
  }

  @override
  Future<void> save(String accountKey, ListeningChanges changes) async {
    if (writeStarted case final started? when !started.isCompleted) {
      started.complete();
      await writeRelease!.future;
    }
    if (failWrites) throw Exception('storage unavailable');
    await super.save(accountKey, changes);
    if (nextSaved case final saved? when !saved.isCompleted) saved.complete();
  }

  void release() {
    for (final gate in [readRelease, writeRelease]) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    readFailure = null;
    failWrites = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final durable in [false, true]) {
    group(durable ? 'SQLite' : 'preferences', () {
      late _Records records;
      late HeldEngine engine;
      late audio.LocalFiles downloads;
      late Playback player;
      late BatchApi api;
      late JellyfinClient client;
      late JellyfinSession session;
      late RecordSync sync;
      late RecordJournal remote;
      Phone? phone;
      String getAccount() => session.scope.key;
      LocalResumeStore reopened() => LocalResumeStore(
        openDatabase: durable ? () async => phone!.database : null,
      );

      void publish() {
        for (final action in remote.uploads) {
          api.put(RecordJournal.identity(action), jsonEncode(action));
        }
      }

      void publishBookmark(String id) {
        remote.change(jsonEncode(['audio', 'bookmarks', id]), {
          ...player.bookmarks.first.toJson(),
          'id': id,
          'title': id,
        });
        publish();
      }

      Future<void> receive() =>
          RecordTransport(records).synchronize(session, client);

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        if (durable) phone = await Phone.open('playback-refresh');
        records = _Records(
          openDatabase: durable ? () async => phone!.database : null,
        );
        engine = HeldEngine();
        downloads = audio.LocalFiles();
        player = Playback(downloads: downloads, engine: engine, store: records);
        api = BatchApi();
        session = JellyfinSession(
          scope: audio.account().scope,
          token: 'test',
          username: 'Alice',
          canDownload: true,
        );
        client = JellyfinClient(
          session.scope.server,
          deviceId: 'refresh-test',
          transport: api,
        );
        await player.bind(session, [audio.title, otherBook]);
        await player.open(audio.title, audio.recording);
        await player.seekEdition(11000);
        await player.addBookmark(title: 'Local');
        sync = RecordSync(
          records: records,
          transport: ConnectedTransport(records, client),
        )..suspend();
        sync.bind(session);
        await sync.synchronize();
        remote = RecordJournal(getAccount(), 'remote')
          ..receive(
            api.objects.values.map(
              (object) =>
                  jsonDecode(object['Payload'] as String)
                      as Map<String, dynamic>,
            ),
          );
      });

      tearDown(() async {
        sync.dispose();
        records.release();
        engine.release();
        await player.close();
        downloads.dispose();
        client.close();
      });

      for (final command in HeldCommand.values) {
        for (final rejected in [false, true]) {
          test(
            'two ${rejected ? 'rejected-upload' : 'complete'} exchanges adopt listening records during held ${command.name}',
            () async {
              if (rejected) {
                await player.addBookmark(title: 'Pending upload');
                final pending = (await records.pendingUploads(getAccount()))
                    .single;
                final id = RecordJournal.identity(pending);
                api.put(id, jsonEncode(pending))['Deleted'] = true;
                api.reject = id;
                api.rejectedStatus = 410;
              }
              final lastSync = sync.lastSyncNotifier.value!.synced;
              final confirmed = player.position;
              final undo = player.undoNotifier.value;
              engine.held = command;
              var finished = false;
              final running = switch (command) {
                HeldCommand.load => player.open(otherBook, otherEdition),
                HeldCommand.seek => player.seekEdition(78000),
                HeldCommand.pause => player.pause(),
              }.then((_) => finished = true);
              await engine.entered.future;
              Future<void>? syncing;
              try {
                for (var pass = 1; pass <= 2; pass++) {
                  publishBookmark('remote-$pass');
                  remote.change(
                    jsonEncode(['audio', 'history', 'move-$pass']),
                    {...player.history.first.toJson(), 'id': 'move-$pass'},
                  );
                  // A different edition's resume proves adoption without asking
                  // the current decoder to move or replacing its confirmed place.
                  remote.change(resumeRecordAddress(otherEdition), {
                    'edition': 'other',
                    'sources': editionSources(otherEdition),
                    'source': audio.first.key,
                    'revision': 'r1',
                    'milliseconds': pass * 2000,
                    'pendingOffline': false,
                  });
                  publish();
                  remote.change(resumeRecordAddress(audio.recording), {
                    'edition': 'recording',
                    'sources': editionSources(audio.recording),
                    'source': audio.first.key,
                    'revision': 'r1',
                    'milliseconds': pass * 20000,
                    'pendingOffline': false,
                  });
                  publish();
                  final pages = api.pages;
                  syncing = sync.syncNow();
                  await syncing.timeout(_deadline);
                  expect(api.pages, greaterThan(pages));
                  expect(finished, isFalse);
                  expect(player.position, same(confirmed));
                  expect(engine.milliseconds, 11000);
                  expect(player.progress(otherEdition)?.elapsedMs, pass * 2000);
                  expect(player.undoNotifier.value?.action.id, undo?.action.id);
                  expect(
                    player.bookmarks.map((mark) => mark.id),
                    contains('remote-$pass'),
                  );
                  expect(
                    player.history.map((event) => event.id),
                    contains('move-$pass'),
                  );
                  expect(records.staleNotifier(getAccount()).value, isFalse);
                  final saved = (await reopened().read(getAccount()))!;
                  expect(
                    (saved['bookmarks'] as List).map((mark) => mark['id']),
                    contains('remote-$pass'),
                  );
                  expect(
                    (saved['history'] as List).map((event) => event['id']),
                    contains('move-$pass'),
                  );
                  expect(
                    saved['resumes']['other'].single['milliseconds'],
                    pass * 2000,
                  );
                  expect(
                    saved['resumes']['recording'].single['milliseconds'],
                    pass * 20000,
                  );
                  expect(
                    sync.lastSyncNotifier.value?.failure,
                    rejected ? RecordSyncFailure.uploadRejected : null,
                  );
                  if (rejected) {
                    expect(sync.lastSyncNotifier.value?.synced, lastSync);
                  }
                }
              } finally {
                records.nextSaved = Completer<void>();
                engine.release();
                await running;
                // Load schedules its save but does not await storage. Observe
                // that save directly, without making flush or sync do its work.
                await records.nextSaved!.future.timeout(_deadline);
                await syncing;
              }
              final saved = (await reopened().read(getAccount()))!;
              expect(
                (saved['bookmarks'] as List).map((mark) => mark['id']),
                containsAll(['remote-1', 'remote-2']),
              );
              expect(
                saved['resumes'][command == HeldCommand.load
                        ? 'other'
                        : 'recording']
                    .single['milliseconds'],
                command == HeldCommand.seek
                    ? 18000
                    : command == HeldCommand.load
                    ? 0
                    : 40000,
              );
              if (command != HeldCommand.load) {
                expect(
                  (saved['history'] as List).where(
                    (event) => event['kind'] == command.name,
                  ),
                  hasLength(command == HeldCommand.seek ? 4 : 1),
                );
              }
              player.checkInvariants();
              if (durable) {
                await player.close();
                await phone!.restart();
                final restarted = (await phone!.store.read(getAccount()))!;
                expect(
                  (restarted['bookmarks'] as List).map((mark) => mark['id']),
                  containsAll(['remote-1', 'remote-2']),
                );
                expect(
                  (restarted['history'] as List).map((event) => event['id']),
                  containsAll(['move-1', 'move-2']),
                );
              }
            },
          );
        }
      }

      test('an unrestored account allows two exchanges while binding waits for audio', () async {
        engine.held = HeldCommand.seek;
        final seeking = player.seekEdition(78000);
        await engine.entered.future;
        final leaving = player.bind(audio.account(user: 'bob'), [audio.title]);
        final returning = player.bind(session, [audio.title, otherBook]);
        try {
          // The account is A again, but its restoration still waits on A's
          // obsolete seek. Build remote records from the durable bookmark.
          final saved = (await reopened().read(getAccount()))!;
          for (var pass = 1; pass <= 2; pass++) {
            remote.change(jsonEncode(['audio', 'bookmarks', 'return-$pass']), {
              ...Map<String, dynamic>.from(
                (saved['bookmarks'] as List).first as Map,
              ),
              'id': 'return-$pass',
              'title': 'return-$pass',
            });
            publish();
            await sync.syncNow().timeout(_deadline);
            expect(player.position, isNull);
            expect(player.bookmarks, isEmpty);
            expect(records.staleNotifier(getAccount()).value, isTrue);
            expect(
              (await reopened().read(getAccount()))!['bookmarks'],
              hasLength(pass + 1),
            );
          }
        } finally {
          engine.release();
          await seeking;
          await leaving;
          await returning;
          await sync.synchronize();
        }
        expect(player.position?.milliseconds, 11000);
        expect(
          player.bookmarks.map((mark) => mark.id),
          containsAll(['return-1', 'return-2']),
        );
        expect(
          player.history.where((event) => event.after.milliseconds == 18000),
          isEmpty,
        );
      });

      test('a late recovery refresh cannot replace the newer snapshot adopted by sync', () async {
        publishBookmark('first');
        await receive();
        records.holdRead();
        final recovering = sync.recoverKept();
        await records.readStarted!.future;
        try {
          publishBookmark('second');
          await sync.syncNow().timeout(_deadline);
          expect(
            player.bookmarks.map((mark) => mark.id),
            containsAll(['first', 'second']),
          );
          records.readRelease!.complete();
          await recovering;
          expect(
            player.bookmarks.map((mark) => mark.id),
            containsAll(['first', 'second']),
          );
          expect(records.staleNotifier(getAccount()).value, isFalse);
          player.checkInvariants();
        } finally {
          records.release();
          await recovering;
          await sync.synchronize();
        }
      });

      test('a held read cannot replace records after leaving and returning to the account', () async {
        publishBookmark('before-return');
        await receive();
        records.holdRead();
        final refreshing = player.refreshPersonalRecords();
        await records.readStarted!.future;
        try {
          await player
              .bind(audio.account(user: 'bob'), [audio.title])
              .timeout(_deadline);
          await player
              .bind(session, [audio.title, otherBook])
              .timeout(_deadline);
          publishBookmark('after-return');
          await receive();
          records.readRelease!.complete();
          await refreshing;
          expect(
            player.bookmarks.map((mark) => mark.id),
            contains('before-return'),
          );
          expect(
            player.bookmarks.map((mark) => mark.id),
            isNot(contains('after-return')),
          );
          expect(records.staleNotifier(getAccount()).value, isTrue);
          await records.refreshWriters(getAccount());
          expect(
            player.bookmarks.map((mark) => mark.id),
            contains('after-return'),
          );
          expect(records.staleNotifier(getAccount()).value, isFalse);
        } finally {
          records.release();
          await refreshing;
        }
      });

      test('received deletion clears Undo and bookmarks without losing the held seek', () async {
        final historyId = player.undoNotifier.value!.action.id;
        final bookmarkId = player.bookmarks.single.id;
        engine.held = HeldCommand.seek;
        final seeking = player.seekEdition(78000);
        await engine.entered.future;
        remote.change(jsonEncode(['audio', 'history', historyId]), null);
        remote.change(jsonEncode(['audio', 'bookmarks', bookmarkId]), null);
        publish();
        try {
          await sync.syncNow().timeout(_deadline);
          expect(player.undoNotifier.value, isNull);
          expect(player.bookmarks, isEmpty);
          expect(
            player.history.map((event) => event.id),
            isNot(contains(historyId)),
          );
          expect(player.position?.milliseconds, 11000);
        } finally {
          engine.release();
          await seeking;
          await sync.synchronize();
        }
        expect(player.undoNotifier.value!.action.before.milliseconds, 11000);
        expect(player.position?.milliseconds, 18000);
        final saved = (await reopened().read(getAccount()))!;
        expect(saved['bookmarks'], isEmpty);
        expect(
          (saved['history'] as List).map((event) => event['id']),
          isNot(contains(historyId)),
        );
        expect(
          (saved['history'] as List)
              .where((event) => event['kind'] == 'seek')
              .single['after']['milliseconds'],
          18000,
        );
        player.checkInvariants();
      });

      test('an adopted history keeps its Undo action usable', () async {
        final id = player.undoNotifier.value!.action.id;
        publishBookmark('remote');
        await sync.syncNow();
        expect(
          player.undoNotifier.value!.action,
          same(player.history.singleWhere((event) => event.id == id)),
        );
        player.checkInvariants();
        await player.undoSeek();
        expect(player.position?.milliseconds, 0);
        expect(
          player.history.where((event) => event.kind == HistoryAction.undo),
          hasLength(1),
        );
        expect(
          (await reopened().read(getAccount()))!['history'],
          hasLength(player.history.length),
        );
      });

      test(
        'a held read cannot adopt or accept a snapshot after close',
        () async {
          publishBookmark('after-close');
          await receive();
          records.holdRead();
          final refreshing = player.refreshPersonalRecords();
          await records.readStarted!.future;
          final closing = player.close();
          try {
            await closing.timeout(_deadline);
            records.readRelease!.complete();
            await refreshing;
            expect(engine.closed, isTrue);
            expect(
              player.bookmarks.map((mark) => mark.id),
              isNot(contains('after-close')),
            );
            expect(records.staleNotifier(getAccount()).value, isTrue);
            await player.refreshPersonalRecords();
            expect(records.staleNotifier(getAccount()).value, isTrue);
          } finally {
            records.release();
            await refreshing;
            await closing;
          }
        },
      );

      test('a local deletion during a held read rejects it and retries without losing remote records', () async {
        final local = player.bookmarks.single.id;
        publishBookmark('remote');
        await receive();
        records.holdRead();
        final refreshing = player.refreshPersonalRecords();
        await records.readStarted!.future;
        records.holdWrite();
        final deleting = player.deleteBookmark(local);
        try {
          await records.writeStarted!.future.timeout(_deadline);
          records.readRelease!.complete();
          await refreshing;
          expect(player.bookmarks, isEmpty);
          expect(records.staleNotifier(getAccount()).value, isTrue);
          records.writeRelease!.complete();
          await deleting;
          await records.refreshWriters(getAccount());
          expect(player.bookmarks.map((mark) => mark.id), ['remote']);
          expect(records.staleNotifier(getAccount()).value, isFalse);
          expect(
            (await reopened().read(getAccount()))!['bookmarks'].single['id'],
            'remote',
          );
        } finally {
          records.release();
          await refreshing;
          await deleting;
        }
      });

      test(
        'refresh waits for a local save but not the held seek after it',
        () async {
          publishBookmark('remote');
          await receive();
          records.holdWrite();
          final saving = player.addBookmark(title: 'Saving');
          await records.writeStarted!.future;
          engine.held = HeldCommand.seek;
          final seeking = player.seekEdition(78000);
          var refreshed = false;
          final refreshing = player.refreshPersonalRecords().then(
            (_) => refreshed = true,
          );
          try {
            await pumpEventQueue();
            expect(refreshed, isFalse);
            records.writeRelease!.complete();
            await saving;
            await engine.entered.future;
            await refreshing.timeout(_deadline);
            expect(engine.released.isCompleted, isFalse);
            expect(
              player.bookmarks.map((mark) => mark.title),
              unorderedEquals(['Local', 'Saving', 'remote']),
            );
            expect(player.position?.milliseconds, 11000);
          } finally {
            records.release();
            engine.release();
            await saving;
            await seeking;
            await refreshing;
          }
        },
      );

      test('failed pending writes reject refresh until retry preserves both local and remote records', () async {
        records.failWrites = true;
        await player.addBookmark(title: 'Pending');
        publishBookmark('remote');
        await receive();
        engine.held = HeldCommand.seek;
        final seeking = player.seekEdition(78000);
        await engine.entered.future;
        try {
          await records.refreshWriters(getAccount()).timeout(_deadline);
          expect(player.unsavedChanges, isTrue);
          expect(
            player.bookmarks.map((mark) => mark.title),
            unorderedEquals(['Local', 'Pending']),
          );
          expect(records.staleNotifier(getAccount()).value, isTrue);
          records.failWrites = false;
          await player.flush();
          await records.refreshWriters(getAccount()).timeout(_deadline);
          expect(
            player.bookmarks.map((mark) => mark.title),
            unorderedEquals(['Local', 'Pending', 'remote']),
          );
          expect(player.unsavedChanges, isFalse);
          expect(records.staleNotifier(getAccount()).value, isFalse);
          expect(
            (await reopened().read(getAccount()))!['bookmarks'],
            hasLength(3),
          );
        } finally {
          records.release();
          engine.release();
          await seeking;
        }
      });

      for (final bug in [false, true]) {
        test(
          'a refresh ${bug ? 'Error propagates' : 'Exception reports failure'} while a seek stays held',
          () async {
            publishBookmark('remote');
            engine.held = HeldCommand.seek;
            final seeking = player.seekEdition(78000);
            await engine.entered.future;
            final failure = bug
                ? StateError('read bug')
                : Exception('read unavailable');
            records.readFailure = failure;
            try {
              final syncing = sync.syncNow();
              if (bug) {
                await expectLater(
                  syncing.timeout(_deadline),
                  throwsA(same(failure)),
                );
              } else {
                await syncing.timeout(_deadline);
                expect(
                  sync.lastSyncNotifier.value?.failure,
                  RecordSyncFailure.refreshFailed,
                );
              }
              expect(player.playing, isTrue);
              expect(player.message, isNull);
              expect(engine.released.isCompleted, isFalse);
              expect(records.staleNotifier(getAccount()).value, isTrue);
              records.readFailure = null;
              await sync.syncNow().timeout(_deadline);
              expect(
                player.bookmarks.map((mark) => mark.id),
                contains('remote'),
              );
              expect(sync.lastSyncNotifier.value?.failure, isNull);
            } finally {
              records.release();
              engine.release();
              await seeking;
              await sync.synchronize();
            }
          },
        );
      }
    });
  }
}
