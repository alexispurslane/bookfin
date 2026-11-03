import 'dart:io';
import 'dart:convert';

import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Android record storage migrates legacy records and retains uploads outside preferences', () async {
    final directory = await Directory.systemTemp.createTemp(
      'bookfin-record-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/records.sqlite';
    final database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    final snapshot = {
      'version': 3,
      'bookmarks': [
        {
          'id': 'one',
          'title': 'Kept',
          'position': {
            'edition': 'edition',
            'source': 'source',
            'revision': 'revision',
            'milliseconds': 900,
          },
          'createdAt': '2026-11-02T12:00:00.000Z',
          'bookTitle': 'Saved book',
          'editionLabel': 'Recording',
        },
      ],
      'history': [],
      'resumes': <String, dynamic>{},
    };
    SharedPreferences.setMockInitialValues({
      'bookfin.playback.v1.alice': jsonEncode(snapshot),
    });
    final store = LocalResumeStore(openDatabase: () async => database);
    expect((await store.read('alice'))!['bookmarks'], hasLength(1));
    await store.write('alice', snapshot);
    await database.close();
    SharedPreferences.setMockInitialValues({});
    final reopened = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(reopened.close);
    final restarted = LocalResumeStore(openDatabase: () async => reopened);
    expect((await restarted.read('alice'))!['bookmarks'], hasLength(1));
    final saved = jsonDecode((await reopened.read('alice'))!) as Map;
    expect(saved['sync']['pending'], hasLength(1));
    expect(await restarted.read('bob'), isNull);
    await reopened.checkInvariants();
  });
  test(
    'a completed personal-record write survives closing and reopening SQLite',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bookfin-record-database-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/records.sqlite';
      final first = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      await first.write('alice', '{"bookmark":"kept","pending":["one"]}');
      await first.close();
      final restarted = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(restarted.close);
      expect(
        await restarted.read('alice'),
        '{"bookmark":"kept","pending":["one"]}',
      );
      expect(await restarted.read('bob'), isNull);
      await restarted.checkInvariants();
    },
  );
}
