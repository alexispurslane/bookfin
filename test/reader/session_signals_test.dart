import 'package:bookfin/reader/session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'publication_test.dart' show epub;
import 'session_test.dart' show DeferredSearch, book, edition, source, visible;

void main() {
  late LocalFiles downloads;
  late FailingWrites store;
  late ReaderSession reader;
  late DeferredSearch navigator;
  late Signals signals;

  Future<void> openBook() async {
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    navigator = DeferredSearch();
    reader.attach(reader.token, navigator, []);
    await reader.flush();
  }

  setUp(() {
    downloads = LocalFiles()..files[source.key] = Uri.file('/verified.epub');
    store = FailingWrites();
    reader = ReaderSession(
      downloads: downloads,
      store: store,
      load: (_) async => Publication.admit(epub()),
    );
    signals = Signals(reader);
  });

  tearDown(() {
    reader.dispose();
    downloads.dispose();
  });

  test(
    'a page turn notifies the place once and no other reader signal',
    () async {
      await openBook();
      signals.reset();
      reader.acceptVisible(reader.token, visible);
      await reader.flush();
      expect(signals.counts, {...Signals.none, 'place': 1, 'session': 1});
    },
  );

  test(
    'a completed write that keeps the save status notifies nothing',
    () async {
      await openBook();
      reader.acceptVisible(reader.token, visible);
      signals.reset();
      await reader.flush();
      await reader.bind(account(), [book]);
      expect(signals.counts, Signals.none);
    },
  );

  test(
    'a failed write reports the save status, and a successful retry clears it',
    () async {
      await openBook();
      store.fail = true;
      signals.reset();
      reader.acceptVisible(reader.token, visible);
      await reader.flush();
      expect(reader.saveFailed, isTrue);
      expect(reader.message, contains('not saved'));
      expect(signals.counts, {
        ...Signals.none,
        'place': 1,
        'saveStatus': 1,
        'session': 2,
      });
      store.fail = false;
      signals.reset();
      await reader.flush();
      expect(reader.saveFailed, isFalse);
      expect(signals.counts, {...Signals.none, 'saveStatus': 1, 'session': 1});
    },
  );

  test(
    'adding, editing and deleting a bookmark each notify the bookmarks',
    () async {
      await openBook();
      reader.acceptVisible(reader.token, visible);
      await reader.flush();
      signals.reset();
      await reader.addBookmark(title: 'Ford');
      expect(signals.counts, {...Signals.none, 'bookmarks': 1, 'session': 1});
      signals.reset();
      await reader.editBookmark(reader.bookmarks.single.id, title: 'Bridge');
      expect(signals.counts, {...Signals.none, 'bookmarks': 1, 'session': 1});
      signals.reset();
      await reader.deleteBookmark(reader.bookmarks.single.id);
      expect(signals.counts, {...Signals.none, 'bookmarks': 1, 'session': 1});
      expect(reader.bookmarks, isEmpty);
    },
  );

  test('a font size change notifies the font size only', () async {
    await openBook();
    signals.reset();
    await reader.setFontSize(28);
    expect(reader.fontSize, 28);
    expect(signals.counts, {...Signals.none, 'fontSize': 1, 'session': 1});
  });

  test(
    'a search notifies search when it starts and when its hits arrive',
    () async {
      await openBook();
      signals.reset();
      final searching = reader.search('river');
      expect(reader.searching, isTrue);
      expect(signals.counts, {...Signals.none, 'search': 1, 'session': 1});
      navigator.calls.single.complete(const SearchReport([]));
      await searching;
      expect(reader.searching, isFalse);
      expect(signals.counts, {...Signals.none, 'search': 2, 'session': 2});
    },
  );

  test(
    'opening an edition notifies the document and its bookmarks, not the place',
    () async {
      await reader.bind(account(), [book]);
      signals.reset();
      await reader.open(book, edition);
      expect(reader.loading, isFalse);
      expect(signals.counts['document'], greaterThan(0));
      expect(signals.counts['bookmarks'], 1);
      expect(signals.counts['place'], 0);
      expect(signals.counts['search'], 0);
      expect(signals.counts['fontSize'], 0);
      expect(signals.counts['saveStatus'], 0);
    },
  );

  test('a page turn that notifies only the place still saves the position for the next session', () async {
    await openBook();
    reader.acceptVisible(reader.token, visible);
    await reader.flush();
    final restarted = ReaderSession(
      downloads: downloads,
      store: store,
      load: (_) async => Publication.admit(epub()),
    );
    await restarted.bind(account(), [book]);
    await restarted.open(book, edition);
    expect(restarted.initialLocation?.cfi, visible.cfi);
    restarted.dispose();
  });
}

/// Counts the notifications of each reader signal and of the whole session.
class Signals {
  Signals(ReaderSession reader) {
    final sources = <String, Listenable>{
      'place': reader.placeChanges,
      'document': reader.documentChanges,
      'bookmarks': reader.bookmarkChanges,
      'search': reader.searchChanges,
      'fontSize': reader.fontSizeChanges,
      'saveStatus': reader.saveStatusChanges,
      'session': reader,
    };
    for (final MapEntry(:key, :value) in sources.entries) {
      value.addListener(() => counts[key] = counts[key]! + 1);
    }
  }

  static const none = {
    'place': 0,
    'document': 0,
    'bookmarks': 0,
    'search': 0,
    'fontSize': 0,
    'saveStatus': 0,
    'session': 0,
  };
  final counts = Map.of(none);
  void reset() => counts.addAll(none);
}

class FailingWrites extends MemoryResume {
  bool fail = false;
  @override
  Future<void> write(String accountKey, Map<String, dynamic> value) async {
    if (fail) throw Exception('Storage is full.');
    await super.write(accountKey, value);
  }
}
