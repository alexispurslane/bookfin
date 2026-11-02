import 'dart:async';

import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/playback_test.dart' show account, LocalFiles;
import 'publication_test.dart' show epub;
import 'session_test.dart' show source, edition, book, visible;

class FailingRecords implements ResumeStore {
  FailingRecords(this.records);
  final ResumeStore records;
  bool writable = false;
  Completer<void>? gate;
  @override
  Future<Map<String, dynamic>?> read(String key) => records.read(key);
  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    await gate?.future;
    if (!writable) throw Exception('Storage is unavailable');
    await records.write(key, value);
  }
}

void main() {
  late LocalResumeStore records;
  late FailingRecords storage;
  late LocalFiles downloads;
  late ReaderSession reader;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    records = LocalResumeStore();
    storage = FailingRecords(records.reading);
    downloads = LocalFiles()..files[source.key] = Uri.file('/verified.epub');
    reader = ReaderSession(
      downloads: downloads,
      store: storage,
      load: (_) async => Publication.admit(epub()),
    );
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    reader.acceptVisible(reader.token, visible);
  });
  tearDown(() async {
    reader.dispose();
    await reader.flush();
    downloads.dispose();
  });

  test(
    'flush retries a failed bookmark before switching accounts and returning',
    () async {
      await reader.addBookmark(title: 'Kept after storage recovery');
      expect(reader.message, contains('not saved'));
      storage.writable = true;
      await reader.flush();
      await reader.bind(account(user: 'bob'), [book]);
      await reader.open(book, edition);
      expect(reader.bookmarks, isEmpty);
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      expect(reader.bookmarks, hasLength(1));
      expect(reader.bookmarks.single.title, 'Kept after storage recovery');
      final saved = await records.reading.read(account().scope.key);
      expect(
        (saved!['bookmarks'] as List).single['title'],
        'Kept after storage recovery',
      );
    },
  );

  test(
    'an old-account failure remains pending without warning the new account',
    () async {
      storage.gate = Completer<void>();
      final saving = reader.addBookmark(title: 'Alice only');
      final switching = reader.bind(account(user: 'bob'), [book]);
      storage.gate!.complete();
      await Future.wait([saving, switching]);
      await reader.open(book, edition);
      expect(reader.bookmarks, isEmpty);
      expect(reader.message, isNull);
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      expect(reader.bookmarks, hasLength(1));
      expect(reader.bookmarks.single.title, 'Alice only');
      expect(reader.message, contains('not saved'));
      storage.writable = true;
      await reader.flush();
      final saved = await records.reading.read(account().scope.key);
      expect(saved, isNotNull);
      expect(saved!['bookmarks'], hasLength(1));
      expect(
        await records.reading.read(account(user: 'bob').scope.key),
        isNull,
      );
    },
  );

  test('binding retries failed reading records and retains concurrent audio records', () async {
    await reader.addBookmark(title: 'Reading mark');
    storage.writable = true;
    await Future.wait([
      records.write(account().scope.key, {'version': 3, 'speed': 1.5}),
      reader.bind(account(user: 'bob'), [book]),
    ]);
    expect((await records.read(account().scope.key))!['speed'], 1.5);
    expect(
      (await records.reading.read(account().scope.key))!['bookmarks'],
      hasLength(1),
    );
  });

  test(
    'dispose retries pending snapshots without moving them to another account',
    () async {
      await reader.addBookmark(title: 'Closing mark');
      storage.writable = true;
      reader.dispose();
      await reader.flush();
      reader = ReaderSession(
        downloads: downloads,
        store: storage,
        load: (_) async => Publication.admit(epub()),
      );
      final saved = await records.reading.read(account().scope.key);
      expect(saved, isNotNull);
      expect((saved!['bookmarks'] as List).single['title'], 'Closing mark');
      expect(
        await records.reading.read(account(user: 'bob').scope.key),
        isNull,
      );
    },
  );

  test(
    'editing and deleting bookmarks survive failed writes and reopening',
    () async {
      storage.writable = true;
      await reader.addBookmark(title: 'Original', note: 'Old note');
      final bookmark = reader.bookmarks.single;
      storage.writable = false;
      await reader.editBookmark(
        bookmark.id,
        title: 'Revised',
        note: 'New note',
      );
      storage.writable = true;
      await reader.flush();
      await reader.bind(account(user: 'bob'), [book]);
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      final edited = reader.bookmarks.single;
      expect(edited.id, bookmark.id);
      expect(edited.position.anchor, bookmark.position.anchor);
      expect(edited.createdAt.isAtSameMomentAs(bookmark.createdAt), isTrue);
      expect(edited.title, 'Revised');
      expect(edited.note, 'New note');
      storage.writable = false;
      await reader.deleteBookmark(bookmark.id);
      storage.writable = true;
      await reader.flush();
      await reader.bind(account(user: 'bob'), [book]);
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      expect(reader.bookmarks, isEmpty);
    },
  );
}
