import 'dart:async';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/native.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/record_codec.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../sync/phone.dart';
import '../sync/event_upload_test.dart' show otherBook, otherEdition;
import 'held_engine.dart';
import 'playback_test.dart' as audio;

class _Store extends LocalResumeStore {
  _Store({super.openDatabase});
  bool fail = false;
  Completer<void>? saveGate;
  Completer<void>? saveEntered;
  @override
  Future<void> save(String account, ListeningChanges changes) async {
    if (fail) throw Exception('disk full');
    if (saveGate != null) {
      if (!saveEntered!.isCompleted) saveEntered!.complete();
      await saveGate!.future;
    }
    return super.save(account, changes);
  }
}

class _Engine extends HeldEngine {
  bool failLoad = false;
  @override
  Future<void> load(List<Uri> sources, int fileIndex, int position) {
    if (failLoad) throw Exception('decoder load failed');
    return super.load(sources, fileIndex, position);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final sqlite in [false, true]) {
    group(sqlite ? 'SQLite' : 'preferences', () {
      late _Store store;
      Phone? phone;
      late audio.LocalFiles downloads;
      late _Engine engine;
      late Playback player;
      late RecordJournal remote;
      final account = audio.account().scope.key;
      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        if (sqlite) phone = await Phone.open('play-choice');
        store = _Store(
          openDatabase: sqlite ? () async => phone!.database : null,
        );
        downloads = audio.LocalFiles();
        engine = _Engine();
        player = Playback(downloads: downloads, engine: engine, store: store);
        await player.bind(audio.account(), [audio.title, otherBook]);
        await player.open(audio.title, audio.recording, autoplay: false);
        await player.seekEdition(11000);
        await player.flush();
        remote = RecordJournal(account, 'remote');
        remote.receive(await store.pendingUploads(account));
      });
      tearDown(() async {
        store.fail = false;
        if (store.saveGate case final gate? when !gate.isCompleted) {
          gate.complete();
        }
        engine.release();
        downloads.lookupGate?.complete();
        await player.close();
        downloads.dispose();
      });

      Future<void> receive(int milliseconds) async {
        remote.receive(await store.pendingUploads(account));
        remote.change(resumeRecordAddress(audio.recording), {
          'edition': audio.recording.id,
          'source': audio.first.key,
          'revision': audio.first.revision,
          'sources': editionSources(audio.recording),
          'milliseconds': milliseconds,
          'pendingOffline': false,
        }, device: 'Other phone');
        await store.receivePage(account, remote.uploads, 0);
        await player.refreshPersonalRecords();
      }

      Future<void> abandonAndRestart({bool failLoad = false}) async {
        final abandoned = player;
        store.fail = true;
        addTearDown(abandoned.close);
        if (sqlite) await phone!.restart();
        store = _Store(
          openDatabase: sqlite ? () async => phone!.database : null,
        );
        engine = _Engine()..failLoad = failLoad;
        player = Playback(downloads: downloads, engine: engine, store: store);
        await player.bind(audio.account(), [audio.title, otherBook]);
      }

      test(
        'a failed restart with a saved choice reports only the audio failure',
        () async {
          await receive(40000);
          await player.playExternally();
          await player.pause();
          final saved = (await store.read(account))!;
          expect(saved['playChoice'], isNotNull);

          await abandonAndRestart(failLoad: true);

          final status = player.statusNotifier.value;
          expect(status.recoveryMessage, isNull);
          expect(status.actionNotice?.editionId, audio.recording.id);
          expect(status.actionNotice?.operation, PlaybackOperation.open);
          expect(status.messagesFor(), isEmpty);
          expect(
            status.messagesFor(book: audio.title),
            contains(contains('Cannot play')),
          );
          expect((await store.read(account))!['history'], saved['history']);
          expect(
            (await store.read(account))!['playChoice'],
            saved['playChoice'],
          );
          player.checkInvariants();

          engine.failLoad = false;
          await player.open(audio.title, audio.recording, autoplay: false);
          expect(player.statusNotifier.value.actionNotice, isNull);
          expect(player.position!.milliseconds, 11000);
          expect(player.playChoiceNotifier.value?.remote.milliseconds, 40000);
          player.checkInvariants();
        },
      );

      test(
        'refresh completes after the withdrawn question is durable',
        () async {
          await receive(40000);
          await player.playExternally();
          await player.pause();
          store.saveGate = Completer<void>();
          store.saveEntered = Completer<void>();
          var completed = false;
          final refreshing = receive(11000).then((_) => completed = true);
          await store.saveEntered!.future;
          await pumpEventQueue();
          expect(completed, isFalse);
          store.saveGate!.complete();
          await refreshing;
          expect((await store.read(account))!['playChoice'], isNull);
        },
      );

      test(
        'restart reconciles the question after a held decoder load',
        () async {
          await receive(40000);
          await player.playExternally();
          await player.pause();
          final abandoned = player;
          store.fail = true;
          addTearDown(abandoned.close);
          if (sqlite) await phone!.restart();
          store = _Store(
            openDatabase: sqlite ? () async => phone!.database : null,
          );
          engine = _Engine()..held = HeldCommand.load;
          player = Playback(downloads: downloads, engine: engine, store: store);
          final binding = player.bind(audio.account(), [
            audio.title,
            otherBook,
          ]);
          await engine.entered.future;
          await receive(50000);
          engine.release();
          await binding;
          expect(player.position!.milliseconds, 11000);
          expect(player.playChoiceNotifier.value?.remote.milliseconds, 50000);
        },
      );

      test('restart rejects an obsolete question even when its withdrawal failed to save', () async {
        await receive(40000);
        await player.playExternally();
        await player.pause();
        store.fail = true;
        await receive(11000);
        await player.flush();
        expect(player.saveFailed, isTrue);
        expect((await store.read(account))!['playChoice'], isNotNull);
        await abandonAndRestart();
        expect(player.playChoiceNotifier.value, isNull);
        await player.play();
        expect(player.playing, isTrue);
        expect(player.position!.milliseconds, 11000);
      });

      for (final replacement in [50000, null]) {
        test(
          'a ${replacement == null ? 'deleted' : 'replaced'} choice during its seek never commits the obsolete move',
          () async {
            await receive(40000);
            await player.play();
            final choice = player.playChoiceNotifier.value!;
            final previousUndo = player.undoAction;
            engine.held = HeldCommand.seek;
            final choosing = player.chooseListeningPlace(
              choice,
              ListeningPlace.otherDevice,
            );
            await engine.entered.future;
            if (replacement == null) {
              remote.receive(await store.pendingUploads(account));
              remote.change(resumeRecordAddress(audio.recording), null);
              await store.receivePage(account, remote.uploads, 0);
              await player.refreshPersonalRecords();
            } else {
              await receive(replacement);
            }
            final current = await store.listeningResume(
              account,
              audio.recording,
            );
            engine.release();
            await choosing;
            expect(player.position!.milliseconds, 11000);
            expect(engine.milliseconds, 11000);
            expect(player.playing, isFalse);
            expect(player.undoAction?.id, previousUndo?.id);
            expect(
              player.history.where((event) => event.kind == HistoryAction.open),
              isEmpty,
            );
            expect(
              await store.listeningResume(account, audio.recording),
              current,
            );
            expect(
              player.playChoiceNotifier.value?.remote.milliseconds,
              replacement,
            );
            player.checkInvariants();
          },
        );
      }

      for (final refresh in [false, true]) {
        for (final replacement in [11000, 50000, null]) {
          test(
            'restart reconciles a ${replacement ?? 'deleted'} resume ${refresh ? 'after' : 'before'} refreshing a durable choice',
            () async {
              await receive(40000);
              await player.playExternally();
              await player.pause();
              remote.receive(await store.pendingUploads(account));
              remote.change(
                resumeRecordAddress(audio.recording),
                replacement == null
                    ? null
                    : {
                        'edition': audio.recording.id,
                        'source': audio.first.key,
                        'revision': audio.first.revision,
                        'sources': editionSources(audio.recording),
                        'milliseconds': replacement,
                        'pendingOffline': false,
                      },
                device: 'Other phone',
              );
              await store.receivePage(account, remote.uploads, 0);
              final current = await store.listeningResume(
                account,
                audio.recording,
              );
              if (refresh) {
                await player.refreshPersonalRecords();
                expect(
                  await store.listeningResume(account, audio.recording),
                  current,
                  reason: 'reconciling a question must not choose a resume',
                );
              }
              await abandonAndRestart();
              expect(
                player.playChoiceNotifier.value?.remote.milliseconds,
                replacement == 50000 ? 50000 : null,
              );
              if (replacement == 50000) {
                expect(player.position!.milliseconds, 11000);
              }
              await player.flush();
              // Once matching-place withdrawal is durable, restart follows the
              // ordinary open path, which may update its offline-report flag.
              if (!refresh || replacement != 11000) {
                expect(
                  await store.listeningResume(account, audio.recording),
                  current,
                  reason: 'recovering a question must not choose a resume',
                );
              } else {
                expect(player.position!.milliseconds, 11000);
              }
              final saved = await store.read(account);
              expect(
                saved!['playChoice'],
                replacement == 50000 ? isNotNull : isNull,
              );
              player.checkInvariants();
            },
          );
        }
      }

      for (final place in ListeningPlace.values) {
        test(
          'choosing ${place.name} saves both places and starts at that place',
          () async {
            await receive(40000);
            await player.play();
            final choice = player.playChoiceNotifier.value!;
            expect(choice.device, 'Other phone');
            await player.chooseListeningPlace(choice, place);
            expect(player.playing, isTrue);
            expect(
              player.position!.milliseconds,
              place == ListeningPlace.thisPhone ? 11000 : 40000,
            );
            expect(player.playChoiceNotifier.value, isNull);
            await player.pause();
            await player.refreshPersonalRecords();
            await player.play();
            expect(player.playChoiceNotifier.value, isNull);
            expect(
              player.history.where((e) => e.kind == HistoryAction.preserve),
              hasLength(2),
            );
            if (place == ListeningPlace.otherDevice) {
              expect(player.undoAction?.device, 'Other phone');
              await player.undoSeek();
              expect(player.position!.milliseconds, 11000);
            } else {
              final remote = player.history.firstWhere(
                (e) =>
                    e.kind == HistoryAction.preserve &&
                    e.after.milliseconds == 40000,
              );
              await player.restoreHistory(remote.id, previous: false);
              expect(player.position!.milliseconds, 40000);
            }
            player.checkInvariants();
          },
        );
      }

      test(
        'cancelling a choice leaves audio paused and asks on the next Play',
        () async {
          await receive(40000);
          await player.play();
          final choice = player.playChoiceNotifier.value!;
          player.cancelListeningChoice(choice);
          expect(player.playChoiceNotifier.value, isNull);
          expect(player.playing, isFalse);
          await player.play();
          expect(player.playChoiceNotifier.value, same(choice));
          expect(engine.playCount, 0);
        },
      );

      test('repeated external Play and refresh keep one pair and one pending question', () async {
        await receive(40000);
        final handler = PlaybackHandler()..attach(player);
        await handler.play();
        final choice = player.playChoiceNotifier.value!;
        await handler.play();
        await player.refreshPersonalRecords();
        expect(player.playChoiceNotifier.value, same(choice));
        expect(
          player.history.where((e) => e.kind == HistoryAction.preserve),
          hasLength(2),
        );
        await player.chooseListeningPlace(choice, ListeningPlace.thisPhone);
        await handler.play();
        expect(player.playChoiceNotifier.value, isNull);
      });

      test(
        'a newer sync invalidates the answer of the visible choice',
        () async {
          await receive(40000);
          await player.play();
          final stale = player.playChoiceNotifier.value!;
          await receive(50000);
          final current = player.playChoiceNotifier.value!;
          expect(current, isNot(same(stale)));
          await player.chooseListeningPlace(stale, ListeningPlace.otherDevice);
          expect(player.position!.milliseconds, 11000);
          expect(player.playing, isFalse);
          await player.chooseListeningPlace(
            current,
            ListeningPlace.otherDevice,
          );
          expect(player.position!.milliseconds, 50000);
        },
      );

      test('a deleted resume withdraws the old choice', () async {
        await receive(40000);
        await player.play();
        final choice = player.playChoiceNotifier.value!;
        remote.change(resumeRecordAddress(audio.recording), null);
        await store.receivePage(account, remote.uploads, 0);
        await player.refreshPersonalRecords();
        expect(player.playChoiceNotifier.value, isNull);
        await player.chooseListeningPlace(choice, ListeningPlace.otherDevice);
        expect(player.position!.milliseconds, 11000);
      });

      test('a failed durable preservation keeps the remote resume and does not start', () async {
        await receive(40000);
        store.fail = true;
        await (PlaybackHandler()..attach(player)).play();
        expect(engine.playCount, 0);
        expect(player.saveFailed, isTrue);
        final saved = await store.read(account);
        expect(
          (saved!['resumes'][audio.recording.id] as List).last['milliseconds'],
          40000,
        );
        store.fail = false;
        await player.playExternally();
        expect(player.playing, isTrue);
        expect(
          player.history.where((e) => e.kind == HistoryAction.preserve),
          hasLength(2),
        );
      });

      test(
        'restart recovers the deferred question from durable History',
        () async {
          await receive(40000);
          await player.playExternally();
          await player.flush();
          final abandoned = player;
          // The dead process can no longer write. The fake engine has no
          // autonomous callbacks; keep it open solely for teardown.
          store.fail = true;
          if (sqlite) await phone!.restart();
          store = _Store(
            openDatabase: sqlite ? () async => phone!.database : null,
          );
          engine = _Engine();
          player = Playback(downloads: downloads, engine: engine, store: store);
          await player.bind(audio.account(), [audio.title, otherBook]);
          expect(player.position!.milliseconds, 11000);
          expect(player.playChoiceNotifier.value?.remote.milliseconds, 40000);
          await player.flush();
          final saved = await store.read(account);
          expect(saved!['playChoice'], isNotNull);
          await player.chooseListeningPlace(
            player.playChoiceNotifier.value!,
            ListeningPlace.otherDevice,
          );
          expect(player.position!.milliseconds, 40000);
          // Abandonment above deliberately omitted Playback.close, as a killed
          // process does. Release its Dart-only subscriptions after assertions.
          await abandoned.close();
        },
      );

      test('another account cannot answer the former account choice', () async {
        await receive(40000);
        await player.play();
        final choice = player.playChoiceNotifier.value!;
        await player.bind(audio.account(user: 'bob'), [audio.title]);
        await player.chooseListeningPlace(choice, ListeningPlace.otherDevice);
        expect(player.position, isNull);
        expect(player.playChoiceNotifier.value, isNull);
        player.checkInvariants();
      });

      test('book-page Listen on the open recording asks without reloading the remote place', () async {
        await receive(40000);
        await player.open(audio.title, audio.recording);
        expect(player.position!.milliseconds, 11000);
        expect(engine.playCount, 0);
        expect(player.playChoiceNotifier.value, isNotNull);
      });

      test('a sync during ongoing playback preserves the remote place without moving or prompting', () async {
        await player.play();
        await receive(40000);
        engine.emit(0, 13000, playing: true);
        await player.flush();
        expect(player.playChoiceNotifier.value, isNull);
        expect(player.position!.milliseconds, 13000);
        final kept = player.history.where(
          (e) => e.kind == HistoryAction.preserve,
        );
        expect(kept.map((e) => e.after.milliseconds), contains(40000));
        await player.pause();
        await player.play();
        expect(player.playChoiceNotifier.value?.remote.milliseconds, 40000);
      });

      test(
        'a newer remote place equal to this phone withdraws an obsolete choice',
        () async {
          await receive(40000);
          await player.play();
          final choice = player.playChoiceNotifier.value!;
          await receive(11000);
          expect(player.playChoiceNotifier.value, isNull);
          await player.chooseListeningPlace(choice, ListeningPlace.otherDevice);
          expect(player.position!.milliseconds, 11000);
        },
      );

      test(
        'deleting the kept remote History entry withdraws its deferred choice',
        () async {
          await receive(40000);
          await player.playExternally();
          final choice = player.playChoiceNotifier.value!;
          final kept = player.history.firstWhere(
            (e) =>
                e.kind == HistoryAction.preserve &&
                e.after.milliseconds == 40000,
          );
          await player.deleteHistory(kept.id);
          expect(player.playChoiceNotifier.value, isNull);
          await player.chooseListeningPlace(choice, ListeningPlace.otherDevice);
          expect(player.position!.milliseconds, 11000);
        },
      );

      test('opening another edition cancels the choice without applying the former answer', () async {
        await receive(40000);
        await player.play();
        final choice = player.playChoiceNotifier.value!;
        for (final file in otherEdition.files) {
          downloads.files[file.key] = Uri.file('/other.wav');
        }
        await player.open(otherBook, otherEdition, autoplay: false);
        await player.chooseListeningPlace(choice, ListeningPlace.otherDevice);
        expect(player.edition!.id, otherEdition.id);
        expect(player.position!.milliseconds, 0);
        expect(player.playChoiceNotifier.value, isNull);
      });

      test('a replacement recording cannot use the old choice', () async {
        await receive(40000);
        await player.play();
        final choice = player.playChoiceNotifier.value!;
        const replaced = Edition(
          id: 'recording',
          kind: EditionKind.audio,
          label: 'Replacement',
          files: [
            SourceFile(
              itemId: 'one',
              displayName: 'Changed',
              mediaSourceId: 'm1',
              revision: 'changed',
              durationMs: 60000,
              container: 'wav',
              sizeBytes: 42,
            ),
          ],
          memberIds: ['one:m1'],
        );
        const book = Book(
          id: 'book',
          title: 'The journey',
          author: 'A. Writer',
          editions: [replaced],
        );
        await player.bind(audio.account(), [book]);
        await player.chooseListeningPlace(choice, ListeningPlace.otherDevice);
        expect(player.position, isNull);
        expect(player.playChoiceNotifier.value, isNull);
        expect(player.replacementStart, isNotNull);
      });

      for (final external in [false, true]) {
        test(
          'sync during a held ${external ? 'external' : 'in-app'} Play is considered before starting',
          () async {
            downloads.lookupGate = Completer<void>();
            final playing = external ? player.playExternally() : player.play();
            await pumpEventQueue();
            await receive(40000);
            downloads.lookupGate!.complete();
            downloads.lookupGate = null;
            await playing;
            expect(player.playChoiceNotifier.value?.remote.milliseconds, 40000);
            expect(player.playing, external);
            expect(player.position!.milliseconds, 11000);
          },
        );
      }

      test('refresh replaces a pending choice while an unrelated audio command is held', () async {
        await receive(40000);
        await player.play();
        final old = player.playChoiceNotifier.value!;
        engine.held = HeldCommand.pause;
        final pausing = player.pause();
        await engine.entered.future;
        await receive(50000).timeout(const Duration(seconds: 5));
        expect(player.playChoiceNotifier.value?.remote.milliseconds, 50000);
        engine.release();
        await pausing;
        await player.chooseListeningPlace(old, ListeningPlace.otherDevice);
        expect(player.position!.milliseconds, 11000);
      });

      if (sqlite) {
        test('a kill during preservation commits neither the new resume nor half the History pair', () async {
          await receive(40000);
          final sql = await phone!.separateConnection();
          await sql.execute(
            "CREATE TRIGGER cut AFTER INSERT ON record_actions BEGIN SELECT RAISE(ABORT, 'killed'); END",
          );
          try {
            await player.playExternally();
            expect(player.saveFailed, isTrue);
            expect(player.playing, isFalse);
            final restarted = LocalResumeStore(
              openDatabase: () async => phone!.database,
            );
            final saved = await restarted.read(account);
            expect(
              (saved!['resumes'][audio.recording.id] as List)
                  .last['milliseconds'],
              40000,
            );
            expect(
              (saved['history'] as List).where((e) => e['kind'] == 'preserve'),
              isEmpty,
            );
          } finally {
            await sql.execute('DROP TRIGGER cut');
          }
          await player.playExternally();
          expect(
            player.history.where((e) => e.kind == HistoryAction.preserve),
            hasLength(2),
          );
          expect(player.playing, isTrue);
        });
      }

      test('external Play after a decoder load failure still requires durable preservation', () async {
        await receive(40000);
        for (final file in otherEdition.files) {
          downloads.files[file.key] = Uri.file('/other.wav');
        }
        engine.failLoad = true;
        await player.open(otherBook, otherEdition, autoplay: false);
        engine.failLoad = false;
        store.fail = true;
        await player.playExternally();
        expect(player.playing, isFalse);
        expect(engine.playCount, 0);
        store.fail = false;
        await player.playExternally();
        expect(
          player.history.where((e) => e.kind == HistoryAction.preserve),
          hasLength(2),
        );
        expect(player.position!.milliseconds, 11000);
        expect(player.playChoiceNotifier.value?.remote.milliseconds, 40000);
      });

      test('a deferred question survives settings saves before the library returns', () async {
        await receive(40000);
        await player.playExternally();
        await player.close();
        engine = _Engine();
        player = Playback(downloads: downloads, engine: engine, store: store);
        await player.bind(audio.account(), []);
        await player.setJumps(15, 45);
        await player.flush();
        final saved = await store.read(account);
        expect(saved!['playChoice'], isNotNull);
      });

      test('external Play keeps the only remote place in History before replacing its resume', () async {
        await receive(40000);
        expect(player.position!.milliseconds, 11000);
        final handler = PlaybackHandler()..attach(player);
        await handler.play();
        engine.emit(0, 12000, playing: true);
        await player.flush();
        final saved = await store.read(account);
        final places = (saved!['history'] as List).expand(
          (event) => [
            event['before']['milliseconds'],
            event['after']['milliseconds'],
          ],
        );
        expect(
          places,
          contains(40000),
          reason: 'the sole remote place must remain recoverable',
        );
        expect(places, contains(11000));
        expect(player.playing, isTrue);
        expect(player.position!.milliseconds, 12000);
      });

      test('in-app Play stays paused until this phone or the remote place is chosen', () async {
        await receive(40000);
        await player.play();
        expect(engine.playCount, 0);
        expect(player.position!.milliseconds, 11000);
      });
    });
  }
}
