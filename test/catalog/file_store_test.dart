import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/store.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bookfin/catalog/catalog_files.dart';
import 'package:bookfin/catalog/catalog_files_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'controller_test.dart' show account, MemoryCredentials;
import 'model_test.dart' show entry;
import '../appearance/preferences_test.dart' show MemoryAppearanceStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SharedPreferencesAsync preferences;
  late LegacyPreferences legacy;
  late DiskCatalogFiles disk;
  final scope = account('alice').scope;
  final key = 'bookfin.catalog.v1.${base64Url.encode(utf8.encode(scope.key))}';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookfin-catalog-');
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = legacy = LegacyPreferences();
    disk = DiskCatalogFiles(Directory('${root.path}/bookfin-catalog'));
    preferences = SharedPreferencesAsync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('bookfin/media'), (
          call,
        ) async {
          expect(call.method, 'storage');
          return {'path': '${root.path}/bookfin-media'};
        });
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('bookfin/media'), null);
      SharedPreferencesAsyncPlatform.instance = previous;
      await root.delete(recursive: true);
    });
  });

  testWidgets(
    'the app starts retained-account migration after its first frame',
    (tester) async {
      await tester.runAsync(() async {
        FlutterSecureStorage.setMockInitialValues({});
        await preferences.setString(legacyKey('bob'), 'inactive');
        final appearance = AppearanceController(MemoryAppearanceStore());
        legacy.onKeys = () => expect(find.byType(MaterialApp), findsOneWidget);
        await tester.pumpWidget(BookfinApp(appearance: appearance));
        await tester.pump();
        expect(find.byType(MaterialApp), findsOneWidget);
        expect(legacy.keyRequests, 1);
        await legacy.removed.future;
        expect(
          await LocalCatalogStore().read(account('bob').scope),
          'inactive',
        );
        await tester.pumpWidget(const SizedBox());
        appearance.dispose();
      });
    },
  );

  testWidgets(
    'failed background migration reports an error and retains the catalog',
    (tester) async {
      await tester.runAsync(() async {
        FlutterSecureStorage.setMockInitialValues({});
        await preferences.setString(key, 'legacy');
        legacy.failRemoval = true;
        final reported = Completer<FlutterErrorDetails>();
        final previous = FlutterError.onError;
        FlutterError.onError = reported.complete;
        final appearance = AppearanceController(MemoryAppearanceStore());
        try {
          await tester.pumpWidget(BookfinApp(appearance: appearance));
          await tester.pump();
          final error = await reported.future;
          expect(error.library, 'catalog storage');
          expect(await preferences.getString(key), 'legacy');
          expect(await LocalCatalogStore().read(scope), 'legacy');
        } finally {
          FlutterError.onError = previous;
          await tester.pumpWidget(const SizedBox());
          appearance.dispose();
        }
      });
    },
  );

  test(
    'a migrated catalog restores corrections and hidden libraries offline',
    () async {
      final text = legacyCatalog(
        scope: scope,
        libraries: [
          const BookLibrary('books', 'Books'),
          const BookLibrary('hidden', 'Hidden'),
        ],
        hidden: {'hidden'},
        entries: [entry('one')],
        completedAt: DateTime.utc(2026, 11, 12),
        edits: CatalogEdits(
          details: {
            'book:one': const BookDetails(
              title: 'My corrected title',
              author: 'My author',
            ),
          },
        ),
      );
      await preferences.setString(key, text);
      await LocalCatalogStore().migrateLegacy();
      final reopened = await LocalCatalogStore().read(scope);
      expect(reopened, text);
      final decoded = CatalogCache.decode(scope, reopened!);
      expect((await LocalCatalogStore().readChoices(scope)).hidden, {'hidden'});
      expect(decoded.completedAt, DateTime.utc(2026, 11, 12));
      var networkRequests = 0;
      final catalog = CatalogController(
        credentials: MemoryCredentials()..value = account('alice'),
        store: LocalCatalogStore(),
        clientFactory: (_, _) {
          networkRequests++;
          throw StateError('No network during restore');
        },
      );
      addTearDown(catalog.dispose);
      await catalog.restore();
      expect(catalog.books.single.title, 'My corrected title');
      expect(catalog.books.single.author, 'My author');
      expect(networkRequests, 0);
    },
  );

  test(
    'the same user on another server has a different committed catalog',
    () async {
      final other = account('alice', server: 'https://other.example').scope;
      await LocalCatalogStore().write(scope, 'first server');
      await LocalCatalogStore().write(other, 'other server');
      expect(await LocalCatalogStore().read(scope), 'first server');
      expect(await LocalCatalogStore().read(other), 'other server');
    },
  );

  test(
    'ordinary catalog writes survive reopen without a preference catalog',
    () async {
      await LocalCatalogStore().write(scope, 'first catalog');
      expect(await LocalCatalogStore().read(scope), 'first catalog');
      expect(await preferences.getString(key), isNull);
      final files = await root
          .list(recursive: true)
          .where((file) => file is File)
          .toList();
      expect(files, hasLength(2));
      expect(await committedFile(disk, key).readAsString(), 'first catalog');
    },
  );
  test(
    'restore reads the legacy account without migrating inactive accounts',
    () async {
      await preferences.setString(key, 'current');
      final otherKey = legacyKey('bob');
      await preferences.setString(otherKey, 'inactive');
      legacy.reads.clear();
      expect(await LocalCatalogStore().read(scope), 'current');
      expect(legacy.reads, [key]);
      expect(legacy.keyRequests, 0);
      expect(await root.list().toList(), isEmpty);
    },
  );

  test(
    'migration commits current and inactive accounts before removing each key',
    () async {
      await preferences.setString(key, 'current é 📚');
      await preferences.setString(legacyKey('bob'), 'inactive');
      await preferences.setString('reading-speed', 'tiny');
      legacy.reads.clear();
      await LocalCatalogStore().migrateLegacy();
      expect(await preferences.getString(key), isNull);
      expect(await preferences.getString(legacyKey('bob')), isNull);
      expect(await preferences.getString('reading-speed'), 'tiny');
      expect(await LocalCatalogStore().read(scope), 'current é 📚');
      expect(await LocalCatalogStore().read(account('bob').scope), 'inactive');
      expect(legacy.allValueRequests, 0);
      expect(legacy.keyRequests, 1);
      expect(legacy.reads.where((key) => !key.startsWith('bookfin.catalog.')), [
        'reading-speed',
      ]);
    },
  );

  test('malformed legacy text survives migration exactly and still reports its decode error', () async {
    const malformed = '{"edits": [broken é 📚';
    await preferences.setString(key, malformed);
    await LocalCatalogStore().migrateLegacy();
    final reopened = await LocalCatalogStore().read(scope);
    expect(reopened, malformed);
    expect(await preferences.getString(key), isNull);
    expect(() => CatalogCache.decode(scope, reopened!), throwsFormatException);
  });

  test('a committed file wins when interrupted preference cleanup leaves both sources', () async {
    await preferences.setString(key, 'old legacy');
    legacy.failRemoval = true;
    await expectLater(
      LocalCatalogStore().migrateLegacy(),
      throwsA(isA<Exception>()),
    );
    expect(await disk.read(key), 'old legacy');
    expect(await preferences.getString(key), 'old legacy');
    await LocalCatalogStore().write(scope, 'new file');
    expect(await LocalCatalogStore().read(scope), 'new file');
    legacy.failRemoval = false;
    await LocalCatalogStore().migrateLegacy();
    expect(await preferences.getString(key), isNull);
    expect(await LocalCatalogStore().read(scope), 'new file');
  });

  test('an older migration finishes before a concurrent newer write', () async {
    await preferences.setString(key, 'old legacy');
    final controlled = ControlledFiles(disk)..pauseWrite = true;
    final store = LocalCatalogStore(files: controlled);
    final migration = store.migrateLegacy();
    await controlled.entered.future;
    final writing = store.write(scope, 'new file');
    final overlappingWrites = controlled.writes;
    controlled.release.complete();
    await Future.wait([migration, writing]);
    expect(overlappingWrites, 1);
    expect(await LocalCatalogStore().read(scope), 'new file');
    expect(await preferences.getString(key), isNull);
  });

  test(
    'migration cannot restore legacy text over an already requested write',
    () async {
      await preferences.setString(key, 'old legacy');
      final controlled = ControlledFiles(disk)..pauseWrite = true;
      final store = LocalCatalogStore(files: controlled);
      final writing = store.write(scope, 'new file');
      await controlled.entered.future;
      final migration = store.migrateLegacy();
      controlled.release.complete();
      await Future.wait([migration, writing]);
      expect(await LocalCatalogStore().read(scope), 'new file');
      expect(await preferences.getString(key), isNull);
    },
  );

  test(
    'a failed migration keeps the legacy copy and can retry on the same store',
    () async {
      await preferences.setString(key, 'only good copy');
      final controlled = ControlledFiles(disk)..failWrite = true;
      final store = LocalCatalogStore(files: controlled);
      await expectLater(
        store.migrateLegacy(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await LocalCatalogStore().read(scope), 'only good copy');
      expect(await preferences.getString(key), 'only good copy');
      controlled.failWrite = false;
      await store.migrateLegacy();
      expect(await preferences.getString(key), isNull);
      expect(await LocalCatalogStore().read(scope), 'only good copy');
    },
  );

  test(
    'an inactive account failure does not strand the other legacy accounts',
    () async {
      await preferences.setString(key, 'current');
      await preferences.setString(legacyKey('bob'), 'inactive');
      final controlled = ControlledFiles(disk)..failKey = key;
      await expectLater(
        LocalCatalogStore(files: controlled).migrateLegacy(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await preferences.getString(key), 'current');
      expect(await preferences.getString(legacyKey('bob')), isNull);
      expect(await LocalCatalogStore().read(account('bob').scope), 'inactive');
    },
  );

  test(
    'failure to create catalog storage preserves the legacy account',
    () async {
      await preferences.setString(key, 'legacy');
      final controlled = ControlledFiles(disk)..blockCreation = true;
      await expectLater(
        LocalCatalogStore(files: controlled).migrateLegacy(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await preferences.getString(key), 'legacy');
      await File(disk.root.path).delete();
      await LocalCatalogStore().migrateLegacy();
      expect(await LocalCatalogStore().read(scope), 'legacy');
      expect(await preferences.getString(key), isNull);
    },
  );

  test(
    'a failed replacement leaves the committed file readable after reopen',
    () async {
      final store = LocalCatalogStore();
      await store.write(scope, 'old');
      final file = committedFile(disk, key);
      await Directory('${file.path}.partial').create();
      await expectLater(
        store.write(scope, 'new'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await LocalCatalogStore().read(scope), 'old');
      await Directory('${file.path}.partial').delete();
      await store.write(scope, 'new');
      expect(await LocalCatalogStore().read(scope), 'new');
    },
  );

  test('rename failure keeps legacy bytes and retry commits them', () async {
    await preferences.setString(key, 'legacy');
    final controlled = ControlledFiles(disk)..blockRename = true;
    await expectLater(
      LocalCatalogStore(files: controlled).migrateLegacy(),
      throwsA(isA<FileSystemException>()),
    );
    expect(await preferences.getString(key), 'legacy');
    expect(
      await File('${committedFile(disk, key).path}.partial').readAsString(),
      'legacy',
    );
    await Directory(committedFile(disk, key).path).delete();
    await LocalCatalogStore().migrateLegacy();
    expect(await preferences.getString(key), isNull);
    expect(await LocalCatalogStore().read(scope), 'legacy');
  });

  test(
    'an interrupted replacement ignores partial bytes and retries safely',
    () async {
      await LocalCatalogStore().write(scope, 'old');
      await File('${committedFile(disk, key).path}.partial')
          .writeAsString('incompl');
      expect(await LocalCatalogStore().read(scope), 'old');
      await LocalCatalogStore().write(scope, 'complete');
      expect(await LocalCatalogStore().read(scope), 'complete');
    },
  );

  test(
    'an interrupted first migration ignores partial bytes and retains legacy',
    () async {
      await preferences.setString(key, 'legacy');
      await disk.root.create();
      await File('${committedFile(disk, key).path}.partial')
          .writeAsString('incompl');
      expect(await LocalCatalogStore().read(scope), 'legacy');
      await LocalCatalogStore().migrateLegacy();
      expect(await LocalCatalogStore().read(scope), 'legacy');
      expect(await preferences.getString(key), isNull);
    },
  );

  test(
    'unreadable committed bytes report failure and preserve both sources',
    () async {
      await LocalCatalogStore().write(scope, 'original');
      final file = committedFile(disk, key);
      await file.writeAsBytes([0xff, 0xfe]);
      await preferences.setString(key, 'older');
      await expectLater(LocalCatalogStore().read(scope), throwsFormatException);
      await expectLater(
        LocalCatalogStore().migrateLegacy(),
        throwsFormatException,
      );
      expect(await file.readAsBytes(), [0xff, 0xfe]);
      expect(await preferences.getString(key), 'older');
    },
  );

  test(
    'account files stay separate and their names contain no account paths',
    () async {
      await LocalCatalogStore().write(scope, 'alice');
      await LocalCatalogStore().write(account('bob/../../other').scope, 'bob');
      expect(await LocalCatalogStore().read(scope), 'alice');
      expect(
        await LocalCatalogStore().read(account('bob/../../other').scope),
        'bob',
      );
      expect(await LocalCatalogStore().read(account('carol').scope), isNull);
      final files = await disk.root.list().toList();
      expect(files, hasLength(4));
      for (final file in files) {
        expect(
          file.uri.pathSegments.last,
          matches(RegExp(r'^[a-f0-9]{64}\.catalog$')),
        );
      }
    },
  );

  test(
    'tiny preference writes do not read or modify the catalog file',
    () async {
      final text = 'book data 📚' * 300000;
      final controlled = ControlledFiles(disk);
      await LocalCatalogStore(files: controlled).write(scope, text);
      final file = committedFile(disk, key);
      final before = await file.stat();
      controlled.reads = 0;
      controlled.writes = 0;
      await preferences.setString('reading-speed', '1');
      await preferences.setString('reading-speed', '2');
      expect(controlled.reads, 0);
      expect(controlled.writes, 0);
      expect(legacy.catalogWrites, 0);
      expect(await preferences.getString(key), isNull);
      expect((await file.stat()).modified, before.modified);
      expect(await LocalCatalogStore().read(scope), text);
    },
  );
}

String legacyKey(String user) =>
    'bookfin.catalog.v1.${base64Url.encode(utf8.encode(account(user).scope.key))}';

File committedFile(DiskCatalogFiles disk, String key) =>
    File('${disk.root.path}/${sha256.convert(utf8.encode(key))}.catalog');

// Only the external preferences boundary is mocked. Catalog bytes are real files.
base class LegacyPreferences extends InMemorySharedPreferencesAsync {
  LegacyPreferences() : super.empty();
  bool failRemoval = false;
  final removed = Completer<void>();
  int keyRequests = 0;
  void Function()? onKeys;
  int allValueRequests = 0;
  int catalogWrites = 0;
  final reads = <String>[];

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) {
    reads.add(key);
    return super.getString(key, options);
  }

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) {
    if (key.startsWith('bookfin.catalog.v1.')) catalogWrites++;
    return super.setString(key, value, options);
  }

  @override
  Future<Set<String>> getKeys(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) {
    keyRequests++;
    onKeys?.call();
    return super.getKeys(parameters, options);
  }

  @override
  Future<Map<String, Object>> getPreferences(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) {
    allValueRequests++;
    return super.getPreferences(parameters, options);
  }

  @override
  Future<bool> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    if (failRemoval) throw Exception('preference removal failed');
    final result = await super.clear(parameters, options);
    if (!removed.isCompleted) removed.complete();
    return result;
  }
}

class ControlledFiles implements CatalogFiles {
  ControlledFiles(this.disk);
  final DiskCatalogFiles disk;
  bool failWrite = false;
  bool blockRename = false;
  bool blockCreation = false;
  bool pauseWrite = false;
  String? failKey;
  int reads = 0;
  int writes = 0;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<Set<String>> catalogKeys(String? Function(String) identify) =>
      disk.catalogKeys(identify);
  @override
  Future<void> preserve(String key) => disk.preserve(key);
  @override
  Future<String?> read(String key) {
    reads++;
    return disk.read(key);
  }

  @override
  Future<void> write(String key, String text) async {
    writes++;
    if (pauseWrite) {
      pauseWrite = false;
      entered.complete();
      await release.future;
    }
    if (failWrite || key == failKey) {
      // Model interruption after a partial write, before commit. The migration
      // must leave the sole legacy copy available to another store instance.
      await disk.root.create(recursive: true);
      await File('${committedFile(disk, key).path}.partial')
          .writeAsString('fragment');
      throw const FileSystemException('write interrupted');
    }
    if (blockCreation) {
      await File(disk.root.path).writeAsString('obstacle');
    }
    if (blockRename && key.startsWith('bookfin.catalog.v1.')) {
      await Directory(committedFile(disk, key).path).create(recursive: true);
    }
    await disk.write(key, text);
  }
}

// Hand-written version 2 fixture: production only writes server-only version 3.
String legacyCatalog({
  required AccountScope scope,
  List<BookLibrary> libraries = const [],
  Set<String> hidden = const {},
  List<CatalogEntry> entries = const [],
  CatalogEdits? edits,
  DateTime? completedAt,
}) => jsonEncode({
  'version': 2,
  'scope': scope.toJson(),
  'accessBlocked': false,
  'libraries': [for (final library in libraries) library.toJson()],
  'hidden': hidden.toList(),
  'entries': [for (final entry in entries) entry.toJson()],
  'edits': (edits ?? CatalogEdits()).toJson(),
  'completedAt': completedAt?.toIso8601String(),
});
