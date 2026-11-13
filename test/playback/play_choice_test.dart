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
  @override
  Future<void> save(String account, ListeningChanges changes) {
    if (fail) throw Exception('disk full');
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
