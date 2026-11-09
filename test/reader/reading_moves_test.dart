// The reader session records each jump through the book as a reading move,
// with the place where it began and the place where it ended, and offers
// Undo for it. A page turn, a jump to the page that already shows, and a
// change of the text size are not moves. These tests drive the session with
// the real pager, as the reader screen does (see session_native_test.dart).
import 'dart:async';
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/records.dart';
import 'package:bookfin/reader/book_map.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/prepare.dart' show PageSettings;
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'epub/helpers.dart' show loadReaderFont, readerPage;
import 'epub/page_source_test.dart' show paragraphs;
import 'pdf_document_test.dart' show pdfSource;
import 'session_native_test.dart'
    show accountKey, bookOf, epubEdition, epubFile, navBook;

/// A reading store that keeps each change set that the session hands it,
/// and refuses them while [failing].
class MoveStore extends MemoryResume {
  final saves = <ReadingChanges>[];
  bool failing = false;

  @override
  Future<void> saveReading(String accountKey, ReadingChanges changes) {
    if (failing) throw Exception('Storage is full');
    saves.add(changes);
    return super.saveReading(accountKey, changes);
  }

  /// The reading moves that the store holds, as JSON.
  List<Map<String, dynamic>> get moves => [
    for (final value in values[accountKey]?['history'] as List? ?? const [])
      value as Map<String, dynamic>,
  ];
}

/// A three-chapter book. Each chapter fills several pages. The first page
/// links to a word in the third chapter, which search also finds.
Publication threeChapters() => Publication.admit(
  navBook(
    [
      '<h1 id="alder">Alder</h1><p>See <a href="s2.xhtml#wombat">the '
          'wombat</a>.</p>${paragraphs(14, label: 'Alder')}',
      '<h1 id="birch">Birch</h1>${paragraphs(14, label: 'Birch')}',
      '<h1 id="cedar">Cedar</h1>${paragraphs(6, label: 'Cedar')}'
          '<p id="wombat">A wombat sleeps under the cedar.</p>'
          '${paragraphs(6, label: 'Cedar end')}',
    ],
    [
      ('Alder', 'text/s0.xhtml#alder'),
      ('Birch', 'text/s1.xhtml#birch'),
      ('Cedar', 'text/s2.xhtml#cedar'),
    ],
  ),
);

/// The JSON of [place], so that two places compare by value.
Map<String, dynamic> json(TextPosition place) => encodeTextPosition(place);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReaderFont);

  late LocalFiles downloads;
  late MoveStore store;
  final sessions = <ReaderSession>[];
  final publication = threeChapters();

  setUp(() {
    downloads = LocalFiles()..files[epubFile.key] = Uri.file('/verified.epub');
    store = MoveStore();
  });
  tearDown(() {
    for (final session in sessions) {
      session.dispose();
    }
    sessions.clear();
    downloads.dispose();
  });

  /// The first page that [pager] shows that passes [test].
  Future<ShownPage> shownWhere(
    EpubPager pager,
    bool Function(ShownPage shown) test,
  ) {
    final now = pager.shown.value;
    if (now != null && test(now)) return Future.value(now);
    final found = Completer<ShownPage>();
    void listener() {
      final shown = pager.shown.value;
      if (shown != null && test(shown) && !found.isCompleted) {
        found.complete(shown);
      }
    }

    pager.shown.addListener(listener);
    return found.future
        .timeout(const Duration(seconds: 30))
        .whenComplete(() => pager.shown.removeListener(listener));
  }

  /// Presents [settings] to the session's pager, as the viewport does, and
  /// waits for the page that it shows for them.
  Future<void> present(
    ReaderSession reader, [
    PageSettings settings = readerPage,
  ]) async {
    final pager = reader.pager!;
    final before = pager.shown.value?.page;
    pager.present(settings);
    await shownWhere(
      pager,
      (shown) =>
          shown.page.settings == settings && !identical(shown.page, before),
    );
    await reader.flush();
    reader.checkInvariants();
  }

  /// The book map of the open book, once the session measured it.
  Future<BookMap> mapped(ReaderSession reader) {
    if (reader.bookMap case final map?) return Future.value(map);
    final done = Completer<BookMap>();
    void listener() {
      if (reader.bookMap case final map? when !done.isCompleted) {
        done.complete(map);
      }
    }

    reader.bookMapChanges.addListener(listener);
    return done.future
        .timeout(const Duration(seconds: 30))
        .whenComplete(() => reader.bookMapChanges.removeListener(listener));
  }

  /// A new session of the account, bound to [book].
  Future<ReaderSession> sessionOf(Book book) async {
    final reader = ReaderSession(
      downloads: downloads,
      store: store,
      load: (_) async => publication,
    );
    sessions.add(reader);
    await reader.bind(account(), [book]);
    return reader;
  }

  /// Opens the three-chapter book at its start, shows its first page, and
  /// waits for its map.
  Future<ReaderSession> openBook() async {
    final book = bookOf(epubEdition);
    final reader = await sessionOf(book);
    await reader.open(book, epubEdition);
    await present(reader);
    await mapped(reader);
    return reader;
  }

  /// Runs [step] on [reader], then saves and checks the session.
  Future<void> after(ReaderSession reader, Future<void> Function() step) async {
    await step();
    await reader.flush();
    reader.checkInvariants();
  }

  /// The section of the page that the session's pager shows.
  int shownSection(ReaderSession reader) =>
      reader.pager!.shown.value!.page.section;

  test('a drag of the scrub bar to another chapter records one seek from '
      'the old page to the new page', () async {
    final reader = await openBook();
    final map = reader.bookMap!;
    final start = reader.position!;

    await after(
      reader,
      () => reader.goTo(map.targetAt(map.chapters.last.start + .01)),
    );

    expect(shownSection(reader), 2);
    final move = reader.history.single;
    expect(move.kind, HistoryAction.seek);
    expect(json(move.before), json(start));
    expect(json(move.after), json(reader.position!));
    expect(move.bookTitle, 'River');
    expect(move.editionLabel, 'EPUB');
  });

  test('a move saves with its new place in one change set', () async {
    final reader = await openBook();
    store.saves.clear();

    await after(reader, () => reader.goToContents('text/s2.xhtml#cedar'));

    final move = reader.history.single;
    final changes = store.saves.single;
    expect(changes.history.keys, [move.id]);
    expect(changes.history[move.id], move.toJson());
    expect(changes.resumes, [json(reader.position!)]);
  });

  group('each jump records one move of its kind', () {
    final jumps =
        <(String, HistoryAction, Future<void> Function(ReaderSession))>[
          (
            'a contents entry',
            HistoryAction.chapter,
            (reader) => reader.goToContents('text/s2.xhtml#cedar'),
          ),
          (
            'a chapter arrow',
            HistoryAction.chapter,
            (reader) => reader.moveChapter(true),
          ),
          (
            'a link or Go to note',
            HistoryAction.link,
            (reader) => reader.followLink('text/s2.xhtml#wombat'),
          ),
          (
            'a search result',
            HistoryAction.search,
            (reader) async {
              await reader.search('wombat sleeps');
              await reader.openHit(reader.hits.single);
            },
          ),
        ];
    for (final (cause, kind, jump) in jumps) {
      test(cause, () async {
        final reader = await openBook();
        final start = reader.position!;

        await after(reader, () => jump(reader));

        expect(shownSection(reader), greaterThan(0));
        final move = reader.history.single;
        expect(move.kind, kind);
        expect(json(move.before), json(start));
        expect(json(move.after), json(reader.position!));
      });
    }

    test('a bookmark', () async {
      final reader = await openBook();
      await after(reader, () => reader.goToContents('text/s2.xhtml#cedar'));
      await reader.addBookmark(title: 'Cedar');
      final cedar = reader.position!;
      await after(reader, () => reader.goToContents('text/s0.xhtml#alder'));
      final start = reader.position!;

      await after(
        reader,
        () => reader.restoreBookmark(reader.bookmarks.single.id),
      );

      expect(reader.history, hasLength(3));
      final move = reader.history.first;
      expect(move.kind, HistoryAction.bookmarkRestore);
      expect(json(move.before), json(start));
      expect(json(move.after), json(cedar));
    });
  });

  test('a page turn records no move', () async {
    final reader = await openBook();

    await after(reader, () => reader.move(true));
    await after(reader, () => reader.move(true));
    await after(reader, () => reader.move(false));

    expect(reader.history, isEmpty);
    expect(store.moves, isEmpty);
  });

  test('a jump to the page that already shows records no move', () async {
    final reader = await openBook();
    final start = reader.position!;

    await after(reader, () => reader.goToContents('text/s0.xhtml#alder'));
    await after(reader, () => reader.goTo(reader.bookMap!.targetAt(0)));

    expect(json(reader.position!), json(start));
    expect(reader.history, isEmpty);
    expect(reader.undoOffer, isNull);
  });

  test('a jump that fails records no move and keeps the saved place', () async {
    final reader = await openBook();
    final start = reader.position!;
    store.saves.clear();

    await after(reader, () => reader.followLink('text/missing.xhtml'));

    expect(reader.message, contains('Your saved place was kept'));
    expect(json(reader.position!), json(start));
    expect(reader.history, isEmpty);
    expect(store.saves.expand((changes) => changes.history.keys), isEmpty);

    await after(reader, () => reader.move(true));
    expect(
      reader.history,
      isEmpty,
      reason: 'The next page turn does not end the failed jump.',
    );
  });

  group('Undo', () {
    test('a recorded move becomes the Undo offer, saved once the store '
        'holds it', () async {
      final reader = await openBook();
      var changes = 0;
      reader.undoChanges.addListener(() => changes++);

      await after(reader, () => reader.goToContents('text/s2.xhtml#cedar'));

      expect(reader.undoOffer?.action, same(reader.history.single));
      expect(reader.undoOffer?.saved, isTrue);
      expect(changes, greaterThan(0));
    });

    test('Undo returns to the place where the last move began and records '
        'an undo move, which ends the offer', () async {
      final reader = await openBook();
      final start = reader.position!;
      await after(reader, () => reader.goToContents('text/s2.xhtml#cedar'));
      final cedar = reader.position!;

      await after(reader, reader.undoMove);

      expect(shownSection(reader), 0);
      expect(json(reader.position!), json(start));
      final undo = reader.history.first;
      expect(undo.kind, HistoryAction.undo);
      expect(json(undo.before), json(cedar));
      expect(json(undo.after), json(start));
      expect(reader.undoOffer, isNull);
    });

    test(
      'a page turn keeps the offer, and the next move replaces it',
      () async {
        final reader = await openBook();
        await after(reader, () => reader.goToContents('text/s1.xhtml#birch'));
        final first = reader.history.single;

        await after(reader, () => reader.move(true));
        expect(reader.undoOffer?.action, same(first));

        await after(reader, () => reader.goToContents('text/s2.xhtml#cedar'));
        expect(reader.undoOffer?.action, same(reader.history.first));
        expect(reader.history.first, isNot(same(first)));
      },
    );

    test('Dismiss ends the offer and keeps the move', () async {
      final reader = await openBook();
      await after(reader, () => reader.goToContents('text/s2.xhtml#cedar'));

      reader.dismissUndo();

      expect(reader.undoOffer, isNull);
      expect(reader.history, hasLength(1));
    });

    test('the open of another book ends the offer', () async {
      final reader = await openBook();
      await after(reader, () => reader.goToContents('text/s2.xhtml#cedar'));

      await reader.open(reader.book!, epubEdition);

      expect(reader.undoOffer, isNull);
      expect(reader.history, hasLength(1));
    });

    test(
      'a change of the text size records no move, and the offer stays',
      () async {
        final reader = await openBook();
        await after(reader, () => reader.goToContents('text/s2.xhtml#cedar'));
        final move = reader.history.single;

        await reader.setFontSize(26);
        await present(
          reader,
          const PageSettings(
            width: 412,
            height: 671,
            fontSize: 26,
            night: false,
          ),
        );

        expect(reader.history.single, same(move));
        expect(reader.undoOffer?.action, same(move));
      },
    );
  });

  test('Go back on a move returns to its before, and Go to returns to its '
      'after, each with a history restore move', () async {
    final reader = await openBook();
    final start = reader.position!;
    await after(reader, () => reader.goToContents('text/s2.xhtml#cedar'));
    final move = reader.history.single;

    await after(reader, () => reader.restoreHistory(move.id));
    expect(json(reader.position!), json(start));
    expect(reader.history.first.kind, HistoryAction.historyRestore);

    await after(reader, () => reader.restoreHistory(move.id, previous: false));
    expect(json(reader.position!), json(move.after));
    expect(reader.history.first.kind, HistoryAction.historyRestore);
    expect(reader.history, hasLength(3));
    expect(reader.undoOffer?.action, same(reader.history.first));
  });

  test('Go to on a move into another ebook edition of the book opens that '
      'edition there', () async {
    final otherFile = SourceFile(
      itemId: 'other',
      displayName: 'Other.epub',
      mediaSourceId: 'original',
      revision: 'revision-one',
      durationMs: null,
      container: 'epub',
      sizeBytes: 100,
    );
    final other = Edition(
      id: 'other-edition',
      kind: EditionKind.text,
      label: 'Other EPUB',
      files: [otherFile],
      memberIds: const ['other'],
    );
    downloads.files[otherFile.key] = Uri.file('/other.epub');
    final book = Book(
      id: 'work',
      title: 'River',
      author: 'Writer',
      editions: [epubEdition, other],
    );
    final reader = await sessionOf(book);
    await reader.open(book, epubEdition);
    await present(reader);
    await after(reader, () => reader.goToContents('text/s2.xhtml#cedar'));
    final move = reader.history.single;
    // The two editions hold the same text, so a place keeps its anchor.
    final there = TextPosition(
      editionId: other.id,
      sourceKey: otherFile.key,
      revision: otherFile.revision,
      anchor: move.after.anchor,
    );
    final crossing = HistoryEvent(
      id: 'crossing',
      at: DateTime.utc(2026, 11, 9),
      kind: HistoryAction.seek,
      before: move.before,
      after: there,
      bookTitle: 'River',
      editionLabel: 'Other EPUB',
    );
    store.values[accountKey]!['history'] = [...store.moves, crossing.toJson()];
    await reader.refreshPersonalRecords();
    final cedar = reader.position!;

    await reader.restoreHistory('crossing', previous: false);
    await present(reader);
    await reader.flush();

    expect(reader.edition?.id, other.id);
    expect(shownSection(reader), 2);
    final restore = reader.history.first;
    expect(restore.kind, HistoryAction.historyRestore);
    expect(json(restore.before), json(cedar));
    expect(json(restore.after), json(there));
    expect(restore.editionLabel, 'Other EPUB');
    expect(reader.undoOffer?.action, same(restore));
    reader.checkInvariants();
  });

  test('the open of another book drops a jump that did not end, and a jump '
      'that waited for it', () async {
    final reader = await openBook();
    final hanging = _HangingNavigator();
    reader.attachDocument(reader.token, hanging, reader.contents);
    unawaited(reader.goToContents('text/s2.xhtml#cedar'));
    unawaited(reader.goToContents('text/s1.xhtml#birch'));
    await pumpEventQueue();

    await reader.open(reader.book!, epubEdition);
    await present(reader);
    await reader.flush();

    expect(shownSection(reader), 0, reason: 'The waiting jump did not run.');
    expect(reader.history, isEmpty);
    reader.checkInvariants();

    await after(reader, () => reader.goToContents('text/s2.xhtml#cedar'));
    expect(
      reader.history.single.kind,
      HistoryAction.chapter,
      reason: 'The new book does not wait for the old jump.',
    );
  });

  group('the bookmark here', () {
    test('names the bookmark on the shown page, and none after a page turn '
        'away from it', () async {
      final reader = await openBook();
      await after(reader, () => reader.move(true));
      expect(reader.bookmarkHere, isNull);

      await reader.addBookmark(title: 'Here');
      final mark = reader.bookmarks.single;
      expect(reader.bookmarkHere?.id, mark.id);

      await after(reader, () => reader.move(true));
      expect(reader.bookmarkHere, isNull);
      await after(reader, () => reader.move(false));
      expect(reader.bookmarkHere?.id, mark.id);
    });
  });

  test('a failed save keeps the move pending, the reader says that records '
      'are not saved, and the next save writes the move once', () async {
    final reader = await openBook();
    store.failing = true;

    await after(reader, () => reader.goToContents('text/s2.xhtml#cedar'));

    final move = reader.history.single;
    expect(reader.saveFailed, isTrue);
    expect(reader.message, contains('not saved'));
    expect(reader.undoOffer?.action, same(move));
    expect(reader.undoOffer?.saved, isFalse);
    expect(store.moves, isEmpty);

    store.failing = false;
    await reader.flush();

    expect(reader.saveFailed, isFalse);
    expect(reader.undoOffer?.saved, isTrue);
    expect(store.moves, [move.toJson()]);
    expect(
      json(decodeTextPosition(store.values[accountKey]!['resumes'].last)),
      json(move.after),
    );
    reader.checkInvariants();
  });

  group('in a PDF', () {
    Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
    const pdf = Edition(
      id: 'pdf-edition',
      kind: EditionKind.text,
      label: 'PDF',
      files: [pdfSource],
      memberIds: ['pdf'],
    );
    const book = Book(
      id: 'pdf-work',
      title: 'PDF book',
      author: 'Writer',
      editions: [pdf],
    );

    Future<ReaderSession> openPdf() async {
      downloads.files[pdfSource.key] = File(
        'tool/research/readers/fixtures/simple.pdf',
      ).absolute.uri;
      final reader = ReaderSession(
        downloads: downloads,
        store: store,
        load: loadPublication,
        loadDocument: loadReadingDocument,
      );
      sessions.add(reader);
      await reader.bind(account(), [book]);
      await reader.open(book, pdf);
      final navigator = _PageNavigator(reader);
      reader.attachDocument(reader.token, navigator, [
        const ContentsEntry('Source page 1', 'page:1'),
        const ContentsEntry('Source page 2', 'page:2'),
      ]);
      navigator.show(1);
      await mapped(reader);
      return reader;
    }

    test('the arrows turn a page and record no move', () async {
      final reader = await openPdf();
      expect(reader.hasChapters, isFalse);

      await after(reader, () => reader.moveChapter(true));

      expect((reader.visibleAddress! as PdfAddress).sourcePage, 2);
      expect(reader.history, isEmpty);
    });

    test('a contents entry records a move between source pages', () async {
      final reader = await openPdf();

      await after(reader, () => reader.goToContents('page:2'));

      final move = reader.history.single;
      expect(move.kind, HistoryAction.chapter);
      expect(move.before.sourcePage, 1);
      expect(move.after.sourcePage, 2);
    });
  });
}

/// A navigator whose jumps never end.
class _HangingNavigator implements DocumentNavigator {
  @override
  Future<void> contents(String href) => Completer<void>().future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for the PDF viewport: it shows a source page of a two-page PDF
/// and reports it at once.
class _PageNavigator implements DocumentNavigator {
  _PageNavigator(this.reader);
  final ReaderSession reader;
  int page = 1;

  void show(int next) {
    page = next;
    reader.acceptAddress(reader.token, PdfAddress(next, 0, pageCount: 2));
  }

  @override
  Future<void> move(bool forward) async {
    final next = page + (forward ? 1 : -1);
    if (next >= 1 && next <= 2) show(next);
  }

  @override
  Future<void> display(ReaderAddress address) async =>
      show((address as PdfAddress).sourcePage);
  @override
  Future<void> contents(String href) async =>
      show(int.parse(href.substring('page:'.length)));
  @override
  Future<void> seek(int part, double progress) async => show(part + 1);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
