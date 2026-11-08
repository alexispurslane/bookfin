import 'dart:async';
import 'dart:convert';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'publication_test.dart' show epub;

const source = SourceFile(
  itemId: 'ebook',
  displayName: 'Book.epub',
  mediaSourceId: 'original',
  revision: 'revision-one',
  durationMs: null,
  container: 'epub',
  sizeBytes: 100,
);
const edition = Edition(
  id: 'text-edition',
  kind: EditionKind.text,
  label: 'EPUB',
  files: [source],
  memberIds: ['ebook'],
);
const book = Book(
  id: 'work',
  title: 'River',
  author: 'Writer',
  editions: [edition],
);
const visible = VisibleLocation(
  'epubcfi(/6/2!/4/2/1:0)',
  'OPS/one.xhtml',
  'A river',
);

void main() {
  test('closing while records restore cancels the open without disabling later record saves', () async {
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub');
    final store = MemoryResume()..readGate = Completer<void>();
    final reader = ReaderSession(
      downloads: downloads,
      store: store,
      load: (_) async => Publication.admit(epub()),
    );
    final binding = reader.bind(account(), [book]);
    final opening = reader.open(book, edition);
    reader.closeView(reader.token);
    store.readGate!.complete();
    await Future.wait([binding, opening]);
    expect(reader.publication, isNull);
    await reader.open(book, edition);
    reader.acceptVisible(reader.token, visible);
    expect(reader.canBookmark, isTrue);
    await reader.addBookmark(title: 'After returning');
    await reader.flush();
    final restarted = ReaderSession(
      downloads: downloads,
      store: store,
      load: (_) async => Publication.admit(epub()),
    );
    await restarted.bind(account(), [book]);
    await restarted.open(book, edition);
    expect(restarted.bookmarks.single.title, 'After returning');
    reader.dispose();
    restarted.dispose();
    downloads.dispose();
  });

  test(
    'only the newest open can load after account records finish restoring',
    () async {
      final downloads = LocalFiles()
        ..files[source.key] = Uri.file('/verified.epub');
      final store = MemoryResume()..readGate = Completer<void>();
      var loads = 0;
      final reader = ReaderSession(
        downloads: downloads,
        store: store,
        load: (_) async {
          loads++;
          return Publication.admit(epub());
        },
      );
      final binding = reader.bind(account(), [book]);
      final first = reader.open(book, edition);
      final second = reader.open(book, edition);
      store.readGate!.complete();
      await Future.wait([binding, first, second]);
      expect(loads, 1);
      reader.dispose();
      downloads.dispose();
    },
  );

  test('visible reading positions and bookmarks reopen in the same account and edition', () async {
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub');
    final store = MemoryResume();
    final publication = Publication.admit(epub());
    ReaderSession create() => ReaderSession(
      downloads: downloads,
      store: store,
      load: (_) async => publication,
    );
    final reader = create();
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    reader.acceptVisible(reader.token, visible);
    await reader.addBookmark();
    await reader.flush();
    final restarted = create();
    await restarted.bind(account(), [book]);
    await restarted.open(book, edition);
    expect(restarted.initialLocation?.cfi, visible.cfi);
    expect(restarted.bookmarks.single.position.anchor, reader.position!.anchor);
    final anchor = jsonDecode(reader.position!.anchor) as Map;
    expect(anchor['processed'], publication.identity);
    expect(anchor['original'], publication.originalDigest);
    expect(reader.position!.revision, 'revision-one');
    await restarted.bind(account(user: 'bob'), [book]);
    await restarted.open(book, edition);
    expect(restarted.initialLocation, isNull);
    expect(restarted.bookmarks, isEmpty);
    reader.dispose();
    restarted.dispose();
    downloads.dispose();
  });

  test('an account change cancels a pending publication and ignores its old viewport', () async {
    final gate = Completer<Publication>();
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub');
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: (_) => gate.future,
    );
    await reader.bind(account(), [book]);
    final opening = reader.open(book, edition);
    await Future<void>.delayed(Duration.zero);
    final oldToken = reader.token;
    await reader.bind(account(user: 'bob'), [book]);
    gate.complete(Publication.admit(epub()));
    await opening;
    reader.acceptVisible(oldToken, visible);
    expect(reader.publication, isNull);
    expect(reader.position, isNull);
    reader.dispose();
    downloads.dispose();
  });

  test('changed processed content rejects an old locator without deleting its bookmark', () async {
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub');
    final store = MemoryResume();
    var publication = Publication.admit(epub());
    final reader = ReaderSession(
      downloads: downloads,
      store: store,
      load: (_) async => publication,
    );
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    reader.acceptVisible(reader.token, visible);
    await reader.addBookmark();
    await reader.flush();
    publication = Publication.admit(
      epub(chapter: '<html><head/><body>Different</body></html>'),
    );
    await reader.open(book, edition);
    expect(reader.initialLocation, isNull);
    expect(reader.message, contains('different'));
    expect(reader.bookmarks, hasLength(1));
    reader.dispose();
    downloads.dispose();
  });

  test('an open requested under an old account cannot start after its restore finishes', () async {
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub');
    final store = MemoryResume()..readGate = Completer<void>();
    final reader = ReaderSession(
      downloads: downloads,
      store: store,
      load: (_) async => Publication.admit(epub()),
    );
    final firstBinding = reader.bind(account(), [book]);
    final oldOpen = reader.open(book, edition);
    final newBinding = reader.bind(account(user: 'bob'), [book]);
    store.readGate!.complete();
    await Future.wait([firstBinding, oldOpen, newBinding]);
    expect(reader.publication, isNull);
    expect(reader.edition, isNull);
    reader.dispose();
    downloads.dispose();
  });

  test('late search results cannot replace a newer search or cross an account boundary', () async {
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub');
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: (_) async => Publication.admit(epub()),
    );
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    final navigator = DeferredSearch();
    reader.attach(reader.token, navigator, []);
    final first = reader.search('old');
    final second = reader.search('current');
    navigator.calls[1].complete(
      const SearchReport([], error: 'Current failure'),
    );
    await second;
    navigator.calls[0].complete(const SearchReport([], error: 'Stale failure'));
    await first;
    expect(reader.searchError, 'Current failure');
    final third = reader.search('cancelled');
    reader.cancelSearch();
    navigator.calls[2].complete(
      const SearchReport([], error: 'Cancelled failure'),
    );
    await third;
    expect(reader.searchError, isNull);
    expect(reader.searching, isFalse);
    final fourth = reader.search('old account');
    await reader.bind(account(user: 'bob'), [book]);
    navigator.calls[3].complete(
      const SearchReport([], error: 'Other account failure'),
    );
    await fourth;
    expect(reader.searchError, isNull);
    expect(reader.hits, isEmpty);
    reader.dispose();
    downloads.dispose();
  });

  test(
    'removing a source cancels its viewport and retains its account bookmarks',
    () async {
      final downloads = LocalFiles()
        ..files[source.key] = Uri.file('/verified.epub');
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: (_) async => Publication.admit(epub()),
      );
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      final old = reader.token;
      reader.acceptVisible(old, visible);
      await reader.addBookmark();
      await reader.bind(account(), []);
      reader.acceptVisible(old, visible);
      expect(reader.publication, isNull);
      expect(reader.position, isNull);
      expect(reader.loading, isFalse);
      expect(reader.message, isNotNull);
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      expect(reader.bookmarks, hasLength(1));
      reader.checkInvariants();
      reader.dispose();
      downloads.dispose();
    },
  );
}

class DeferredSearch implements NavigatorPort {
  final calls = <Completer<SearchReport>>[];
  @override
  Future<SearchReport> search(String query, int request) {
    final call = Completer<SearchReport>();
    calls.add(call);
    return call.future;
  }

  @override
  Future<void> cancelSearch(int request) async {}
  @override
  Future<void> configure({
    required double fontSize,
    required bool night,
  }) async {}
  @override
  Future<void> contents(String href) async {}
  @override
  Future<void> display(ReadingLocation location) async {}
  @override
  Future<void> move(bool forward) async {}
  @override
  Future<void> seek(int section, double progress) async {}

  /// The section, the progress and the width of each page preview, in
  /// order.
  final previews = <(int, double, double)>[];

  /// What each page preview returns, or null to keep it waiting.
  PagePicture? picture;
  @override
  Future<PagePicture> preview(int section, double progress, double width) {
    previews.add((section, progress, width));
    return picture == null
        ? Completer<PagePicture>().future
        : Future.value(picture);
  }
}
