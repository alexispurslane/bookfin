import 'dart:convert';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/records.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'publication_test.dart' show epub;
import 'session_test.dart' show book, edition, source, visible;

// The reader session's part of the shared History timeline: the reading
// entries of a book, and the verbs that the timeline's controller calls.

const otherSource = SourceFile(
  itemId: 'other-ebook',
  displayName: 'Other.epub',
  mediaSourceId: 'original',
  revision: 'revision-one',
  durationMs: null,
  container: 'epub',
  sizeBytes: 100,
  chapters: [],
);
const otherEdition = Edition(
  id: 'other-text',
  kind: EditionKind.text,
  label: 'Other EPUB',
  files: [otherSource],
  memberIds: ['other-ebook'],
);
const otherBook = Book(
  id: 'other-work',
  title: 'Sea',
  author: 'Writer',
  editions: [otherEdition],
);

void main() {
  final publication = Publication.admit(epub());
  final key = account().scope.key;
  late LocalFiles downloads;
  late MemoryResume store;
  late ReaderSession reader;

  /// A place in [inEdition] whose quote is [quote].
  TextPosition place(String quote, {Edition inEdition = edition}) =>
      TextPosition(
        editionId: inEdition.id,
        sourceKey: inEdition.files.single.key,
        revision: inEdition.files.single.revision,
        anchor: jsonEncode(
          EpubDocument(publication).save(
            EpubAddress(
              ReadingLocation('epubcfi(/6/2!/4/2/1:0)', 'OPS/one.xhtml', quote),
            ),
          ),
        ),
      );

  HistoryEvent<TextPosition> move(
    String id,
    int minute, {
    Edition? inEdition,
  }) => HistoryEvent(
    id: id,
    at: DateTime.utc(2026, 11, 9, 20, minute),
    kind: HistoryAction.search,
    before: place('Before $id', inEdition: inEdition ?? edition),
    after: place('After $id', inEdition: inEdition ?? edition),
    bookTitle: 'Saved title',
    editionLabel: 'Saved label',
  );

  final marked = Bookmark(
    id: 'elsewhere',
    position: place('A sea', inEdition: otherEdition),
    createdAt: DateTime.utc(2026, 11, 9, 20, 5),
    bookTitle: otherBook.title,
    editionLabel: otherEdition.label,
  );

  setUp(() async {
    downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub')
      ..files[otherSource.key] = Uri.file('/other.epub');
    store = MemoryResume()
      ..values[key] = {
        'version': 1,
        'resumes': <dynamic>[],
        'bookmarks': [marked.toJson()],
        'history': [
          move('first', 1).toJson(),
          move('third', 3).toJson(),
          move('other', 4, inEdition: otherEdition).toJson(),
          move('second', 2).toJson(),
        ],
      };
    reader = ReaderSession(
      downloads: downloads,
      store: store,
      load: (_) async => publication,
    );
    await reader.bind(account(), [book, otherBook]);
  });
  tearDown(() async {
    reader.dispose();
    await reader.flush();
    downloads.dispose();
  });

  test('a book\'s reading timeline lists the moves and bookmarks of its '
      'editions only, newest first', () {
    expect(
      [for (final entry in reader.timeline(book)) entry.id],
      ['third', 'second', 'first'],
    );
    expect(
      [for (final entry in reader.timeline(otherBook)) entry.id],
      ['elsewhere', 'other'],
    );
    expect(reader.timeline(null), hasLength(5));
  });

  test('the reading timeline stays the same list until the records '
      'change', () async {
    final before = reader.timeline(book);
    expect(reader.timeline(book), same(before));

    await reader.deleteHistory('second');

    expect(
      [for (final entry in reader.timeline(book)) entry.id],
      ['third', 'first'],
    );
  });

  test('deleting a reading move removes it from the saved records and keeps '
      'the others', () async {
    await reader.deleteHistory('second');
    await reader.flush();

    expect([
      for (final value in store.values[key]!['history'] as List)
        (value as Map)['id'],
    ], unorderedEquals(['first', 'third', 'other']));
    expect(store.values[key]!['bookmarks'], hasLength(1));
  });

  test('a place opens the edition that holds it, at that place', () async {
    await reader.openAt(place('Right here'));

    expect(reader.edition?.id, edition.id);
    expect(reader.initialAddress?.quote, 'Right here');
  });

  test(
    'a place in an edition that is not in the library opens nothing',
    () async {
      await reader.openAt(
        place(
          'Gone',
          inEdition: const Edition(
            id: 'gone',
            kind: EditionKind.text,
            label: 'EPUB',
            files: [source],
            memberIds: ['ebook'],
          ),
        ),
      );

      expect(reader.book, isNull);
    },
  );

  test('a place that no longer fits its edition opens the saved place '
      'instead', () async {
    await reader.open(book, edition);
    reader.acceptVisible(reader.token, visible);
    await reader.flush();
    final changed = TextPosition(
      editionId: edition.id,
      sourceKey: source.key,
      revision: source.revision,
      anchor: '{"version":1}',
    );

    await reader.open(book, edition, at: changed);

    expect(reader.initialAddress?.quote, visible.quote);
  });

  test('renaming a bookmark of another book keeps that bookmark\'s own book '
      'names', () async {
    await reader.open(book, edition);

    await reader.editBookmark('elsewhere', title: 'The sea');
    await reader.flush();

    final saved = (store.values[key]!['bookmarks'] as List).single as Map;
    expect(saved['title'], 'The sea');
    expect(saved['bookTitle'], otherBook.title);
    expect(saved['editionLabel'], otherEdition.label);
  });

  test('Go back on a reading move shows where it began in the open '
      'edition', () async {
    final shown = <ReaderAddress>[];
    await reader.open(book, edition);
    reader.attachDocument(reader.token, _Navigator(shown.add), const []);

    await reader.restoreHistory('second');
    await reader.restoreHistory('second', previous: false);

    expect(
      [for (final address in shown) address.quote],
      ['Before second', 'After second'],
    );
  });
}

/// A navigator that reports each place that the session shows.
class _Navigator implements DocumentNavigator {
  _Navigator(this.onDisplay);
  final void Function(ReaderAddress address) onDisplay;
  @override
  Future<void> display(ReaderAddress address) async => onDisplay(address);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
