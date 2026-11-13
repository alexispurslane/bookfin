import 'dart:convert';
import 'dart:io';

import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/reader/document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../reader/pdf_document_test.dart' show pdfSource;
import '../reader/pdf_session_test.dart' show book, edition;
import '../reader/pdf_viewport_test.dart' show DrawnPdf;
import 'playback_test.dart' show account, LocalFiles;
import 'settings_worker_test.dart' show Workers, choices, readingSettings;

const audioSettings = {'version': 3, 'speed': 1.25};
ListeningChanges position(int milliseconds, {double speed = 1.25}) =>
    ListeningChanges(
      {...audioSettings, 'speed': speed},
      resumes: {
        'edition': [
          {
            'source': 'source',
            'revision': 'revision',
            'milliseconds': milliseconds,
          },
        ],
      },
    );

// Triggers count real SQLite settings writes, including assignments of the
// same text. The legacy trigger lets the regression run against schema five.
Future<void> countSettingsWrites(Database sql) async {
  await sql.execute('CREATE TABLE settings_writes (domain TEXT)');
  await sql.execute('''CREATE TRIGGER count_legacy_settings
    AFTER UPDATE OF metadata ON record_accounts BEGIN
      INSERT INTO settings_writes VALUES ('legacy'); END''');
  final hasDomains = (await sql.rawQuery(
    "SELECT name FROM sqlite_master WHERE name = 'record_settings'",
  )).isNotEmpty;
  if (hasDomains) {
    for (final operation in ['INSERT', 'UPDATE', 'DELETE']) {
      final row = operation == 'DELETE' ? 'old' : 'new';
      await sql.execute('''CREATE TRIGGER count_settings_$operation
        AFTER $operation ON record_settings BEGIN
          INSERT INTO settings_writes VALUES ($row.domain); END''');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late RecordDatabase database;
  late Database sql;
  late String path;
  late LocalResumeStore store;
  late Workers workers;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('domain-settings-');
    addTearDown(() => directory.delete(recursive: true));
    path = '${directory.path}/records.sqlite';
    database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(() => database.close());
    sql = await databaseFactoryFfi.openDatabase(path);
    workers = Workers();
    store = LocalResumeStore(
      openDatabase: () async => database,
      hop: workers.call,
    );
    await store.reading.saveReading(
      'alice',
      ReadingChanges(readingSettings(choices('text'))),
    );
    await store.save('alice', position(1000));
    await countSettingsWrites(sql);
    workers.texts.clear();
  });

  Future<void> expectWrites(List<String> domains, {int encoded = 0}) async {
    final writes = (await sql.query('settings_writes'))
        .map((row) => row['domain'])
        .toList();
    // Counts are work, not latency measurements on an Android device.
    stdout.writeln(
      'settings SQLite writes: $writes; worker text encodes: ${workers.texts.length}',
    );
    expect(writes, domains);
    expect(workers.texts.length, encoded);
  }

  Future<ReaderSession> openReader({double fontSize = 20}) async {
    final downloads = LocalFiles()
      ..files[pdfSource.key] = Uri.file('/text.pdf');
    addTearDown(downloads.dispose);
    final key = account().scope.key;
    await store.reading.saveReading(
      key,
      ReadingChanges({
        ...readingSettings(choices('text')),
        'fontSize': fontSize,
      }),
    );
    final reader = ReaderSession(
      downloads: downloads,
      store: store.reading,
      load: (_) async => throw StateError('PDF does not use EPUB loader'),
      loadDocument: (_, _) async => DrawnPdf(),
    );
    addTearDown(reader.dispose);
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    return reader;
  }

  for (final changeSettings in [false, true]) {
    test(
      'reader record saves never copy or encode unchanged PDF choices (change first: $changeSettings)',
      () async {
        final reader = await openReader();
        if (changeSettings) {
          await reader.setTrimMargins(false);
          await reader.flush();
        }
        workers.settingsCopies = 0;
        workers.texts.clear();
        await sql.delete('settings_writes');
        reader.acceptAddress(reader.token, PdfAddress(2, 0, pageCount: 2));
        await reader.flush();
        await reader.addBookmark(title: 'River');
        await reader.flush();
        stdout.writeln(
          'reader settings worker copies: ${workers.settingsCopies}',
        );
        expect(workers.settingsCopies, 0);
        await expectWrites([]);
        expect(reader.bookmarks.single.title, 'River');
      },
    );
  }

  test('legacy text sizing migrates once without resending settings on later reading saves', () async {
    final reader = await openReader(fontSize: 23);
    workers.texts.clear();
    await sql.delete('settings_writes');
    reader.acceptAddress(reader.token, PdfAddress(2, 0, pageCount: 2));
    await reader.flush();
    await expectWrites(['reading'], encoded: 1);
    final saved = (await store.reading.read(account().scope.key))!;
    expect(saved['fontSize'], 23);
    expect(saved['sizesMainText'], isTrue);
    workers.settingsCopies = 0;
    workers.texts.clear();
    await sql.delete('settings_writes');
    await reader.addBookmark(title: 'After migration');
    await reader.flush();
    expect(workers.settingsCopies, 0);
    await expectWrites([]);
  });

  test('listening positions leave both settings domains untouched after PDF choices exist', () async {
    for (final milliseconds in [2000, 3000, 4000]) {
      await store.save('alice', position(milliseconds));
    }
    await expectWrites([]);
    await database.close();
    database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    final restarted = LocalResumeStore(openDatabase: () async => database);
    expect(
      (await restarted.reading.read('alice'))!['pdfBooks'],
      choices('text'),
    );
    expect(
      (await restarted.read(
        'alice',
      ))!['resumes']['edition'].single['milliseconds'],
      4000,
    );
    expect((await database.load('alice'))!['sync']['pending'], hasLength(4));
    await restarted.checkInvariants();
  });

  test('one batch acknowledgment writes no settings and retains the records on reopen', () async {
    await store.save('alice', position(2000));
    await sql.delete('settings_writes');
    workers.texts.clear();
    final before = (await database.load('alice'))!;
    await store.acknowledgeBatch(
      'alice',
      (before['sync']['pending'] as List).cast<String>(),
    );
    await expectWrites([]);
    await database.close();
    database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    final after = (await database.load('alice'))!;
    expect(after['sync']['pending'], isEmpty);
    expect(after['sync']['actions'], before['sync']['actions']);
    expect(after['snapshot'], before['snapshot']);
  });

  test(
    'only a changed domain is written and equal settings add no write',
    () async {
      await store.save('alice', position(2000, speed: 1.5));
      await expectWrites(['listening']);
      await sql.delete('settings_writes');
      await store.reading.saveReading(
        'alice',
        ReadingChanges(readingSettings(choices('pageWords'))),
      );
      await expectWrites(['reading'], encoded: 1);
      await sql.delete('settings_writes');
      workers.texts.clear();
      await store.reading.saveReading(
        'alice',
        ReadingChanges(readingSettings(choices('pageWords'))),
      );
      await expectWrites([]);
      expect((await store.read('alice'))!['speed'], 1.5);
      expect(
        (await store.reading.read('alice'))!['pdfBooks'],
        choices('pageWords'),
      );
    },
  );

  test('failed settings and position commit rolls back both and retry still saves settings', () async {
    final before = await database.load('alice');
    await sql.execute(
      "CREATE TRIGGER fail_records BEFORE INSERT ON record_coverage BEGIN SELECT RAISE(ABORT, 'disk full'); END",
    );
    await expectLater(
      store.save('alice', position(2000, speed: 1.75)),
      throwsA(isA<DatabaseException>()),
    );
    expect(await database.load('alice'), before);
    await expectWrites([]);
    await sql.execute('DROP TRIGGER fail_records');
    await store.save('alice', position(2000, speed: 1.75));
    await expectWrites(['listening']);
    final after = (await database.load('alice'))!;
    expect(after['snapshot']['speed'], 1.75);
    expect(after['sync']['pending'], hasLength(2));
    expect(
      jsonEncode(after['snapshot']['reading']),
      jsonEncode(before!['snapshot']['reading']),
    );
    await store.checkInvariants();
  });
  test('schema five settings migrate atomically and retry without changing journal state', () async {
    const originalBody = '  {"future": "unreadable wire original"}  ';
    await sql.insert('record_objects', {
      'account': 'alice',
      'identity': 'future-object',
      'sequence': 31,
      'body': originalBody,
      'unreadable': 1,
    });
    await sql.update(
      'record_accounts',
      {'cursor': 31},
      where: 'account = ?',
      whereArgs: ['alice'],
    );
    final original = (await database.load('alice'))!;
    final metadata = jsonEncode(original['snapshot']);
    await sql.update(
      'record_accounts',
      {'metadata': metadata},
      where: 'account = ?',
      whereArgs: ['alice'],
    );
    await sql.execute('DROP TABLE record_settings');
    await sql.execute('DROP TABLE set_aside_record_settings');
    await sql.execute('PRAGMA user_version = 5');
    await database.close();
    database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    sql = await databaseFactoryFfi.openDatabase(path);
    await sql.execute(
      "CREATE TRIGGER fail_settings BEFORE INSERT ON record_settings WHEN new.domain = 'reading' BEGIN SELECT RAISE(ABORT, 'full during migration'); END",
    );
    final restarted = LocalResumeStore(openDatabase: () async => database);
    await expectLater(
      restarted.read('alice'),
      throwsA(isA<DatabaseException>()),
    );
    expect((await sql.query('record_accounts')).single['metadata'], metadata);
    expect(await sql.query('record_settings'), isEmpty);
    await sql.execute('DROP TRIGGER fail_settings');
    expect(
      (await restarted.reading.read('alice'))!['pdfBooks'],
      choices('text'),
    );
    expect(await database.load('alice'), original);
    expect(
      (await database.retainedObjects('alice')).single['body'],
      originalBody,
    );
    expect(await restarted.discoveryCursor('alice'), 31);
    await restarted.checkInvariants();
    await sql.delete('settings_writes');
    await restarted.save('alice', position(2000));
    expect(await sql.query('settings_writes'), isEmpty);
    await restarted.checkInvariants();
  });

  test('preference migration keeps both domains account isolation and pending records', () async {
    final original =
        jsonDecode((await database.read('alice'))!) as Map<String, dynamic>;
    SharedPreferences.setMockInitialValues({
      'bookfin.playback.v1.bob': jsonEncode(original),
    });
    // This legacy snapshot has no sync installation bound to another account.
    original.remove('sync');
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'bookfin.playback.v1.bob',
      jsonEncode(original),
    );
    expect((await store.reading.read('bob'))!['pdfBooks'], choices('text'));
    await store.save('bob', position(9000, speed: 2));
    expect((await store.read('alice'))!['speed'], 1.25);
    expect((await store.read('bob'))!['speed'], 2);
    expect((await database.load('bob'))!['sync']['pending'], isNotEmpty);
    await database.close();
    database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    final restarted = LocalResumeStore(openDatabase: () async => database);
    expect((await restarted.reading.read('bob'))!['pdfBooks'], choices('text'));
    expect((await restarted.read('bob'))!['speed'], 2);
    await restarted.checkInvariants();
  });

  test(
    'failed reading settings and place commit remains retryable as one change',
    () async {
      final before = await database.load('alice');
      final changes = ReadingChanges(
        readingSettings(choices('pageWords')),
        resumes: [
          {
            'edition': 'text',
            'source': 'text-source',
            'revision': 'r1',
            'anchor': '{}',
          },
        ],
      );
      await sql.execute(
        "CREATE TRIGGER fail_reading BEFORE INSERT ON record_coverage BEGIN SELECT RAISE(ABORT, 'full during reading'); END",
      );
      await expectLater(
        store.reading.saveReading('alice', changes),
        throwsA(isA<DatabaseException>()),
      );
      expect(await database.load('alice'), before);
      expect(await sql.query('settings_writes'), isEmpty);
      await sql.execute('DROP TRIGGER fail_reading');
      workers.texts.clear();
      await store.reading.saveReading('alice', changes);
      await expectWrites(['reading'], encoded: 1);
      final saved = (await store.reading.read('alice'))!;
      expect(saved['pdfBooks'], choices('pageWords'));
      expect(saved['resumes'].single['edition'], 'text');
      await store.checkInvariants();
    },
  );

  test('unreadable domain settings retain exact originals and recover other domain and records', () async {
    const damaged = '{broken reading settings';
    await sql.update(
      'record_settings',
      {'payload': damaged},
      where: 'account = ? AND domain = ?',
      whereArgs: ['alice', 'reading'],
    );
    final restarted = LocalResumeStore(openDatabase: () async => database);
    final saved = (await restarted.read('alice'))!;
    expect(saved['speed'], 1.25);
    expect(saved['resumes']['edition'].single['milliseconds'], 1000);
    expect(restarted.setAside('alice'), isTrue);
    expect(
      (await sql.query(
        'set_aside_record_settings',
        where: 'domain = ?',
        whereArgs: ['reading'],
      )).single['payload'],
      damaged,
    );
    expect((await database.load('alice'))!['sync']['pending'], hasLength(1));
    await restarted.checkInvariants();
  });
}
