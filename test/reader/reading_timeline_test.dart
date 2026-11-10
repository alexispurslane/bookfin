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

  group('a History choice outside the open edition', () {
    /// Saves [saved] as the place where this phone last read its edition.
    Future<void> lastRead(TextPosition saved) async {
      store.values[key]!['resumes'] = [encodeTextPosition(saved)];
      await reader.refreshPersonalRecords();
    }

    /// Lets the open book show the place that it opened at, as the pager
    /// reports the first page that it shows.
    void showOpened() =>
        reader.acceptAddress(reader.token, reader.initialAddress!);

    String quoteOf(TextPosition place) =>
        (jsonDecode(place.anchor) as Map)['quote'] as String;

    test('Go to on a reading move opens its edition there, records one '
        'history restore move from the edition\'s saved place, and offers '
        'Undo', () async {
      await lastRead(place('Where I stopped'));

      await reader.restoreHistory('second', previous: false);
      showOpened();

      expect(reader.edition?.id, edition.id);
      expect(reader.initialAddress?.quote, 'After second');
      final moved = reader.history.first;
      expect(moved.kind, HistoryAction.historyRestore);
      expect(quoteOf(moved.before), 'Where I stopped');
      expect(quoteOf(moved.after), 'After second');
      expect(
        reader.history.where((event) => event.kind != HistoryAction.search),
        [moved],
        reason: 'One entry starts the visit: the move.',
      );
      expect(reader.undoOffer?.action, same(moved));
    });

    test(
      'Undo after that open returns to the edition\'s saved place',
      () async {
        await lastRead(place('Where I stopped'));
        await reader.restoreHistory('second', previous: false);
        showOpened();
        final shown = <ReaderAddress>[];
        reader.attachDocument(reader.token, _Navigator(shown.add), const []);

        await reader.undoMove();

        expect(
          [for (final address in shown) address.quote],
          ['Where I stopped'],
        );
      },
    );

    test('Go to at the edition\'s saved place records no move and offers no '
        'Undo. The visit starts as Opened', () async {
      final stopped = place('After second');
      await lastRead(stopped);

      await reader.restoreHistory('second', previous: false);
      showOpened();

      final opened = reader.history.first;
      expect(opened.kind, HistoryAction.open);
      expect(quoteOf(opened.before), 'After second');
      expect(quoteOf(opened.after), 'After second');
      expect(reader.undoOffer, isNull);
    });

    test('an edition that this phone never read records only the start of '
        'the visit', () async {
      await reader.restoreHistory('second', previous: false);
      showOpened();

      expect(reader.history.first.kind, HistoryAction.open);
      expect(reader.undoOffer, isNull);
    });

    test('Go to on a bookmark opens its edition there, as a bookmark restore '
        'move from the edition\'s saved place', () async {
      store.values[key]!['resumes'] = [
        encodeTextPosition(place('Out at sea', inEdition: otherEdition)),
      ];
      await reader.refreshPersonalRecords();

      await reader.restoreBookmark('elsewhere');
      showOpened();

      expect(reader.edition?.id, otherEdition.id);
      final moved = reader.history.first;
      expect(moved.kind, HistoryAction.bookmarkRestore);
      expect(quoteOf(moved.before), 'Out at sea');
      expect(quoteOf(moved.after), 'A sea');
      expect(reader.undoOffer?.action, same(moved));
    });

    test('Go to from another open book ends that book\'s visit', () async {
      await reader.open(otherBook, otherEdition);
      reader.acceptVisible(
        reader.token,
        const ReadingLocation('epubcfi(/6/2!/4/2/1:0)', 'OPS/one.xhtml', 'Sea'),
      );

      await reader.restoreHistory('second', previous: false);
      showOpened();

      expect(reader.edition?.id, edition.id);
      final closed = reader.history.firstWhere(
        (event) => event.kind == HistoryAction.close,
      );
      expect(closed.after.editionId, otherEdition.id);
    });

    test(
      'a place in an edition that is not in the library opens nothing',
      () async {
        final gone = HistoryEvent(
          id: 'gone',
          at: DateTime.utc(2026, 11, 9, 20, 9),
          kind: HistoryAction.search,
          before: place('Gone before'),
          after: place(
            'Gone',
            inEdition: const Edition(
              id: 'gone',
              kind: EditionKind.text,
              label: 'EPUB',
              files: [source],
              memberIds: ['ebook'],
            ),
          ),
          bookTitle: 'Gone',
          editionLabel: 'EPUB',
        );
        store.values[key]!['history'] = [
          ...store.values[key]!['history'] as List,
          gone.toJson(),
        ];
        await reader.refreshPersonalRecords();

        await reader.restoreHistory('gone', previous: false);

        expect(reader.book, isNull);
      },
    );
  });

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
