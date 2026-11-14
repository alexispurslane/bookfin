import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/app/account_binding.dart';
import 'package:bookfin/catalog/catalog_files_io.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/covers_io.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/store.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/settings/clear_data.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../catalog/controller_test.dart' show FixtureClient, MemoryCredentials;
import '../downloads/transfer_test.dart' show MediaFixture;
import '../playback/playback_test.dart' as audio;
import '../playback/incremental_save_test.dart' show bookmark, event, resume;
import '../sync/controlled_transport.dart';
import '../sync/phone.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();
  for (final sqlite in [false, true]) {
    group(sqlite ? 'SQLite Settings clear' : 'preferences Settings clear', () {
      late Directory root;
      late MediaFixture media;
      late JellyfinSession alice;
      late JellyfinSession bob;
      late LocalCatalogStore cache;
      late _HeldCatalogFiles catalogFiles;
      late _FailingPreferences preferences;
      late MemoryCredentials credentials;
      late CatalogController catalog;
      late _ObservedDownloads downloads;
      late DiskCovers covers;
      late LocalResumeStore records;
      late RecordSync sync;
      late AccountBinding binding;
      late MediaPolicy policy;
      late FixtureClient client;
      late File downloaded;
      late File bobDownloaded;
      Phone? phone;
      Future<void> Function()? upload;
      final sent = <String>[];
      final cover = const CoverRef('text', 'v1');
      var online = true;
      setUp(() async {
        SharedPreferences.setMockInitialValues({
          'bookfin.appearance.test': 'night',
        });
        preferences = _FailingPreferences();
        SharedPreferencesStorePlatform.instance = preferences;
        SharedPreferences.resetStatic();
        final oldPreferences = SharedPreferencesAsyncPlatform.instance;
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        addTearDown(
          () => SharedPreferencesAsyncPlatform.instance = oldPreferences,
        );
        root = await Directory.systemTemp.createTemp('settings-clear-');
        media = await MediaFixture.start();
        alice = media.session();
        bob = media.session(user: 'bob');
        catalogFiles = _HeldCatalogFiles(Directory('${root.path}/catalog'));
        cache = LocalCatalogStore(files: catalogFiles);
        for (final session in [alice, bob]) {
          await cache.write(
            session.scope,
            CatalogCache(
              scope: session.scope,
              libraries: [const BookLibrary('books', 'Books')],
              entries: [
                CatalogEntry.fromJson(media.dto('text'), libraryId: 'books'),
              ],
            ).encode(),
          );
        }
        credentials = MemoryCredentials()..value = alice;
        client = FixtureClient(media.uri);
        catalog = CatalogController(
          credentials: credentials,
          store: cache,
          clientFactory: (_, _) => client,
        );
        await catalog.restore();
        policy = MediaPolicy()..network = MediaNetwork.wifi;
        downloads = _ObservedDownloads(
          root: Directory('${root.path}/media'),
          freeBytes: () async => 1000000,
          policy: policy,
        );
        // Retain a separate account's real downloaded bytes in the same root.
        await downloads.bind(bob, catalog.books);
        media.authenticatedUser = 'bob';
        await downloads.request(catalog.books.single.editions.single);
        await downloads.idle;
        bobDownloaded = File.fromUri(
          (await downloads.localFile(
            catalog.books.single.editions.single.files.single,
          ))!,
        );
        await downloads.bind(alice, catalog.books);
        media.authenticatedUser = 'alice';
        await downloads.request(catalog.books.single.editions.single);
        await downloads.idle;
        downloaded = File.fromUri(
          (await downloads.localFile(
            catalog.books.single.editions.single.files.single,
          ))!,
        );
        online = true;
        covers = DiskCovers(
          root: Directory('${root.path}/covers'),
          fetch: (_, _) async {
            if (!online) throw const SocketException('offline');
            return Uint8List.fromList([1, 2, 3]);
          },
        );
        await covers.load(alice, cover);
        await covers.load(bob, cover);
        phone = sqlite ? await Phone.open('settings-clear') : null;
        records = phone?.store ?? LocalResumeStore();
        for (final who in [alice, bob]) {
          await records.write(who.scope.key, {
            'bookmarks': [bookmark('kept', title: '${who.username} bookmark')],
            'history': [event('move', 5000)],
            'resumes': resume(5000),
          });
        }
        upload = null;
        sent.clear();
        sync = RecordSync(
          records: records,
          transport: ControlledTransport(records, (session, _) async {
            final pending = await records.pendingUploads(session.scope.key);
            await upload?.call();
            sent.add(session.scope.key);
            await records.acknowledgeBatch(
              session.scope.key,
              pending.map(RecordJournal.identity),
            );
            return (replaced: 0);
          }),
        )..suspend();
        binding = AccountBinding(
          catalog: catalog,
          downloads: downloads,
          sync: sync,
        );
        await downloads.bind(alice, catalog.books);
      });
      tearDown(() async {
        binding.dispose();
        sync.dispose();
        catalog.dispose();
        client.close();
        downloads.dispose();
        await downloads.idle;
        policy.dispose();
        await media.close();
        await root.delete(recursive: true);
      });
      Future<void> clear() => clearAccountData(
        confirmed: alice,
        catalog: catalog,
        sync: sync,
        downloads: downloads,
        covers: covers,
      );
      Future<LocalResumeStore> reopenedRecords() async {
        if (phone case final phone?) {
          await phone.restart();
          return phone.store;
        }
        return LocalResumeStore();
      }

      Future<void> expectFilesKept() async {
        expect(await downloaded.exists(), isTrue);
        expect(await cache.read(alice.scope), isNotNull);
        online = false;
        expect(await covers.load(alice, cover), [1, 2, 3]);
        online = true;
      }

      Future<({Playback player, audio.TestEngine engine, List<Uri> paths})>
      startDownloadedAudio() async {
        await cache.write(
          alice.scope,
          CatalogCache(
            scope: alice.scope,
            libraries: [const BookLibrary('books', 'Books')],
            entries: [
              for (final id in ['audio1', 'audio2'])
                CatalogEntry.fromJson(media.dto(id), libraryId: 'books'),
            ],
          ).encode(),
        );
        await catalog.restore();
        await downloads.bind(alice, catalog.books);
        final paths = <Uri>[];
        for (final book in catalog.books) {
          final edition = book.editions.single;
          await downloads.request(edition);
          await downloads.idle;
          paths.add((await downloads.localFile(edition.files.single))!);
        }
        final engine = audio.TestEngine();
        final player = Playback(
          downloads: downloads,
          engine: engine,
          store: records,
        );
        addTearDown(player.close);
        binding.dispose();
        binding = AccountBinding(
          catalog: catalog,
          downloads: downloads,
          playback: player,
          sync: sync,
        );
        await player.bind(alice, catalog.books);
        await player.open(
          catalog.books.first,
          catalog.books.first.editions.single,
        );
        await player.flush();
        return (player: player, engine: engine, paths: paths);
      }

      Future<void> waitForRemoval(Edition edition) async {
        final status = downloads.watch(edition);
        if (status.value.removing) return;
        final entered = Completer<void>();
        void changed() {
          if (status.value.removing && !entered.isCompleted) entered.complete();
        }

        status.addListener(changed);
        try {
          await entered.future.timeout(const Duration(seconds: 5));
        } finally {
          status.removeListener(changed);
        }
      }

      test('Clear data waits for audio pause and uploads its new place before deleting', () async {
        final (:player, :engine, :paths) = await startDownloadedAudio();
        final edition = player.edition!;
        var completed = false;
        final clearing = clear().then((_) => completed = true);
        await waitForRemoval(edition);
        expect(player.playing, isTrue);
        expect(completed, isFalse);
        expect(await File.fromUri(paths.first).readAsBytes(), media.payload);
        final uploading = Completer<void>();
        final uploaded = Completer<void>();
        addTearDown(() {
          if (!uploaded.isCompleted) uploaded.complete();
        });
        upload = () async {
          if (!uploading.isCompleted) uploading.complete();
          await uploaded.future;
        };
        engine.emit(0, 23000, playing: true);
        await player.pause();
        await uploading.future.timeout(const Duration(seconds: 5));
        expect(await File.fromUri(paths.first).exists(), isTrue);
        expect(completed, isFalse);
        uploaded.complete();
        await clearing;
        expect(await File.fromUri(paths.first).exists(), isFalse);
        expect(await File.fromUri(paths.last).exists(), isFalse);
        final saved = (await records.read(alice.scope.key))!;
        expect(saved['resumes'][edition.id].single['milliseconds'], 23000);
        expect(await records.hasPendingUploads(alice.scope.key), isFalse);
        expect(await bobDownloaded.readAsBytes(), media.payload);
        expect(catalog.books, isEmpty);
        downloads.checkInvariants();
        player.checkInvariants();
      });

      for (final failure in ['save', 'upload']) {
        test(
          'Clear data keeps audio when the pause $failure fails and succeeds on retry',
          () async {
            final (:player, :engine, :paths) = await startDownloadedAudio();
            final edition = player.edition!;
            final clearing = clear();
            final refused = expectLater(clearing, throwsA(isA<Exception>()));
            await waitForRemoval(edition);
            final sql = await phone?.separateConnection();
            try {
              if (failure == 'save') {
                preferences.refuseTitle = '31000';
                await sql?.execute(
                  "CREATE TRIGGER refuse_pause BEFORE INSERT ON record_actions BEGIN SELECT RAISE(ABORT, 'storage full'); END",
                );
              } else {
                upload = () async =>
                    throw const SocketException('offline after pause');
              }
              engine.emit(0, 31000, playing: true);
              await player.pause();
              await refused;
              expect(
                await File.fromUri(paths.first).readAsBytes(),
                media.payload,
              );
              expect(await cache.read(alice.scope), isNotNull);
              expect(catalog.clearingNotifier.value, isFalse);
              expect(player.unsavedChanges, failure == 'save');
            } finally {
              preferences.refuseTitle = null;
              await sql?.execute('DROP TRIGGER IF EXISTS refuse_pause');
              upload = null;
            }
            await clear();
            expect(await File.fromUri(paths.first).exists(), isFalse);
            expect(player.unsavedChanges, isFalse);
            final saved = (await records.read(alice.scope.key))!;
            expect(saved['resumes'][edition.id].single['milliseconds'], 31000);
            expect(await records.hasPendingUploads(alice.scope.key), isFalse);
            expect(await bobDownloaded.readAsBytes(), media.payload);
          },
        );
      }

      test('Clear data releases the old book on switch and waits for the new book to pause', () async {
        final (:player, :engine, :paths) = await startDownloadedAudio();
        final first = player.edition!;
        final secondBook = catalog.books.last;
        final second = secondBook.editions.single;
        var completed = false;
        final clearing = clear().then((_) => completed = true);
        await waitForRemoval(first);
        engine.emit(0, 17000, playing: true);
        await player.open(secondBook, second);
        await waitForRemoval(second);
        expect(player.edition, second);
        expect(player.playing, isTrue);
        expect(completed, isFalse);
        expect(await File.fromUri(paths.first).exists(), isFalse);
        expect(await File.fromUri(paths.last).readAsBytes(), media.payload);
        engine.emit(0, 9000, playing: true);
        await player.pause();
        await clearing;
        final saved = (await records.read(alice.scope.key))!;
        expect(saved['resumes'][first.id].single['milliseconds'], 17000);
        expect(saved['resumes'][second.id].single['milliseconds'], 9000);
        expect(await records.hasPendingUploads(alice.scope.key), isFalse);
        expect(await File.fromUri(paths.last).exists(), isFalse);
        expect(catalog.books, isEmpty);
      });

      test('clear uploads before deleting and retains all personal records across restart', () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        upload = () async {
          entered.complete();
          await release.future;
        };
        var completed = false;
        final clearing = clear().then((_) => completed = true);
        await entered.future;
        try {
          expect(completed, isFalse);
          await expectFilesKept();
          expect(catalog.clearingNotifier.value, isTrue);
        } finally {
          release.complete();
          await clearing;
        }
        expect(await downloaded.exists(), isFalse);
        expect(await bobDownloaded.readAsBytes(), [1, 2, 3, 4, 5, 6]);
        expect(await cache.read(alice.scope), isNull);
        expect(await cache.read(bob.scope), isNotNull);
        online = false;
        expect(await covers.load(alice, cover), isNull);
        expect(await covers.load(bob, cover), [1, 2, 3]);
        expect(sent, [alice.scope.key]);
        final reopened = await reopenedRecords();
        for (final who in [alice, bob]) {
          final saved = (await reopened.read(who.scope.key))!;
          expect(
            saved['bookmarks'].single['title'],
            '${who.username} bookmark',
          );
          expect(saved['history'].single['id'], 'move');
          expect(saved['resumes']['edition'].single['milliseconds'], 5000);
        }
        expect(await reopened.hasPendingUploads(alice.scope.key), isFalse);
        expect(await reopened.hasPendingUploads(bob.scope.key), isTrue);
        expect(credentials.value, same(alice));
        expect(
          (await SharedPreferences.getInstance()).getString(
            'bookfin.appearance.test',
          ),
          'night',
        );
        await catalog.restore();
        expect(catalog.books, isEmpty);
        expect(catalog.hasCatalog, isFalse);
      });

      for (final fails in [false, true]) {
        test(
          'records made while a file is held ${fails ? 'stop removal on upload failure' : 'upload before its release'}',
          () async {
            final release = Completer<void>();
            final initialUpload = Completer<void>();
            upload = () async {
              if (!initialUpload.isCompleted) initialUpload.complete();
            };
            await downloads.readLocalFile(
              catalog.books.single.editions.single.files.single,
              (original) async {
                unawaited(original.hold(() => release.future));
              },
            );
            final clearing = clear();
            final outcome = fails
                ? expectLater(clearing, throwsA(isA<Exception>()))
                : clearing;
            await initialUpload.future;
            await downloads.removalEntered.future;
            await records.write(alice.scope.key, {
              ...(await records.read(alice.scope.key))!,
              'bookmarks': [bookmark('during-wait', title: 'During wait')],
            });
            upload = () async {
              expect(await downloaded.exists(), isTrue);
              if (fails) throw const SocketException('offline after waiting');
            };
            release.complete();
            await outcome;
            expect(await downloaded.exists(), fails);
            expect(await records.hasPendingUploads(alice.scope.key), fails);
            expect(
              (await records.read(
                alice.scope.key,
              ))!['bookmarks'].single['title'],
              'During wait',
            );
          },
        );
      }

      test(
        'a live save failure during the final upload stops removal until retry',
        () async {
          final playerFiles = audio.LocalFiles();
          final player = Playback(
            downloads: playerFiles,
            engine: audio.TestEngine(),
            store: records,
          );
          addTearDown(playerFiles.dispose);
          addTearDown(player.close);
          await player.bind(alice, [audio.title]);
          await player.open(audio.title, audio.recording, autoplay: false);
          await player.flush();
          final sql = await phone?.separateConnection();
          final releaseFile = Completer<void>();
          final uploadEntered = Completer<void>();
          final releaseUpload = Completer<void>();
          await downloads.readLocalFile(
            catalog.books.single.editions.single.files.single,
            (original) async {
              unawaited(original.hold(() => releaseFile.future));
            },
          );
          final clearing = clear();
          final outcome = expectLater(clearing, throwsA(isA<Exception>()));
          await downloads.removalEntered.future;
          await records.write(alice.scope.key, {
            ...(await records.read(alice.scope.key))!,
            'bookmarks': [bookmark('while-held', title: 'While held')],
          });
          upload = () async {
            uploadEntered.complete();
            await releaseUpload.future;
          };
          releaseFile.complete();
          await uploadEntered.future;
          try {
            preferences.refuseTitle = 'During upload';
            await sql?.execute(
              "CREATE TRIGGER refuse_save BEFORE INSERT ON record_actions BEGIN SELECT RAISE(ABORT, 'storage full'); END",
            );
            await player.addBookmark(title: 'During upload');
            expect(player.unsavedChanges, isTrue);
            releaseUpload.complete();
            await outcome;
            await expectFilesKept();
            expect(player.unsavedChanges, isTrue);
          } finally {
            preferences.refuseTitle = null;
            await sql?.execute('DROP TRIGGER IF EXISTS refuse_save');
            if (!releaseUpload.isCompleted) releaseUpload.complete();
          }
          upload = null;
          await clear();
          expect(await downloaded.exists(), isFalse);
          expect(player.unsavedChanges, isFalse);
          expect(await records.hasPendingUploads(alice.scope.key), isFalse);
          expect(
            (await records.read(
              alice.scope.key,
            ))!['bookmarks'].map((dynamic entry) => entry['title']),
            contains('During upload'),
          );
        },
      );

      test('downloads stay blocked while cover removal waits', () async {
        final fetchEntered = Completer<void>();
        final releaseFetch = Completer<void>();
        final observed = _ObservedCovers(
          root: covers.root,
          fetch: (_, _) async {
            fetchEntered.complete();
            await releaseFetch.future;
            return Uint8List.fromList([4]);
          },
        );
        covers = observed;
        final loading = covers.load(alice, const CoverRef('held', 'v1'));
        await fetchEntered.future;
        final edition = catalog.books.single.editions.single;
        final clearing = clear();
        await observed.clearEntered.future;
        try {
          expect(await downloaded.exists(), isFalse);
          expect(catalog.books, isNotEmpty);
          await expectLater(
            downloads.request(edition),
            throwsA(isA<Exception>()),
          );
        } finally {
          releaseFetch.complete();
          await loading;
          await clearing;
        }
        expect(await downloaded.exists(), isFalse);
      });

      test(
        'covers and downloads stay blocked until cleared catalog is published',
        () async {
          catalogFiles.holdRemoval = true;
          final edition = catalog.books.single.editions.single;
          final clearing = clear();
          await catalogFiles.removeEntered.future;
          try {
            expect(catalog.books, isNotEmpty);
            expect(
              await covers.load(alice, const CoverRef('late', 'v1')),
              isNull,
            );
            expect(
              await covers.blurred(alice, const CoverRef('late-blur', 'v1')),
              isNull,
            );
            await expectLater(
              downloads.request(edition),
              throwsA(isA<Exception>()),
            );
          } finally {
            catalogFiles.releaseRemoval.complete();
            await clearing;
          }
          expect(catalog.books, isEmpty);
          online = false;
          expect(
            await covers.load(alice, const CoverRef('late', 'v1')),
            isNull,
          );
          expect(await downloaded.exists(), isFalse);
        },
      );

      test(
        'a cache removal failure releases file protection and permits retry',
        () async {
          catalogFiles.failRemoval = true;
          await expectLater(clear(), throwsA(isA<FileSystemException>()));
          expect(catalog.clearingNotifier.value, isFalse);
          expect(await cache.read(alice.scope), isNotNull);
          final edition = catalog.books.single.editions.single;
          await downloads.request(edition);
          await downloads.idle;
          expect(await downloaded.exists(), isTrue);
          expect(await covers.load(alice, cover), [1, 2, 3]);
          catalogFiles.failRemoval = false;
          await clear();
          expect(await downloaded.exists(), isFalse);
          expect(await cache.read(alice.scope), isNull);
        },
      );

      for (final step in ['save', 'upload']) {
        test('required $step failure prevents every removal', () async {
          if (step == 'save') {
            records.registerWriter(
              account: () => alice.scope.key,
              flush: () async => throw const FileSystemException('full'),
              refresh: () async {},
            );
          } else {
            upload = () async => throw const SocketException('offline');
          }
          await expectLater(clear(), throwsA(isA<Exception>()));
          await expectFilesKept();
          expect(await records.hasPendingUploads(alice.scope.key), isTrue);
          expect(catalog.clearingNotifier.value, isFalse);
        });
      }

      for (final step in ['save', 'upload', 'read', 'cover', 'cache']) {
        for (final replacement in [false, true]) {
          test(
            '${replacement ? 'replacement' : 'switch'} during $step cannot clear the next account',
            () async {
              final entered = Completer<void>();
              final release = Completer<void>();
              Future<void> hold() async {
                if (!entered.isCompleted) entered.complete();
                await release.future;
              }

              if (step == 'save') {
                records.registerWriter(
                  account: () => alice.scope.key,
                  flush: hold,
                  refresh: () async {},
                );
              } else if (step == 'upload') {
                upload = hold;
              } else if (step == 'read') {
                await downloads.readLocalFile(
                  catalog.books.single.editions.single.files.single,
                  (file) async {
                    unawaited(file.hold(hold));
                  },
                );
              } else if (step == 'cache') {
                catalogFiles.holdRemoval = true;
                unawaited(
                  catalogFiles.removeEntered.future.then((_) async {
                    await hold();
                    catalogFiles.releaseRemoval.complete();
                  }),
                );
              } else {
                covers = DiskCovers(
                  root: covers.root,
                  fetch: (_, _) async {
                    await hold();
                    return Uint8List.fromList([4]);
                  },
                );
                unawaited(
                  covers.load(alice, const CoverRef('new-cover', 'v1')),
                );
              }
              final clearing = clear();
              final outcome = expectLater(clearing, throwsA(isA<Exception>()));
              await entered.future;
              if (step == 'read' || step == 'cover') {
                // Let required upload reach the held file owner.
                while (sent.isEmpty) {
                  await Future<void>.delayed(Duration.zero);
                }
              }
              final next = replacement ? media.session() : bob;
              credentials.value = next;
              final restoring = catalog.restore();
              // Restore publishes the next credential before awaiting its cache.
              while (catalog.session?.credentialIdentity !=
                  next.credentialIdentity) {
                await Future<void>.delayed(Duration.zero);
              }
              release.complete();
              await outcome;
              await restoring;
              await downloads.idle;
              expect(await bobDownloaded.readAsBytes(), [1, 2, 3, 4, 5, 6]);
              expect(await cache.read(bob.scope), isNotNull);
              online = false;
              // Use the original cover store, without fetching replacement data.
              final disk = DiskCovers(
                root: covers.root,
                fetch: (_, _) async => null,
              );
              expect(await disk.load(bob, cover), [1, 2, 3]);
              expect(await records.read(bob.scope.key), isNotNull);
              if (step == 'save' || step == 'upload' || step == 'read') {
                expect(await downloaded.exists(), isTrue);
              }
            },
          );
        }
      }
    });
  }
}

/// Observes entry to the real public removal boundary without replacing it.
class _ObservedDownloads extends LocalDownloads {
  _ObservedDownloads({
    required super.root,
    required super.freeBytes,
    required super.policy,
  });
  final removalEntered = Completer<void>();
  @override
  Future<void> remove(Edition edition) {
    final removal = super.remove(edition);
    if (!removalEntered.isCompleted) removalEntered.complete();
    return removal;
  }
}

class _FailingPreferences extends SharedPreferencesStorePlatform {
  final values = <String, Object>{'flutter.bookfin.appearance.test': 'night'};
  String? refuseTitle;
  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (refuseTitle != null &&
        value is String &&
        value.contains(refuseTitle!)) {
      throw const FileSystemException('storage full');
    }
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async => throw UnimplementedError();
}

class _HeldCatalogFiles extends DiskCatalogFiles {
  _HeldCatalogFiles(super.root);
  bool holdRemoval = false;
  bool failRemoval = false;
  final removeEntered = Completer<void>();
  final releaseRemoval = Completer<void>();
  @override
  Future<void> remove(String key) async {
    if (holdRemoval) {
      removeEntered.complete();
      await releaseRemoval.future;
    }
    if (failRemoval) throw const FileSystemException('cache is unavailable');
    await super.remove(key);
  }
}

class _ObservedCovers extends DiskCovers {
  _ObservedCovers({required super.root, required super.fetch});
  final clearEntered = Completer<void>();
  @override
  Future<void> clear(
    AccountScope account, {
    Future<void> Function()? afterRemoval,
  }) {
    clearEntered.complete();
    return super.clear(account, afterRemoval: afterRemoval);
  }
}
