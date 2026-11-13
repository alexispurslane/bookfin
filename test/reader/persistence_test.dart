import 'dart:async';
import 'dart:convert';

import 'package:bookfin/catalog/model.dart' show Edition;
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/playback_test.dart' show account, LocalFiles;
import 'publication_test.dart' show epub;
import 'session_test.dart' show source, edition, book, visible;

/// A records store that fails each save until [writable]. [records] is the
/// listening store or the reading records of a [LocalResumeStore].
class FailingRecords extends ResumeStore
    implements ListeningStore, ReadingStore {
  FailingRecords(this.records);
  final ResumeStore records;
  bool writable = false;
  Completer<void>? gate;
  @override
  Future<Map<String, dynamic>?> read(String key) => records.read(key);
  @override
  void acceptSnapshot(String key, Map<String, dynamic>? value) =>
      records.acceptSnapshot(key, value);
  @override
  bool setAside(String key) => records.setAside(key);
  @override
  Future<ListeningResume?> listeningResume(
    String accountKey,
    Edition edition,
  ) async => switch (records) {
    final ListeningStore listening => listening.listeningResume(
      accountKey,
      edition,
    ),
    _ => null,
  };

  @override
  Future<PlaceOrigin> origin(String key, Edition edition) async =>
      switch (records) {
        final ReadingStore reading => reading.origin(key, edition),
        _ => (own: null, elsewhere: false, device: null),
      };
  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    await gate?.future;
    if (!writable) throw Exception('Storage is unavailable');
    await records.write(key, value);
  }

  @override
  Future<void> save(String key, ListeningChanges changes) async {
    await gate?.future;
    if (!writable) throw Exception('Storage is unavailable');
    await (records as ListeningStore).save(key, changes);
  }

  @override
  Future<void> saveReading(String key, ReadingChanges changes) async {
    await gate?.future;
    if (!writable) throw Exception('Storage is unavailable');
    await (records as ReadingStore).saveReading(key, changes);
  }
}

void main() {
  late LocalResumeStore records;
  late FailingRecords storage;
  late LocalFiles downloads;
  late ReaderSession reader;
  late Publication publication;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    records = LocalResumeStore();
    storage = FailingRecords(records.reading);
    downloads = LocalFiles()..files[source.key] = Uri.file('/verified.epub');
    publication = Publication.admit(epub());
    reader = ReaderSession(
      downloads: downloads,
      store: storage,
      load: (_) async => publication,
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

  /// The damaged values that the store kept aside, as a new process reads
  /// them.
  Future<List<String?>> keptAside() async {
    final preferences = await SharedPreferences.getInstance();
    return [
      for (final name in preferences.getKeys())
        if (name.startsWith('bookfin.damaged-records.v1.'))
          preferences.getString(name),
    ];
  }

  for (final raw in ['[]', '{"reading":[]}']) {
    test(
      'malformed outer storage is kept aside, named as damaged, and the account saves new places: $raw',
      () async {
        reader.dispose();
        await reader.flush();
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(
          'bookfin.playback.v1.${account().scope.key}',
          raw,
        );
        storage.writable = true;
        reader = ReaderSession(
          downloads: downloads,
          store: storage,
          load: (_) async => publication,
        );
        await reader.bind(account(), [book]);
        await reader.open(book, edition);
        reader.acceptVisible(reader.token, visible);
        expect(reader.message, contains('damaged'));
        await reader.addBookmark(title: 'After the damage');
        await reader.flush();

        expect(await keptAside(), [raw]);
        expect(
          (await LocalResumeStore().reading.read(
            account().scope.key,
          ))!['bookmarks'],
          hasLength(1),
        );
      },
    );
  }

  for (final damaged in <Map<String, dynamic>>[
    {'version': 1, 'resumes': 'not a list', 'bookmarks': []},
    {
      'version': 1,
      'resumes': [null],
      'bookmarks': [],
    },
    {
      'version': 1,
      'resumes': [],
      'bookmarks': [
        {'id': 'mark', 'position': null, 'createdAt': 7},
      ],
    },
  ]) {
    test(
      'damaged reading records are kept aside and the readable bookmark comes back: $damaged',
      () async {
        storage.writable = true;
        await reader.addBookmark(title: 'Readable');
        await reader.flush();
        final key = account().scope.key;
        final readable =
            ((await records.reading.read(key))!['bookmarks'] as List).single;
        reader.dispose();
        await reader.flush();
        final text = jsonEncode({
          'reading': {
            ...damaged,
            'bookmarks': [...damaged['bookmarks'] as List, readable],
          },
        });
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString('bookfin.playback.v1.$key', text);
        reader = ReaderSession(
          downloads: downloads,
          store: storage,
          load: (_) async => publication,
        );
        await reader.bind(account(), [book]);
        await reader.open(book, edition);
        reader.acceptVisible(reader.token, visible);

        expect(reader.message, contains('damaged'));
        expect(reader.bookmarks.map((mark) => mark.title), ['Readable']);
        expect(await keptAside(), [text]);
      },
    );
  }

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
        load: (_) async => publication,
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
    'editing a bookmark survives rejected storage and account reopen',
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
    },
  );

  test(
    'deleting a bookmark survives rejected storage and account reopen',
    () async {
      storage.writable = true;
      await reader.addBookmark(title: 'Remove this mark');
      final bookmark = reader.bookmarks.single;
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
