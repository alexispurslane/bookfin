import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/catalog_files.dart';
import 'package:bookfin/catalog/catalog_files_io.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'controller_test.dart' show account, FixtureClient, MemoryCredentials;
import 'file_store_test.dart'
    show LegacyPreferences, committedFile, legacyKey, legacyCatalog;
import 'model_test.dart' show entry;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late DiskCatalogFiles disk;
  late LocalCatalogStore store;
  late FixtureClient client;
  late MemoryCredentials credentials;
  late SharedPreferencesAsync preferences;
  final scope = account('alice').scope;

  CatalogController controller({LocalCatalogStore? storage}) {
    final result = CatalogController(
      credentials: credentials,
      store: storage ?? store,
      clientFactory: (_, _) => client,
    );
    addTearDown(result.dispose);
    return result;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookfin-choices-');
    disk = DiskCatalogFiles(root);
    store = LocalCatalogStore(files: disk);
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = LegacyPreferences();
    preferences = SharedPreferencesAsync();
    credentials = MemoryCredentials()..value = account('alice');
    client = FixtureClient(scope.server)
      ..views = [
        const BookLibrary('books', 'Books'),
        const BookLibrary('hidden', 'Hidden'),
      ];
    addTearDown(() async {
      client.close();
      SharedPreferencesAsyncPlatform.instance = previous;
      await root.delete(recursive: true);
    });
  });

  for (final damage in ['missing', 'corrupt']) {
    test(
      'choices survive a $damage server cache and a real-file reopen',
      () async {
        final first = controller();
        await first.restore();
        await first.refresh();
        await first.correctBook(
          'book:one',
          const BookDetails(title: 'My title', author: 'Me'),
        );
        await first.refresh(hidden: {'hidden'}, byUser: true);
        final file = committedFile(disk, legacyKey('alice'));
        if (damage == 'missing') {
          await file.delete();
        } else {
          await file.writeAsString('{broken');
        }
        final reopened = controller(
          storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
        );
        await reopened.restore();
        await reopened.refresh(byUser: true);
        expect(reopened.books.single.title, 'My title');
        expect(reopened.accountNotifier.value.hidden, {'hidden'});
        reopened.checkInvariants();
        await store.checkInvariants();
      },
    );
  }

  test(
    'replacing a legacy catalog commits its choices before overwriting it',
    () async {
      final legacy = legacyCatalog(
        scope: scope,
        libraries: client.views,
        hidden: {'hidden'},
        entries: [entry('one')],
        edits: CatalogEdits(
          details: {
            'book:one': const BookDetails(title: 'Legacy title', author: 'Me'),
          },
        ),
      );
      await preferences.setString(legacyKey('alice'), legacy);
      await store.write(
        scope,
        CatalogCache(
          scope: scope,
          libraries: client.views,
          entries: [entry('one')],
        ).encode(),
      );
      await store.migrateLegacy();
      final reopened = controller(
        storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
      );
      await reopened.restore();
      expect(reopened.books.single.title, 'Legacy title');
      expect(reopened.accountNotifier.value.hidden, {'hidden'});
      expect(await preferences.getString(legacyKey('alice')), isNull);
    },
  );

  test(
    'refresh retains unreadable legacy bytes outside the replacement catalog',
    () async {
      await disk.write(legacyKey('alice'), '{broken legacy corrections');
      final catalog = controller();
      await catalog.restore();
      expect(catalog.message, isNotNull);
      await catalog.refresh(byUser: true);
      expect(catalog.books.single.title, 'The Orchard');
      final retained = await root
          .list()
          .where(
            (file) =>
                file is File &&
                file.path != committedFile(disk, legacyKey('alice')).path,
          )
          .cast<File>()
          .toList();
      expect(
        await Future.wait(retained.map((file) => file.readAsString())),
        contains('{broken legacy corrections'),
      );
      expect(catalog.message, isNotNull);
    },
  );

  test(
    'hiding a known library saves only choices without fetching server entries',
    () async {
      final counted = CountingFiles(disk);
      store = LocalCatalogStore(files: counted);
      final catalog = controller();
      await catalog.restore();
      await catalog.refresh();
      final requests = client.catalogReads;
      counted.writes.clear();
      await catalog.refresh(hidden: {'books'}, byUser: true);
      expect(catalog.books, isEmpty);
      expect(client.catalogReads, requests);
      expect(counted.writes.keys, isNot(contains(legacyKey('alice'))));
      final reopened = controller(
        storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
      );
      await reopened.restore();
      expect(reopened.books, isEmpty);
      await reopened.refresh(hidden: {}, byUser: true);
      expect(reopened.books.single.title, 'The Orchard');
      expect(client.catalogReads, requests);
    },
  );

  test('a failed choice commit leaves the previous choices after reopen and can retry', () async {
    final catalog = controller();
    await catalog.restore();
    await catalog.refresh();
    final file = committedFile(disk, choiceKey(scope));
    await Directory('${file.path}.partial').create();
    await catalog.correctBook(
      'book:one',
      const BookDetails(title: 'Uncommitted', author: 'Me'),
    );
    expect(catalog.message, contains('not saved'));
    expect(catalog.books.single.title, 'The Orchard');
    final reopened = controller(
      storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
    );
    await reopened.restore();
    expect(reopened.books.single.title, 'The Orchard');
    await Directory('${file.path}.partial').delete();
    await catalog.correctBook(
      'book:one',
      const BookDetails(title: 'Committed', author: 'Me'),
    );
    final retried = controller(
      storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
    );
    await retried.restore();
    expect(retried.books.single.title, 'Committed');
  });

  test(
    'an interrupted first choice commit keeps legacy choices for restart',
    () async {
      final text = legacyCatalog(
        scope: scope,
        libraries: client.views,
        entries: [entry('one')],
        edits: CatalogEdits(
          details: {
            'book:one': const BookDetails(title: 'Only copy', author: 'Me'),
          },
        ),
      );
      await disk.write(legacyKey('alice'), text);
      final file = committedFile(disk, choiceKey(scope));
      await File('${file.path}.partial').writeAsString('incomplete');
      final catalog = controller(
        storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
      );
      await catalog.restore();
      expect(catalog.books.single.title, 'Only copy');
      expect(
        (await store.readChoices(scope)).edits.details['book:one']!.title,
        'Only copy',
      );
    },
  );

  test('migration commits choices for inactive preference accounts before removing them', () async {
    final bob = account('bob').scope;
    await preferences.setString(
      legacyKey('bob'),
      legacyCatalog(
        scope: bob,
        libraries: client.views,
        entries: [entry('one')],
        hidden: {'hidden'},
        edits: CatalogEdits(
          details: {
            'book:one': const BookDetails(title: 'Bobs title', author: 'Bob'),
          },
        ),
      ),
    );
    await store.migrateLegacy();
    expect(await preferences.getString(legacyKey('bob')), isNull);
    await committedFile(disk, legacyKey('bob')).delete();
    credentials.value = account('bob');
    final catalog = controller(
      storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
    );
    await catalog.restore();
    await catalog.refresh();
    expect(catalog.books.single.title, 'Bobs title');
    expect(catalog.accountNotifier.value.hidden, {'hidden'});
    credentials.value = account('alice');
    await catalog.restore();
    await catalog.refresh();
    expect(catalog.books.single.title, 'The Orchard');
    expect(catalog.accountNotifier.value.hidden, isEmpty);
  });

  test('new corrections win when migration overlaps and retained legacy remains after restart', () async {
    final legacy = legacyCatalog(
      scope: scope,
      libraries: client.views,
      entries: [entry('one')],
      edits: CatalogEdits(
        details: {'book:one': const BookDetails(title: 'Old', author: 'Me')},
      ),
    );
    await preferences.setString(legacyKey('alice'), legacy);
    final controlled = CountingFiles(disk)..pauseKey = choiceKey(scope);
    store = LocalCatalogStore(files: controlled);
    final migration = store.migrateLegacy();
    await controlled.entered.future;
    final writing = store.writeChoices(
      scope,
      CatalogChoices(
        edits: CatalogEdits(
          details: {'book:one': const BookDetails(title: 'New', author: 'Me')},
        ),
      ),
    );
    controlled.release.complete();
    await Future.wait([migration, writing]);
    // Simulate interrupted legacy cleanup on the next launch.
    await preferences.setString(legacyKey('alice'), legacy);
    final reopened = LocalCatalogStore(files: DiskCatalogFiles(root));
    await reopened.migrateLegacy();
    final catalog = controller(storage: reopened);
    await catalog.restore();
    expect(catalog.books.single.title, 'New');
    await catalog.resetCorrections();
    await preferences.setString(legacyKey('alice'), legacy);
    final reset = controller(
      storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
    );
    await reset.restore();
    expect(reset.books.single.title, 'The Orchard');
  });

  for (final bytes in [
    utf8.encode('{unknown legacy'),
    [0xff, 0xfe],
  ]) {
    test(
      'refresh preserves exact legacy bytes ${bytes.length} through restart',
      () async {
        await committedFile(disk, legacyKey('alice')).writeAsBytes(bytes);
        final catalog = controller();
        await catalog.restore();
        expect(catalog.message, isNotNull);
        await catalog.refresh();
        expect(catalog.books.single.title, 'The Orchard');
        final files = await root
            .list()
            .where((file) => file.path.contains('.unreadable.'))
            .cast<File>()
            .toList();
        expect(
          await Future.wait(files.map((file) => file.readAsBytes())),
          contains(equals(bytes)),
        );
        final reopened = controller(
          storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
        );
        await reopened.restore();
        expect(reopened.books.single.title, 'The Orchard');
        expect(reopened.message, contains('kept for recovery'));
      },
    );
  }

  test('unknown committed choices are retained and reported instead of reviving older corrections', () async {
    await preferences.setString(
      legacyKey('alice'),
      legacyCatalog(
        scope: scope,
        libraries: client.views,
        entries: [entry('one')],
        edits: CatalogEdits(
          details: {
            'book:one': const BookDetails(title: 'Stale', author: 'Me'),
          },
        ),
      ),
    );
    final future = jsonEncode({
      'version': 99,
      'scope': scope.toJson(),
      'newChoices': 'keep me',
    });
    await disk.write(choiceKey(scope), future);
    final catalog = controller();
    await catalog.restore();
    expect(catalog.books.single.title, 'The Orchard');
    expect(catalog.message, contains('kept for recovery'));
    final files = await root
        .list()
        .where((file) => file.path.contains('.unreadable.'))
        .cast<File>()
        .toList();
    expect(
      await Future.wait(files.map((file) => file.readAsString())),
      contains(future),
    );
  });

  test('a failed first choice migration prevents replacement and retries from the sole legacy copy', () async {
    final legacy = legacyCatalog(
      scope: scope,
      libraries: client.views,
      entries: [entry('one')],
      edits: CatalogEdits(
        details: {
          'book:one': const BookDetails(title: 'Only copy', author: 'Me'),
        },
      ),
    );
    await preferences.setString(legacyKey('alice'), legacy);
    final file = committedFile(disk, choiceKey(scope));
    await Directory('${file.path}.partial').create();
    final replacement = CatalogCache(
      scope: scope,
      libraries: client.views,
      entries: [entry('one')],
    ).encode();
    await expectLater(
      store.write(scope, replacement),
      throwsA(isA<FileSystemException>()),
    );
    expect(await preferences.getString(legacyKey('alice')), legacy);
    expect(await disk.read(legacyKey('alice')), isNull);
    await Directory('${file.path}.partial').delete();
    await store.write(scope, replacement);
    await store.migrateLegacy();
    final reopened = controller(
      storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
    );
    await reopened.restore();
    expect(reopened.books.single.title, 'Only copy');
  });

  test('failure to retain unreadable bytes prevents refresh replacement until retry', () async {
    const damaged = '{unextractable choices';
    await disk.write(legacyKey('alice'), damaged);
    final controlled = CountingFiles(disk)..failPreserve = true;
    store = LocalCatalogStore(files: controlled);
    final catalog = controller();
    await catalog.restore();
    await catalog.refresh(byUser: true);
    expect(catalog.books, isEmpty);
    expect(catalog.message, isNotNull);
    expect(await disk.read(legacyKey('alice')), damaged);
    controlled.failPreserve = false;
    await catalog.refresh(byUser: true);
    expect(catalog.books.single.title, 'The Orchard');
    final files = await root
        .list()
        .where((file) => file.path.contains('.unreadable.'))
        .cast<File>()
        .toList();
    expect(
      await Future.wait(files.map((file) => file.readAsString())),
      contains(damaged),
    );
  });

  test('an account switch during a choice commit never adopts the former accounts choices', () async {
    final controlled = CountingFiles(disk);
    store = LocalCatalogStore(files: controlled);
    final catalog = controller();
    await catalog.restore();
    await catalog.refresh();
    controlled.pauseKey = choiceKey(scope);
    final editing = catalog.correctBook(
      'book:one',
      const BookDetails(title: 'Alice only', author: 'Alice'),
    );
    await controlled.entered.future;
    await catalog.signOut();
    final switching = catalog.connect(
      'https://books.example',
      'bob',
      'password',
    );
    controlled.release.complete();
    await Future.wait([editing, switching]);
    expect(catalog.session!.scope.userId, 'bob');
    expect(catalog.books.single.title, 'The Orchard');
    catalog.checkInvariants();
    credentials.value = account('alice');
    final reopened = controller(
      storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
    );
    await reopened.restore();
    expect(reopened.books.single.title, 'Alice only');
  });

  test('a choice committed during a pending server response wins after refresh and reopen', () async {
    final requested = SignalledClient(scope.server)..views = client.views;
    client = requested;
    final catalog = controller();
    await catalog.restore();
    await catalog.refresh();
    requested.pendingCatalog = Completer();
    requested.requested = Completer();
    final refreshing = catalog.refresh();
    await requested.requested!.future;
    await catalog.correctBook(
      'book:one',
      const BookDetails(title: 'New choice', author: 'Me'),
    );
    requested.pendingCatalog!.complete([entry('one', title: 'Server title')]);
    await refreshing;
    final reopened = controller(
      storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
    );
    await reopened.restore();
    expect(reopened.books.single.title, 'New choice');
  });

  test('a correction queued behind a server write uses the adopted entries and preserves its choices', () async {
    final controlled = CountingFiles(disk);
    store = LocalCatalogStore(files: controlled);
    final catalog = controller();
    await catalog.restore();
    await catalog.refresh();
    controlled.pauseKey = legacyKey('alice');
    client.entries = [
      entry('one', title: 'Server title'),
      entry('two', title: 'Added'),
    ];
    final refreshing = catalog.refresh();
    await controlled.entered.future;
    final correcting = catalog.correctBook(
      'book:one',
      const BookDetails(title: 'My title', author: 'Me'),
    );
    controlled.release.complete();
    await Future.wait([refreshing, correcting]);
    final reopened = controller(
      storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
    );
    await reopened.restore();
    expect(
      reopened.books.map((book) => book.title),
      containsAll(['My title', 'Added']),
    );
    reopened.checkInvariants();
  });

  test('links recording groups file order and details survive dropping the server cache', () async {
    client.entries = [
      entry('one'),
      entry('two', track: 2),
      entry('text', type: 'Book'),
    ];
    final catalog = controller();
    await catalog.restore();
    await catalog.refresh();
    await catalog.linkBooks('book:two', 'book:one');
    await catalog.linkBooks('book:text', 'book:one');
    await catalog.combineAudio('book:one', ['one:source', 'two:source']);
    await catalog.orderFiles('one:source', ['two:source', 'one:source']);
    await catalog.correctBook(
      'book:one',
      const BookDetails(
        title: 'Complete',
        author: 'Me',
        series: 'Series',
        seriesOrder: 1.5,
      ),
    );
    await committedFile(disk, legacyKey('alice')).delete();
    final reopened = controller(
      storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
    );
    await reopened.restore();
    await reopened.refresh();
    final book = reopened.books.single;
    expect(book.title, 'Complete');
    expect(book.seriesOrder, 1.5);
    expect(book.editions, hasLength(2));
    expect(
      book.editions
          .firstWhere((edition) => edition.kind == EditionKind.audio)
          .files
          .map((file) => file.itemId),
      ['two', 'one'],
    );
  });

  test('saving existing choices after reopening storage never reads the server catalog', () async {
    final catalog = controller();
    await catalog.restore();
    await catalog.refresh();
    final counted = CountingFiles(DiskCatalogFiles(root));
    final reopened = LocalCatalogStore(files: counted);
    final choices = await reopened.readChoices(scope);
    await reopened.writeChoices(scope, choices.change(hidden: {'hidden'}));
    expect(counted.reads, isNot(contains(legacyKey('alice'))));
    expect(counted.writes.keys, isNot(contains(legacyKey('alice'))));
    expect((await LocalCatalogStore(files: disk).readChoices(scope)).hidden, {
      'hidden',
    });
  });

  for (final damage in ['missing correction map', 'unknown detail field']) {
    test('$damage in committed choices is retained and reported', () async {
      final choices = jsonDecode(
        CatalogChoices(
          edits: CatalogEdits(
            details: {
              'book:one': const BookDetails(title: 'Known', author: 'Me'),
            },
          ),
        ).encode(scope),
      ) as Map<String, dynamic>;
      final edits = choices['edits'] as Map<String, dynamic>;
      if (damage == 'missing correction map') {
        edits.remove('books');
      } else {
        (edits['details']['book:one']
                as Map<String, dynamic>)['futureMeaning'] =
            'keep';
      }
      final text = jsonEncode(choices);
      await disk.write(choiceKey(scope), text);
      final catalog = controller();
      await catalog.restore();
      await catalog.refresh();
      expect(catalog.message, contains('kept for recovery'));
      final files = await root
          .list()
          .where((file) => file.path.contains('.unreadable.'))
          .cast<File>()
          .toList();
      expect(
        await Future.wait(files.map((file) => file.readAsString())),
        contains(text),
      );
    });
  }

  test('legacy text whose entries cannot build is retained while readable choices survive', () async {
    final broken = CatalogEntry.fromJson({
      ...entry('one').json,
      'MediaSources': 'broken',
    }, libraryId: 'books');
    final text = legacyCatalog(
      scope: scope,
      libraries: client.views,
      entries: [broken],
      edits: CatalogEdits(
        details: {
          'book:one': const BookDetails(title: 'Salvaged', author: 'Me'),
        },
      ),
    );
    await disk.write(legacyKey('alice'), text);
    final catalog = controller();
    await catalog.restore();
    expect(catalog.message, isNotNull);
    await catalog.refresh(byUser: true);
    expect(catalog.books.single.title, 'Salvaged');
    final files = await root
        .list()
        .where((file) => file.path.contains('.unreadable.'))
        .cast<File>()
        .toList();
    expect(
      await Future.wait(files.map((file) => file.readAsString())),
      contains(text),
    );
    expect(catalog.message, contains('kept for recovery'));
  });

  test('a fetched empty library is remembered so later visibility changes stay local', () async {
    await store.writeChoices(scope, CatalogChoices(hidden: {'hidden'}));
    final catalog = controller();
    await catalog.restore();
    await catalog.refresh();
    final before = client.catalogReads;
    await catalog.refresh(hidden: {}, byUser: true);
    expect(client.catalogReads, before + 1);
    await catalog.refresh(hidden: {'hidden'}, byUser: true);
    await catalog.refresh(hidden: {}, byUser: true);
    expect(client.catalogReads, before + 1);
  });

  test('launch migration extracts inactive native accounts before their caches can be lost', () async {
    final bob = account('bob').scope;
    await disk.write(
      legacyKey('bob'),
      legacyCatalog(
        scope: bob,
        libraries: client.views,
        entries: [entry('one')],
        hidden: {'hidden'},
        edits: CatalogEdits(
          details: {
            'book:one': const BookDetails(title: 'Native Bob', author: 'Bob'),
          },
        ),
      ),
    );
    await store.migrateLegacy();
    await committedFile(disk, legacyKey('bob')).delete();
    credentials.value = account('bob');
    final reopened = controller(
      storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
    );
    await reopened.restore();
    await reopened.refresh();
    expect(reopened.books.single.title, 'Native Bob');
    expect(reopened.accountNotifier.value.hidden, {'hidden'});
  });

  test(
    'native discovery failure does not strand retained preference accounts',
    () async {
      final bob = account('bob').scope;
      await preferences.setString(
        legacyKey('bob'),
        legacyCatalog(
          scope: bob,
          libraries: client.views,
          entries: [entry('one')],
          edits: CatalogEdits(
            details: {
              'book:one': const BookDetails(title: 'Preserved', author: 'Bob'),
            },
          ),
        ),
      );
      final counted = CountingFiles(disk)..failScan = true;
      await expectLater(
        LocalCatalogStore(files: counted).migrateLegacy(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await preferences.getString(legacyKey('bob')), isNull);
      expect(
        (await LocalCatalogStore(files: disk).readChoices(bob))
            .edits
            .details['book:one']!
            .title,
        'Preserved',
      );
    },
  );

  test('an invalid legacy account identity reports failure without stranding another account', () async {
    final invalid = 'bookfin.catalog.v1.${base64Url.encode(utf8.encode('{}'))}';
    await preferences.setString(invalid, 'unreadable identity');
    final bob = account('bob').scope;
    await preferences.setString(
      legacyKey('bob'),
      legacyCatalog(
        scope: bob,
        libraries: client.views,
        entries: [entry('one')],
      ),
    );
    await expectLater(store.migrateLegacy(), throwsFormatException);
    expect(await preferences.getString(invalid), 'unreadable identity');
    expect(await preferences.getString(legacyKey('bob')), isNull);
    expect(await disk.read(legacyKey('bob')), isNotNull);
  });

  test('browser migration saves inactive choices independently of preference caches', () async {
    final bob = account('bob').scope;
    await preferences.setString(
      legacyKey('bob'),
      legacyCatalog(
        scope: bob,
        libraries: client.views,
        entries: [entry('one')],
        hidden: {'hidden'},
        edits: CatalogEdits(
          details: {
            'book:one': const BookDetails(title: 'Browser Bob', author: 'Bob'),
          },
        ),
      ),
    );
    final browser = LocalCatalogStore.preferences();
    await browser.migrateLegacy();
    await preferences.remove(legacyKey('bob'));
    final reopened = LocalCatalogStore.preferences();
    final choices = await reopened.readChoices(bob);
    expect(choices.edits.details['book:one']?.title, 'Browser Bob');
    expect(choices.hidden, {'hidden'});
    await reopened.writeChoices(bob, choices.change(edits: CatalogEdits()));
    expect(
      (await LocalCatalogStore.preferences().readChoices(bob)).edits.details,
      isEmpty,
    );
  });

  test('a temporary choice read failure keeps the committed record intact for retry', () async {
    await store.writeChoices(
      scope,
      CatalogChoices(
        edits: CatalogEdits(
          details: {
            'book:one': const BookDetails(title: 'Durable', author: 'Me'),
          },
        ),
      ),
    );
    final before = await disk.read(choiceKey(scope));
    final counted = CountingFiles(disk)..failReadOnceKey = choiceKey(scope);
    final reopening = LocalCatalogStore(files: counted);
    await expectLater(
      reopening.readChoices(scope),
      throwsA(isA<FileSystemException>()),
    );
    expect(await disk.read(choiceKey(scope)), before);
    expect(
      (await reopening.readChoices(scope)).edits.details['book:one']?.title,
      'Durable',
    );
  });

  test('a temporary legacy read failure preserves its corrections until migration can retry', () async {
    final legacy = legacyCatalog(
      scope: scope,
      libraries: client.views,
      entries: [entry('one')],
      edits: CatalogEdits(
        details: {
          'book:one': const BookDetails(title: 'Only legacy', author: 'Me'),
        },
      ),
    );
    await disk.write(legacyKey('alice'), legacy);
    final counted = CountingFiles(disk)..failReadOnceKey = legacyKey('alice');
    final reopening = LocalCatalogStore(files: counted);
    await expectLater(
      reopening.readChoices(scope),
      throwsA(isA<FileSystemException>()),
    );
    expect(await disk.read(legacyKey('alice')), legacy);
    expect(await disk.read(choiceKey(scope)), isNull);
    expect(
      (await reopening.readChoices(scope)).edits.details['book:one']?.title,
      'Only legacy',
    );
  });

  test('access denial after an interrupted choice read adopts a coherent saved account', () async {
    final counted = CountingFiles(disk)..failReadOnceKey = choiceKey(scope);
    store = LocalCatalogStore(files: counted);
    client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
    final catalog = controller();
    await catalog.connect('https://books.example', 'alice', 'password');
    expect(catalog.accessBlocked, isTrue);
    expect(catalog.hasCatalog, isTrue);
    expect(catalog.checkInvariants, returnsNormally);
    final reopened = controller(
      storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
    );
    await reopened.restore();
    expect(reopened.accessBlocked, isTrue);
    reopened.checkInvariants();
  });

  test('a correction persists no server catalog bytes', () async {
    final counted = CountingFiles(disk);
    store = LocalCatalogStore(files: counted);
    client.entries = [
      for (var i = 0; i < 80; i++) entry('item$i', title: 'Book $i'),
    ];
    final catalog = controller();
    await catalog.restore();
    await catalog.refresh();
    final before = await disk.read(legacyKey('alice'));
    counted.writes.clear();
    await catalog.correctBook(
      'book:item1',
      const BookDetails(title: 'Corrected', author: 'Me'),
    );
    expect(catalog.books.map((book) => book.title), contains('Corrected'));
    expect(counted.writes.keys, isNot(contains(legacyKey('alice'))));
    expect(
      counted.writes.values.fold<int>(
        0,
        (sum, text) => sum + utf8.encode(text).length,
      ),
      lessThan(2000),
    );
    expect(await disk.read(legacyKey('alice')), before);
  });

  test('an obsolete account restore cannot adopt choices after waiting for a write', () async {
    final controlled = CountingFiles(disk);
    store = LocalCatalogStore(files: controlled);
    final signalled = SignalledCredentials()..value = account('alice');
    credentials = signalled;
    final bob = account('bob').scope;
    await store.writeChoices(bob, CatalogChoices(hidden: {'hidden'}));
    final catalog = controller();
    await catalog.restore();
    await catalog.refresh();
    controlled.pauseKey = choiceKey(scope);
    final editing = catalog.correctBook(
      'book:one',
      const BookDetails(title: 'Alice only', author: 'Alice'),
    );
    await controlled.entered.future;
    signalled.watchUser = 'alice';
    final obsolete = catalog.connect('https://books.example', 'alice', 'pw');
    await signalled.saved.future;
    // Drain the sign-in continuation into its pending catalog-write wait.
    // This is an event-queue barrier, not elapsed-time synchronization.
    await Future<void>(() {});
    catalog.cancel();
    controlled.pauseReadKey = choiceKey(scope);
    final switching = catalog.connect('https://books.example', 'bob', 'pw');
    controlled.release.complete();
    await switching;
    expect(catalog.session!.scope.userId, 'bob');
    expect(catalog.accountNotifier.value.hidden, {'hidden'});
    controlled.releaseRead.complete();
    await Future.wait([editing, obsolete]);
    expect(catalog.accountNotifier.value.hidden, {'hidden'});
    await catalog.correctBook(
      'book:one',
      const BookDetails(title: 'Bob only', author: 'Bob'),
    );
    final saved = await LocalCatalogStore(files: DiskCatalogFiles(root))
        .readChoices(bob);
    expect(saved.hidden, {'hidden'});
    expect(saved.edits.details['book:one']!.title, 'Bob only');
    catalog.checkInvariants();
  });

  test('a failed access recovery cache write keeps committed visibility coherent on retry', () async {
    final catalog = controller();
    await catalog.restore();
    await catalog.refresh();
    client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
    await catalog.refresh();
    expect(catalog.accessBlocked, isTrue);
    final partial = Directory(
      '${committedFile(disk, legacyKey('alice')).path}.partial',
    );
    await partial.create();
    client.failure = null;
    await catalog.refresh(hidden: {'books'}, byUser: true);
    expect(catalog.message, contains('not saved'));
    expect((await store.readChoices(scope)).hidden, {'books'});
    expect(catalog.accountNotifier.value.hidden, {'books'});
    catalog.checkInvariants();
    await partial.delete();
    await catalog.refresh(hidden: {'books'}, byUser: true);
    expect(catalog.verified, isTrue);
    expect(catalog.accountNotifier.value.hidden, {'books'});
    expect(catalog.books, isEmpty);
    final reopened = controller(
      storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
    );
    await reopened.restore();
    expect(reopened.books, isEmpty);
    catalog.checkInvariants();
  });

  test(
    'one unreadable native file cannot strand independent native choices',
    () async {
      final failed = committedFile(disk, legacyKey('alice'));
      await disk.write(legacyKey('alice'), 'temporarily unreadable');
      final bob = account('bob').scope;
      await disk.write(
        legacyKey('bob'),
        legacyCatalog(
          scope: bob,
          libraries: client.views,
          entries: [entry('one')],
          edits: CatalogEdits(
            details: {
              'book:one': const BookDetails(title: 'Native Bob', author: 'Bob'),
            },
          ),
        ),
      );
      // Exercise the real directory scan, including a real per-file I/O error.
      expect((await Process.run('chmod', ['000', failed.path])).exitCode, 0);
      try {
        await expectLater(
          store.migrateLegacy(),
          throwsA(isA<FileSystemException>()),
        );
        final text = await disk.read(choiceKey(bob));
        expect(text, isNotNull);
        expect(
          CatalogChoices.decode(bob, text!).edits.details['book:one']!.title,
          'Native Bob',
        );
      } finally {
        expect((await Process.run('chmod', ['600', failed.path])).exitCode, 0);
      }
      expect(await failed.readAsString(), 'temporarily unreadable');
      await store.migrateLegacy();
    },
  );

  for (final refresh in [false, true]) {
    test(
      'background legacy damage reaches the active notice ${refresh ? 'after an unchanged refresh' : 'without a server refresh'}',
      () async {
        final initial = controller();
        await initial.restore();
        await initial.refresh();
        await preferences.setString(
          legacyKey('alice'),
          '{damaged retained choices',
        );
        final counted = CountingFiles(DiskCatalogFiles(root));
        store = LocalCatalogStore(files: counted);
        final catalog = controller();
        await catalog.restore();
        expect(catalog.message, isNull);
        final library = catalog.libraryNotifier.value;
        await store.migrateLegacy();
        counted.writes.clear();
        counted.reads.clear();
        final requests = client.catalogReads;
        if (refresh) {
          await catalog.refresh();
        } else {
          await catalog.reconcileChoices();
          expect(client.catalogReads, requests);
          expect(counted.reads, [choiceKey(scope)]);
        }
        expect(catalog.message, contains('kept for recovery'));
        expect(catalog.libraryNotifier.value, same(library));
        expect(counted.writes.keys, isNot(contains(legacyKey('alice'))));
        final files = await root
            .list()
            .where((file) => file is File)
            .cast<File>()
            .toList();
        expect(
          await Future.wait(files.map((file) => file.readAsString())),
          contains('{damaged retained choices'),
        );
        catalog.checkInvariants();
      },
    );
  }

  test('native version one selected libraries migrate to no hidden libraries after reopen', () async {
    final legacy = jsonDecode(
      legacyCatalog(
        scope: scope,
        libraries: client.views,
        entries: [entry('one')],
        edits: CatalogEdits(
          details: {
            'book:one': const BookDetails(
              title: 'Version one choice',
              author: 'Me',
            ),
          },
        ),
      ),
    ) as Map<String, dynamic>;
    legacy['version'] = 1;
    legacy['selected'] = ['books'];
    legacy.remove('hidden');
    await disk.write(legacyKey('alice'), jsonEncode(legacy));
    await store.migrateLegacy();
    await committedFile(disk, legacyKey('alice')).delete();
    final reopened = controller(
      storage: LocalCatalogStore(files: DiskCatalogFiles(root)),
    );
    await reopened.restore();
    await reopened.refresh();
    expect(reopened.accountNotifier.value.hidden, isEmpty);
    expect(reopened.books.single.title, 'Version one choice');
    expect(reopened.message, isNull);
    reopened.checkInvariants();
  });
}

class CountingFiles implements CatalogFiles {
  @override
  Future<void> remove(String key) => disk.remove(key);
  CountingFiles(this.disk);
  final DiskCatalogFiles disk;
  final writes = <String, String>{};
  final reads = <String>[];
  String? pauseKey;
  bool failPreserve = false;
  bool failScan = false;
  String? failReadOnceKey;
  String? pauseReadKey;
  final releaseRead = Completer<void>();
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<CatalogDiscovery> catalogKeys(
    String? Function(String) identify,
  ) async {
    if (failScan) throw const FileSystemException('discovery failed');
    return disk.catalogKeys(identify);
  }

  @override
  Future<void> preserve(String key) async {
    if (failPreserve) throw const FileSystemException('retention failed');
    await disk.preserve(key);
  }

  @override
  Future<String?> read(String key) async {
    reads.add(key);
    if (key == pauseReadKey) await releaseRead.future;
    if (key == failReadOnceKey) {
      failReadOnceKey = null;
      throw const FileSystemException('temporarily unavailable');
    }
    return disk.read(key);
  }

  @override
  Future<void> write(String key, String text) async {
    if (key == pauseKey && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    writes[key] = text;
    await disk.write(key, text);
  }
}

class SignalledCredentials extends MemoryCredentials {
  String? watchUser;
  final saved = Completer<void>();
  @override
  Future<void> write(JellyfinSession? session) async {
    await super.write(session);
    if (watchUser != null &&
        session?.scope.userId == watchUser &&
        !saved.isCompleted) {
      saved.complete();
    }
  }
}

String choiceKey(AccountScope scope) =>
    'bookfin.catalog.choices.v1.${base64Url.encode(utf8.encode(scope.key))}';

class SignalledClient extends FixtureClient {
  SignalledClient(super.server);
  Completer<void>? requested;
  @override
  Future<CatalogPages> catalog(JellyfinSession session, Set<String> shown) {
    if (requested case final signal? when !signal.isCompleted) {
      signal.complete();
    }
    return super.catalog(session, shown);
  }
}
