// A failed read of an account's reading records must not cost the places
// that the user reads afterwards (boo-y2sj, engine rule 3). The session
// keeps those changes, reads the records again, and saves the changes when
// the records open. It never saves before the read: a save carries the
// whole settings, so a save from unread records would replace the saved
// text size with the default.
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/playback_test.dart' show account, LocalFiles;
import 'publication_test.dart' show epub;
import 'session_test.dart' show source, edition, book, visible;

/// Reading records whose read fails until [readable].
class UnreadableRecords extends ReadingStore {
  UnreadableRecords(this.records);
  final ReadingRecords records;
  bool readable = false;
  @override
  Future<Map<String, dynamic>?> read(String key) async {
    if (!readable) throw Exception('Storage is unavailable');
    return records.read(key);
  }

  @override
  Future<void> saveReading(String key, ReadingChanges changes) =>
      records.saveReading(key, changes);
  @override
  void acceptSnapshot(String key, Map<String, dynamic>? value) =>
      records.acceptSnapshot(key, value);
}

void main() {
  late LocalFiles downloads;
  late Publication publication;
  late UnreadableRecords storage;
  late ReaderSession reader;
  final key = account().scope.key;

  /// The reading records as a new process reads them.
  Future<Map<String, dynamic>?> saved() => LocalResumeStore().reading.read(key);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    downloads = LocalFiles()..files[source.key] = Uri.file('/verified.epub');
    publication = Publication.admit(epub());
    // An earlier run saved a text size of 22.
    final earlier = ReaderSession(
      downloads: downloads,
      store: LocalResumeStore().reading,
      load: (_) async => publication,
    );
    await earlier.bind(account(), [book]);
    await earlier.setFontSize(22);
    earlier.dispose();
    await earlier.flush();
    expect((await saved())!['fontSize'], 22);

    storage = UnreadableRecords(LocalResumeStore().reading);
    reader = ReaderSession(
      downloads: downloads,
      store: storage,
      load: (_) async => publication,
    );
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
  });
  tearDown(() async {
    reader.dispose();
    await reader.flush();
    downloads.dispose();
  });

  test('a place read while the records could not be opened is saved when '
      'they open', () async {
    expect(reader.message, contains('could not be opened'));
    reader.acceptVisible(reader.token, visible);

    storage.readable = true;
    await reader.flush();

    expect(
      ((await saved())!['resumes'] as List).map((place) => place['anchor']),
      [contains(visible.cfi)],
    );
  });

  test('the next place after a failed read opens the records again without '
      'a flush', () async {
    storage.readable = true;
    reader.acceptVisible(reader.token, visible);
    await pumpEventQueue();

    expect((await saved())!['resumes'], hasLength(1));
  });

  test('the saved text size survives places read while the records could '
      'not be opened', () async {
    reader.acceptVisible(reader.token, visible);
    storage.readable = true;
    await reader.flush();

    expect((await saved())!['fontSize'], 22);
    expect(reader.fontSize, 22);
  });

  test('no place is saved while the records stay unread', () async {
    reader.acceptVisible(reader.token, visible);
    await reader.flush();

    expect((await saved())!['resumes'], isEmpty);
    expect((await saved())!['fontSize'], 22);
  });

  test('the notice about unread records ends when the records open',
      () async {
    reader.acceptVisible(reader.token, visible);
    storage.readable = true;
    await reader.flush();

    expect(reader.message, isNull);
    expect(reader.canBookmark, isTrue);
  });
}
