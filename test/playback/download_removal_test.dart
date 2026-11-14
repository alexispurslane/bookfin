import 'dart:async';
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../downloads/transfer_test.dart' show MediaFixture;
import '../sync/phone.dart';
import 'held_engine.dart';

/// The decoder boundary reopens real downloaded files for seeks and progression.
/// Removing an unopened part therefore fails here, as it does on a decoder reopen.
class _FileEngine extends HeldEngine {
  Object? loadFailure;
  int cleanupFailures = 0;
  int pauses = 0;
  int _pauseFailures = 0;

  @override
  Future<void> load(List<Uri> sources, int fileIndex, int position) async {
    if (loadFailure case final failure?) {
      loadFailure = null;
      _pauseFailures = cleanupFailures;
      throw failure;
    }
    await super.load(sources, fileIndex, position);
  }

  @override
  Future<void> pause() async {
    pauses++;
    if (_pauseFailures > 0) {
      _pauseFailures--;
      throw Exception('decoder release failed');
    }
    await super.pause();
  }

  @override
  Future<AudioSample> seek(int fileIndex, int position) async {
    await super.seek(fileIndex, position);
    await File.fromUri(files[fileIndex]).readAsBytes();
    return AudioSample(fileIndex, position, playing: isPlaying);
  }

  Future<void> nextFile() async {
    await File.fromUri(files[index + 1]).readAsBytes();
    emit(index + 1, 0, playing: true);
  }
}

class _Store extends LocalResumeStore {
  _Store({super.openDatabase});
  bool fail = false;
  Completer<void>? gate;
  Completer<void>? entered;
  @override
  Future<void> save(String account, ListeningChanges changes) async {
    if (gate != null) {
      if (!entered!.isCompleted) entered!.complete();
      await gate!.future;
    }
    if (fail) throw const FileSystemException('disk full');
    await super.save(account, changes);
  }
}

class _Downloads extends LocalDownloads {
  _Downloads({
    required super.root,
    required super.freeBytes,
    required super.policy,
  });
  String? failRead;
  @override
  Future<T?> readLocalFile<T>(
    SourceFile source,
    Future<T> Function(VerifiedFile original) read, {
    void Function(bool Function() live)? onOwnership,
  }) => super.readLocalFile(source, (original) {
    if (source.key == failRead) throw const FileSystemException('read failed');
    return read(original);
  }, onOwnership: onOwnership);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  for (final sqlite in [false, true]) {
    group(sqlite ? 'SQLite' : 'preferences', () {
      late MediaFixture fixture;
      late Directory root;
      late _Downloads downloads;
      late _FileEngine engine;
      late _Store store;
      late Playback player;
      late Book book;
      late Edition edition;
      late Book otherBook;
      late Edition otherEdition;
      late List<Uri> paths;
      var downloadsDisposed = false;
      Phone? phone;

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        fixture = await MediaFixture.start();
        root = await Directory.systemTemp.createTemp('bookfin-audio-removal-');
        downloads = _Downloads(
          root: root,
          freeBytes: () async => 1000000,
          policy: MediaPolicy()..network = MediaNetwork.wifi,
        );
        book = fixture.books.single;
        edition = fixture.audio;
        otherEdition = Edition(
          id: 'other',
          kind: EditionKind.audio,
          label: 'Other',
          files: [fixture.file('audio3')],
          memberIds: ['audio3:audio3'],
        );
        otherBook = Book(
          id: 'other',
          title: 'Other',
          author: 'Writer',
          editions: [otherEdition],
        );
        downloadsDisposed = false;
        await downloads.bind(fixture.session(), [book, otherBook]);
        await downloads.request(edition);
        await downloads.idle;
        paths = [
          for (final source in edition.files)
            (await downloads.localFile(source))!,
        ];
        if (sqlite) phone = await Phone.open('audio-removal');
        store = _Store(
          openDatabase: sqlite ? () async => phone!.database : null,
        );
        engine = _FileEngine();
        player = Playback(downloads: downloads, engine: engine, store: store);
        await player.bind(fixture.session(), [book, otherBook]);
        await player.open(book, edition);
        await player.flush();
      });

      tearDown(() async {
        store.fail = false;
        if (store.gate case final gate? when !gate.isCompleted) gate.complete();
        engine.release();
        await player.close();
        if (!downloadsDisposed) downloads.dispose();
        await downloads.idle;
        downloads.policy.dispose();
        await fixture.close();
        await root.delete(recursive: true);
      });

      Future<void> waitForPending() async {
        await pumpEventQueue();
        expect(downloads.status(edition).removing, isTrue);
      }

      Future<void> expectFilesKept() async {
        for (final path in paths) {
          expect(await File.fromUri(path).readAsBytes(), fixture.payload);
        }
      }

      test('removal refuses an opening edition whose file verification is still running', () async {
        await player.pause();
        await downloads.request(otherEdition);
        await downloads.idle;
        final path = (await downloads.localFile(otherEdition.files.single))!;
        final verifying = Completer<void>();
        final verified = Completer<void>();
        final reading = Completer<void>();
        final read = Completer<void>();
        addTearDown(() {
          if (!verified.isCompleted) verified.complete();
          if (!read.isCompleted) read.complete();
        });
        final opening = IOOverrides.runZoned(
          () => player.open(otherBook, otherEdition),
          fseGetType: (name, followLinks) async {
            if (name == path.toFilePath() && !verified.isCompleted) {
              if (!verifying.isCompleted) verifying.complete();
              await verified.future;
            }
            return Zone.root.run(
              () => FileSystemEntity.type(name, followLinks: followLinks),
            );
          },
        );
        await verifying.future;
        final unrelated = downloads.readLocalFile(edition.files.first, (
          _,
        ) async {
          reading.complete();
          await read.future;
          return true;
        });
        final removal = downloads.remove(otherEdition);
        await pumpEventQueue();
        expect(downloads.status(otherEdition).removing, isTrue);
        verified.complete();
        await reading.future;
        await opening;
        final admitted = player.edition?.id == otherEdition.id;
        if (admitted) engine.emit(0, 17000, playing: true);
        store.fail = true;
        await player.close();
        read.complete();
        await unrelated;
        await removal;
        // No new listening place may arise after removal owns admission.
        expect(admitted, isFalse);
        expect(await File.fromUri(path).exists(), isFalse);
      });

      test('failed decoder cleanup retains reachable ownership for a later removal', () async {
        await downloads.request(otherEdition);
        await downloads.idle;
        final path = (await downloads.localFile(otherEdition.files.single))!;
        engine.loadFailure = Exception('decoder load failed');
        engine.cleanupFailures = 1;
        await player.open(otherBook, otherEdition);
        expect(await File.fromUri(path).exists(), isTrue);
        await downloads
            .remove(otherEdition)
            .timeout(const Duration(seconds: 1));
        expect(await File.fromUri(path).exists(), isFalse);
        await player.play();
        expect(player.playing, isTrue);
        engine.emit(0, 19000, playing: true);
        expect(player.position!.milliseconds, 19000);
        player.checkInvariants();
      });

      test(
        'repeated decoder release failure keeps files until a successful retry',
        () async {
          await downloads.request(otherEdition);
          await downloads.idle;
          final path = (await downloads.localFile(otherEdition.files.single))!;
          engine.loadFailure = Exception('decoder load failed');
          engine.cleanupFailures = 3;
          await player.open(otherBook, otherEdition);
          player.checkInvariants();
          await expectLater(
            downloads.remove(otherEdition),
            throwsA(isA<Exception>()),
          );
          expect(await File.fromUri(path).readAsBytes(), fixture.payload);
          expect(downloads.status(otherEdition).removing, isFalse);
          await downloads
              .remove(otherEdition)
              .timeout(const Duration(seconds: 1));
          expect(await File.fromUri(path).exists(), isFalse);
          await player.play();
          expect(player.playing, isTrue);
          player.checkInvariants();
        },
      );

      test(
        'a programming Error survives an Exception from decoder cleanup',
        () async {
          await downloads.request(otherEdition);
          await downloads.idle;
          final failure = StateError('decoder contract');
          engine.loadFailure = failure;
          engine.cleanupFailures = 1;
          await expectLater(
            player.open(otherBook, otherEdition),
            throwsA(same(failure)),
          );
          await player.stop();
          await downloads
              .remove(otherEdition)
              .timeout(const Duration(seconds: 1));
          await player.play();
          engine.emit(0, 21000, playing: true);
          expect(player.position!.milliseconds, 21000);
        },
      );

      for (final replacement in ['catalog', 'account']) {
        test(
          'a stale leftover request cannot contact the current $replacement decoder',
          () async {
            await player.pause();
            await downloads.bind(fixture.session(), [otherBook]);
            final leftover = (await downloads.retainedStorage()).first;
            final session = fixture.session(
              user: replacement == 'account' ? 'bob' : 'alice',
            );
            fixture.authenticatedUser = session.scope.userId;
            await downloads.bind(session, [book, otherBook]);
            await player.bind(session, [book, otherBook]);
            await downloads.request(edition);
            await downloads.idle;
            await player.open(book, edition, autoplay: false);
            await player.flush();
            final pauses = engine.pauses;
            final saved = await store.read(session.scope.key);
            await expectLater(
              downloads.removeRetained(leftover),
              throwsA(isA<DownloadRemovalException>()),
            );
            expect(engine.pauses, pauses);
            expect(await store.read(session.scope.key), saved);
            expect(downloads.status(edition).phase, DownloadPhase.downloaded);
          },
        );
      }

      test(
        'a queued removal remembers a failed close while another read is held',
        () async {
          await downloads.request(otherEdition);
          await downloads.idle;
          final entered = Completer<void>();
          final gate = Completer<void>();
          addTearDown(() {
            if (!gate.isCompleted) gate.complete();
          });
          final reading = downloads.readLocalFile(otherEdition.files.single, (
            _,
          ) async {
            entered.complete();
            await gate.future;
            return true;
          });
          await entered.future;
          final removal = downloads.remove(edition);
          final refused = expectLater(
            removal,
            throwsA(isA<DownloadRemovalException>()),
          );
          await waitForPending();
          store.fail = true;
          await player.close();
          gate.complete();
          await reading;
          await refused;
          await expectFilesKept();
        },
      );

      test('a failed file acquisition releases parts that never reached the decoder', () async {
        await player.pause();
        downloads.failRead = edition.files.last.key;
        await player.open(book, edition, autoplay: false);
        expect(player.statusNotifier.value.actionNotice, isNotNull);
        downloads.failRead = null;
        await downloads.remove(edition).timeout(const Duration(seconds: 1));
        expect(await File.fromUri(paths.first).exists(), isFalse);
      });

      test('leftover removal also refuses to remove playing audio after a failed save', () async {
        // Downloads can learn that a library was hidden before Playback binds it.
        await downloads.bind(fixture.session(), [otherBook]);
        final leftover = (await downloads.retainedStorage()).first;
        final removal = downloads.removeRetained(leftover);
        final refused = expectLater(
          removal,
          throwsA(isA<DownloadRemovalException>()),
        );
        await pumpEventQueue();
        store.fail = true;
        await player.pause();
        await refused.timeout(const Duration(seconds: 1));
        await expectFilesKept();
      });

      test(
        'duplicate removals share the pending result while playback continues',
        () async {
          var completed = 0;
          final first = downloads.remove(edition).then((_) => completed++);
          final second = downloads.remove(edition).then((_) => completed++);
          await waitForPending();
          expect(completed, 0);
          expect(downloads.watch(edition).value.actions, isEmpty);
          expect(
            downloads.watch(edition).value.message,
            contains('pause or switch books'),
          );
          expect(player.playing, isTrue);
          await expectFilesKept();
          await player.pause();
          await Future.wait([first, second]);
          expect(completed, 2);
          expect(downloads.status(edition).phase, DownloadPhase.none);
          expect(downloads.status(edition).removing, isFalse);
          downloads.checkInvariants();
          player.checkInvariants();
        },
      );

      for (final openedPaused in [false, true]) {
        test(
          '${openedPaused ? 'a paused open' : 'already paused audio'} removes without starting sound',
          () async {
            await player.pause();
            if (openedPaused) await player.open(book, edition, autoplay: false);
            final starts = engine.playCount;
            await downloads.remove(edition);
            expect(engine.playCount, starts);
            expect(player.playing, isFalse);
            expect(await File.fromUri(paths.last).exists(), isFalse);
          },
        );
      }

      test(
        'a native pause callback saves its confirmed place before removal',
        () async {
          final removal = downloads.remove(edition);
          await waitForPending();
          store.gate = Completer<void>();
          store.entered = Completer<void>();
          engine.emit(1, 45000, playing: false);
          await store.entered!.future;
          await expectFilesKept();
          store.gate!.complete();
          await removal;
          final saved = (await store.read(fixture.session().scope.key))!;
          expect(
            (saved['resumes'] as Map)[edition.id].single['milliseconds'],
            45000,
          );
          expect(player.playing, isFalse);
        },
      );

      test(
        'removal during a held seek keeps both parts until the later pause',
        () async {
          engine.held = HeldCommand.seek;
          final seeking = player.seekSource(edition.files[1].key, 18000);
          await engine.entered.future;
          final removal = downloads.remove(edition);
          await waitForPending();
          await expectFilesKept();
          engine.release();
          await seeking;
          expect(player.playing, isTrue);
          expect(player.position!.milliseconds, 18000);
          await player.pause();
          await removal;
          expect(player.statusNotifier.value.actionNotice, isNull);
        },
      );

      test('book switch saves the old place and can read the new files while removal waits', () async {
        await downloads.request(otherEdition);
        await downloads.idle;
        final otherPath = (await downloads.localFile(
          otherEdition.files.single,
        ))!;
        engine.emit(1, 26000, playing: true);
        await player.flush();
        final removal = downloads.remove(edition);
        await waitForPending();
        store.gate = Completer<void>();
        store.entered = Completer<void>();
        final switching = player.open(otherBook, otherEdition);
        await store.entered!.future;
        await expectFilesKept();
        store.gate!.complete();
        await switching;
        await removal;
        expect(player.edition!.id, 'other');
        expect(player.playing, isTrue);
        expect(await File.fromUri(otherPath).readAsBytes(), fixture.payload);
        final saved = (await store.read(fixture.session().scope.key))!;
        expect(
          (saved['resumes'] as Map)[edition.id].single['milliseconds'],
          26000,
        );
        player.checkInvariants();
      });

      for (final replacement in ['account', 'source']) {
        test(
          'a pending removal cannot follow a replacement $replacement',
          () async {
            final removal = downloads.remove(edition);
            final refused = expectLater(
              removal,
              throwsA(isA<DownloadRemovalException>()),
            );
            await waitForPending();
            if (replacement == 'source') fixture.revision = 'replacement';
            final session = fixture.session(
              user: replacement == 'account' ? 'bob' : 'alice',
            );
            fixture.authenticatedUser = session.scope.userId;
            final nextBook = fixture.books.single;
            final nextEdition = fixture.audio;
            await Future.wait([
              downloads.bind(session, [nextBook]),
              player.bind(session, [nextBook]),
            ]);
            await refused;
            await downloads.request(nextEdition);
            await downloads.idle;
            for (final file in nextEdition.files) {
              expect(
                await File.fromUri((await downloads.localFile(file))!)
                    .readAsBytes(),
                fixture.payload,
              );
            }
            await expectFilesKept();
            expect(downloads.status(nextEdition).removing, isFalse);
            if (replacement == 'account') {
              await player.open(nextBook, nextEdition);
              expect(player.playing, isTrue);
            }
          },
        );
      }

      test(
        'disposing Downloads abandons a pending removal without deleting files',
        () async {
          final removal = downloads.remove(edition);
          final refused = expectLater(
            removal,
            throwsA(isA<DownloadRemovalException>()),
          );
          await waitForPending();
          downloads.dispose();
          downloadsDisposed = true;
          await refused;
          await expectFilesKept();
          await player.pause();
          await expectFilesKept();
        },
      );

      test(
        'closing after a failed save leaves files and recoverable changes',
        () async {
          engine.emit(1, 47000, playing: true);
          final removal = downloads.remove(edition);
          final refused = expectLater(
            removal,
            throwsA(isA<DownloadRemovalException>()),
          );
          await waitForPending();
          store.fail = true;
          await player.close();
          await refused;
          await expectFilesKept();
          expect(player.unsavedChanges, isTrue);
          store.fail = false;
          await player.flush();
          final saved = (await store.read(fixture.session().scope.key))!;
          expect(
            (saved['resumes'] as Map)[edition.id].single['milliseconds'],
            47000,
          );
        },
      );

      test('a fresh removal after failed-save close must still save before deleting', () async {
        engine.emit(1, 41000, playing: true);
        store.fail = true;
        await player.close();
        expect(player.unsavedChanges, isTrue);
        await expectLater(
          downloads.remove(edition),
          throwsA(isA<DownloadRemovalException>()),
        );
        await expectFilesKept();
        store.fail = false;
        await downloads.remove(edition);
        expect(await File.fromUri(paths.first).exists(), isFalse);
        final saved = (await store.read(fixture.session().scope.key))!;
        expect(
          (saved['resumes'] as Map)[edition.id].single['milliseconds'],
          41000,
        );
      });

      test(
        'removal retains bookmarks History and saved places across restart',
        () async {
          await player.seekSource(edition.files.last.key, 32000);
          await player.addBookmark(title: 'Keep this');
          await player.pause();
          await player.stop();
          await player.flush();
          final account = fixture.session().scope.key;
          final saved = (await store.read(account))!;
          await downloads.remove(edition);
          await player.close();
          if (sqlite) await phone!.restart();
          store = _Store(
            openDatabase: sqlite ? () async => phone!.database : null,
          );
          final after = (await store.read(account))!;
          expect(after['bookmarks'], saved['bookmarks']);
          expect(after['history'], saved['history']);
          expect(after['resumes'], saved['resumes']);
        },
      );

      // Removing without a read hold used to delete both parts before either
      // a seek reopened the second part or natural progression opened it.
      for (final seek in [false, true]) {
        test('removal keeps every audio part usable until pause during '
            '${seek ? 'a seek' : 'multi-file progression'}', () async {
          final removal = downloads.remove(edition);
          await Future.any([
            removal,
            Future<void>.delayed(const Duration(milliseconds: 100)),
          ]);
          if (seek) {
            await player.seekSource(edition.files[1].key, 12000);
            expect(player.statusNotifier.value.actionNotice, isNull);
          } else {
            await engine.nextFile();
          }
          expect(player.playing, isTrue);
          expect(player.position!.sourceKey, edition.files[1].key);
          await player.pause();
          await removal;
          for (final path in paths) {
            expect(await File.fromUri(path).exists(), isFalse);
          }
        });
      }

      test(
        'pause keeps files until the listening place is durably saved',
        () async {
          engine.emit(1, 23000, playing: true);
          await player.flush();
          store.gate = Completer<void>();
          store.entered = Completer<void>();
          var removed = false;
          final removal = downloads.remove(edition).then((_) => removed = true);
          final pausing = player.pause();
          await store.entered!.future;
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(removed, isFalse);
          for (final path in paths) {
            expect(await File.fromUri(path).exists(), isTrue);
          }
          store.gate!.complete();
          await pausing;
          await removal;
          final restored = Playback(
            downloads: downloads,
            engine: _FileEngine(),
            store: store,
          );
          await restored.bind(fixture.session(), [book]);
          expect(
            restored.history.any((entry) => entry.after.milliseconds == 23000),
            isTrue,
          );
          await restored.close();
        },
      );

      test(
        'a failed pause save refuses removal and keeps the place recoverable',
        () async {
          engine.emit(1, 31000, playing: true);
          store.fail = true;
          final removal = downloads.remove(edition);
          final refused = expectLater(removal, throwsA(isA<Exception>()));
          await player.pause();
          await refused;
          expect(player.saveFailed, isTrue);
          expect(player.position!.milliseconds, 31000);
          for (final path in paths) {
            expect(await File.fromUri(path).exists(), isTrue);
          }
          store.fail = false;
          await downloads.remove(edition);
          expect(player.saveFailed, isFalse);
          final saved = (await store.read(fixture.session().scope.key))!;
          expect(
            (saved['resumes'] as Map)[edition.id].single['milliseconds'],
            31000,
          );
        },
      );
    });
  }
}
