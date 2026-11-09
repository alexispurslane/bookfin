import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/playback_test.dart' show account, LocalFiles;
import 'publication_test.dart' show epub;
import 'session_test.dart' show source, edition, book, visible;

// A reading bookmark names its book and edition, as a listening bookmark
// does, so that a timeline of every book and a book that left the library
// can name it. Bookmarks from before this have no names and still show.

void main() {
  late LocalResumeStore records;
  late LocalFiles downloads;
  late ReaderSession reader;
  final key = account().scope.key;

  /// Opens the book in a new reader session over [records].
  Future<void> openReader() async {
    reader = ReaderSession(
      downloads: downloads,
      store: records.reading,
      load: (_) async => Publication.admit(epub()),
    );
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    reader.acceptVisible(reader.token, visible);
  }

  /// The saved reading bookmarks of the account, as JSON.
  Future<List<Map<String, dynamic>>> savedBookmarks() async =>
      ((await LocalResumeStore().reading.read(key))!['bookmarks'] as List)
          .cast<Map<String, dynamic>>();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    records = LocalResumeStore();
    downloads = LocalFiles()..files[source.key] = Uri.file('/verified.epub');
  });
  tearDown(() async {
    reader.dispose();
    await reader.flush();
    downloads.dispose();
  });

  /// Saves one reading bookmark in the format before book names.
  Future<void> saveUnnamedBookmark() => records.reading.write(key, {
    'version': 1,
    'resumes': <dynamic>[],
    'bookmarks': [
      {
        'id': 'old',
        'position': {
          'edition': edition.id,
          'source': source.key,
          'revision': source.revision,
          'anchor': '{"cfi":"/6/4","quote":"Miss Brooke"}',
        },
        'createdAt': '2026-11-07T12:00:00.000Z',
        'title': 'Before names',
        'note': null,
      },
    ],
  });

  test('a bookmark that the reader adds saves the book title and the edition label', () async {
    await openReader();

    await reader.addBookmark(title: 'Here');

    final saved = (await savedBookmarks()).single;
    expect(saved['bookTitle'], book.title);
    expect(saved['editionLabel'], edition.label);
  });

  test(
    'a bookmark saved without book names opens and shows as before',
    () async {
      await saveUnnamedBookmark();

      await openReader();

      expect(reader.message, isNull);
      expect(reader.bookmarks.single.title, 'Before names');
    },
  );

  test(
    'a bookmark saved without book names gets them when the reader renames it',
    () async {
      await saveUnnamedBookmark();
      await openReader();

      await reader.editBookmark('old', title: 'Renamed');

      final saved = (await savedBookmarks()).single;
      expect(saved['title'], 'Renamed');
      expect(saved['bookTitle'], book.title);
      expect(saved['editionLabel'], edition.label);
    },
  );
}
