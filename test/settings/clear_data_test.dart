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
import 'package:bookfin/settings/clear_data.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../catalog/controller_test.dart' show FixtureClient, MemoryCredentials;
import '../downloads/transfer_test.dart' show MediaFixture;
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
        cache = LocalCatalogStore(
          files: DiskCatalogFiles(Directory('${root.path}/catalog')),
        );
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

      for (final step in ['save', 'upload', 'read', 'cover']) {
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
