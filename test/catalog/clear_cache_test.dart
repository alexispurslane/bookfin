import 'dart:async';
import 'dart:io';

import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/catalog_files_io.dart';
import 'package:bookfin/catalog/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'controller_test.dart';
import 'file_store_test.dart' show ControlledFiles;
import 'model_test.dart' show entry;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final disk in [false, true]) {
    group(disk ? 'disk saved library' : 'preferences saved library', () {
      late Directory root;
      late LocalCatalogStore store;
      late MemoryCredentials credentials;
      late CatalogController catalog;
      late FixtureClient client;
      late ControlledFiles files;
      setUp(() async {
        final previous = SharedPreferencesAsyncPlatform.instance;
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
        root = await Directory.systemTemp.createTemp('clear-catalog-');
        files = ControlledFiles(DiskCatalogFiles(root));
        store = disk
            ? LocalCatalogStore(files: files)
            : LocalCatalogStore.preferences();
        credentials = MemoryCredentials()..value = account('alice');
        for (final who in ['alice', 'bob']) {
          final scope = account(who).scope;
          await store.write(
            scope,
            CatalogCache(
              scope: scope,
              entries: [entry(who)],
              libraries: [const BookLibrary('books', 'Books')],
            ).encode(),
          );
        }
        client = FixtureClient(credentials.value!.scope.server);
        catalog = CatalogController(
          credentials: credentials,
          store: store,
          clientFactory: (_, _) => client,
        );
        await catalog.restore();
      });
      tearDown(() async {
        catalog.dispose();
        client.close();
        await root.delete(recursive: true);
      });

      test('clear removes only the confirmed saved library and preserves login on restart', () async {
        await catalog.clearSavedLibrary(
          catalog.session!,
          beforeClear: (_) async {},
        );
        expect(await store.read(account('alice').scope), isNull);
        expect(await store.read(account('bob').scope), isNotNull);
        expect(credentials.value?.username, 'alice');
        await catalog.restore();
        expect(catalog.hasCatalog, isFalse);
        expect(catalog.books, isEmpty);
      });

      test(
        'a required preservation failure leaves the saved catalog',
        () async {
          await expectLater(
            catalog.clearSavedLibrary(
              catalog.session!,
              beforeClear: (_) async {
                throw const FileSystemException('save failed');
              },
            ),
            throwsA(isA<Exception>()),
          );
          expect(await store.read(account('alice').scope), isNotNull);
        },
      );

      if (disk) {
        test('clear waits for an already started atomic cache write and removes its result', () async {
          files.pauseWrite = true;
          final refreshing = catalog.refresh();
          await files.entered.future;
          var cleared = false;
          final clearing = catalog
              .clearSavedLibrary(catalog.session!, beforeClear: (_) async {})
              .then((_) => cleared = true);
          try {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            expect(cleared, isFalse);
          } finally {
            files.release.complete();
          }
          await refreshing;
          await clearing;
          expect(await store.read(account('alice').scope), isNull);
          await catalog.restore();
          expect(catalog.books, isEmpty);
        });
      }

      test(
        'clear waits for preservation and rejects late refresh results',
        () async {
          // A real refresh is paused at the network boundary.
          client.pendingCatalog = Completer();
          final refreshing = catalog.refresh();
          while (client.catalogReads == 0) {
            await Future<void>.delayed(Duration.zero);
          }
          final entered = Completer<void>();
          final release = Completer<void>();
          var cleared = false;
          final clearing = catalog
              .clearSavedLibrary(
                catalog.session!,
                beforeClear: (_) async {
                  entered.complete();
                  await release.future;
                },
              )
              .then((_) => cleared = true);
          await Future.any([entered.future, clearing]);
          expect(cleared, isFalse);
          await catalog.refresh();
          expect(client.catalogReads, 1);
          release.complete();
          await clearing;
          client.pendingCatalog!.complete([entry('stale')]);
          await refreshing;
          expect(await store.read(account('alice').scope), isNull);
          expect(catalog.books, isEmpty);
          catalog.checkInvariants();
        },
      );
    });
  }
}
