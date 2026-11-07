import 'dart:convert';
import 'dart:io';

import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../playback/playback_test.dart' show account, LocalFiles;
import 'publication_test.dart' show epub;
import 'session_test.dart' show book, edition, source, visible;

/// A reading store that keeps one account in memory and records each
/// whole snapshot written and each change set saved.
class RecordingReading extends ResumeStore implements ReadingStore {
  RecordingReading(this.value);
  Map<String, dynamic>? value;
  final written = <Map<String, dynamic>>[];
  final saved = <ReadingChanges>[];
  bool failing = false;

  @override
  Future<Map<String, dynamic>?> read(String accountKey) async => value;

  @override
  Future<void> write(String accountKey, Map<String, dynamic> snapshot) async {
    if (failing) throw Exception('Storage is unavailable');
    written.add(snapshot);
    value = snapshot;
  }

  @override
  Future<void> saveReading(String accountKey, ReadingChanges changes) async {
    if (failing) throw Exception('Storage is unavailable');
    saved.add(changes);
  }
}

Map<String, dynamic> place(String edition, String anchor) => {
  'edition': edition,
  'source': 'source-of-$edition',
  'revision': 'r1',
  'anchor': anchor,
};

/// A saved reading account with three places in other books and two
/// bookmarks.
Map<String, dynamic> library() => {
  'version': 1,
  'fontSize': 20,
  'resumes': [
    for (final name in ['one', 'two', 'three']) place(name, '{}'),
  ],
  'bookmarks': [
    for (final id in ['first', 'second'])
      {
        'id': id,
        'position': place('one', '{}'),
        'createdAt': '2026-01-01T00:00:00.000Z',
        'title': id,
        'note': null,
      },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ReaderSession, RecordingReading)> openReader() async {
    final store = RecordingReading(library());
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub');
    final reader = ReaderSession(
      downloads: downloads,
      store: store,
      load: (_) async => Publication.admit(epub()),
    );
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    return (reader, store);
  }

  test('a page turn saves a change set with only the new place', () async {
    final (reader, store) = await openReader();

    reader.acceptVisible(reader.token, visible);
    await reader.flush();

    expect(store.written, isEmpty);
    final changes = store.saved.single;
    expect(changes.resumes.single['edition'], edition.id);
    expect(changes.bookmarks, isEmpty);
    expect(changes.settings['fontSize'], 20);
  });

  test('adding a bookmark saves only that bookmark', () async {
    final (reader, store) = await openReader();
    reader.acceptVisible(reader.token, visible);
    await reader.flush();
    store.saved.clear();

    await reader.addBookmark(title: 'Here');
    await reader.flush();

    expect(store.written, isEmpty);
    final changes = store.saved.single;
    expect(changes.resumes, isEmpty);
    expect(changes.bookmarks.values.single!['title'], 'Here');
  });

  test('deleting a bookmark saves only its deletion', () async {
    final (reader, store) = await openReader();

    await reader.deleteBookmark('second');
    await reader.flush();

    expect(store.written, isEmpty);
    expect(store.saved.single.bookmarks, {'second': null});
    expect(store.saved.single.resumes, isEmpty);
  });

  test(
    'changes that wait for storage merge, so a retry saves each place once',
    () async {
      final (reader, store) = await openReader();
      store.failing = true;
      reader.acceptVisible(reader.token, visible);
      await reader.addBookmark(title: 'Kept');
      reader.acceptVisible(reader.token, visible);
      await reader.flush();
      expect(reader.saveFailed, isTrue);

      store.failing = false;
      await reader.flush();

      expect(store.written, isEmpty);
      final retry = store.saved.single;
      expect(retry.resumes, hasLength(1));
      expect(retry.bookmarks.values.single!['title'], 'Kept');
      expect(reader.saveFailed, isFalse);
    },
  );

  group('the local reading store', () {
    late RecordDatabase database;
    setUp(() async {
      sqfliteFfiInit();
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp('bookfin-read-');
      addTearDown(() => directory.delete(recursive: true));
      database = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/records.sqlite',
      );
      addTearDown(database.close);
    });

    test(
      'saves a change set and keeps every record that it does not name',
      () async {
        final store = LocalResumeStore(openDatabase: () async => database);
        await store.reading.write('alice', library());
        final before =
            (await database.load('alice'))!['sync']['actions'] as List;

        await store.reading.saveReading(
          'alice',
          ReadingChanges(
            {'version': 1, 'fontSize': 24},
            resumes: [place('two', '{"page":9}')],
            bookmarks: {'first': null},
          ),
        );

        final saved = (await store.reading.read('alice'))!;
        expect(saved['fontSize'], 24);
        expect(saved['resumes'], [
          place('one', '{}'),
          place('two', '{"page":9}'),
          place('three', '{}'),
        ]);
        expect(saved['bookmarks'].single['id'], 'second');
        final after =
            (await database.load('alice'))!['sync']['actions'] as List;
        expect(after, hasLength(before.length + 2));
        expect(jsonEncode(after.last['value']), isNot(contains('three')));
        await store.checkInvariants();
      },
    );
  });
}
