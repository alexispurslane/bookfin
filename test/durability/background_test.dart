import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/main.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../appearance/preferences_test.dart' show MemoryAppearanceStore;
import '../foundation_test.dart' show disconnectedCatalog;
import '../playback/playback_test.dart'
    show LocalFiles, TestEngine, account, recording, title;
import '../reader/persistence_test.dart' show FailingRecords;
import '../reader/publication_test.dart' show epub;
import '../reader/session_test.dart' show book, edition, source, visible;
import '../real_time.dart';

// Each test names one moment when the app must save a place in a book, and
// shows that a process killed right after that moment keeps the place. A kill
// drops the preference plugin's memory, so the place must be on disk.

String get _account => account().scope.key;

/// Ends the process: only what the preference plugin wrote survives.
void _kill() => SharedPreferences.resetStatic();

/// A second chapter in the spine of the test publication.
const _secondChapter = VisibleLocation(
  'epubcfi(/6/4!/4/2/1:0)',
  'OPS/two.xhtml',
  'The sea',
);

Publication _twoChapters() => Publication.admit(
  epub(
    extra: {
      'OPS/book.opf': utf8.encode(
        '<package version="3.0"><metadata/><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/><item id="two" href="two.xhtml" media-type="application/xhtml+xml"/><item id="png" href="dot.png" media-type="image/png"/><item id="css" href="book.css" media-type="text/css"/><item id="svg" href="active.svg" media-type="image/svg+xml"/></manifest><spine><itemref idref="one"/><itemref idref="two"/></spine></package>',
      ),
      'OPS/two.xhtml': utf8.encode(
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Sea</title></head><body><p>The sea</p></body></html>',
      ),
    },
  ),
);

/// A second ebook, with its own edition and file.
const _otherSource = SourceFile(
  itemId: 'other-ebook',
  displayName: 'Other.epub',
  mediaSourceId: 'original',
  revision: 'revision-one',
  durationMs: null,
  container: 'epub',
  sizeBytes: 100,
);
const _otherEdition = Edition(
  id: 'other-text-edition',
  kind: EditionKind.text,
  label: 'EPUB',
  files: [_otherSource],
  memberIds: ['other-ebook'],
);
const _otherBook = Book(
  id: 'other-work',
  title: 'Sea',
  author: 'Writer',
  editions: [_otherEdition],
);

/// The saved reading places after a restart, as the edition id and the
/// chapter resource of each.
Future<Map<String, String>> _readingPlacesAfterKill() async {
  _kill();
  final saved = await LocalResumeStore().reading.read(_account);
  return {
    for (final place in (saved?['resumes'] as List? ?? []).cast<Map>())
      place['edition'] as String: jsonDecode(place['anchor'] as String)
          .toString(),
  };
}

/// Kills and restarts the app until what [read] gives back after the
/// restart satisfies [found], and returns that, or the last that it read
/// after 200 looks. A save that a lifecycle change starts hops to another
/// isolate, so it ends in real time, which [finish] gives it.
Future<T> _afterKill<T>(
  WidgetTester tester,
  Future<T> Function() read,
  bool Function(T value) found,
) => finish(tester, () async {
  late T value;
  for (var look = 0; look < 200; look++) {
    _kill();
    value = await read();
    if (found(value)) break;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return value;
}());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'a kill right after the app is hidden mid-playback keeps the last position',
    (tester) async {
      final downloads = LocalFiles();
      final engine = TestEngine();
      final playback = Playback(
        downloads: downloads,
        engine: engine,
        store: LocalResumeStore(),
      );
      await finish(tester, playback.bind(account(), [title]));
      await finish(tester, playback.open(title, recording));
      await finish(tester, playback.play());
      engine.emit(0, 31000, playing: true);
      engine.emit(0, 31400, playing: true);
      await tester.pump();
      await tester.pumpWidget(
        BookfinApp(
          appearance: AppearanceController(MemoryAppearanceStore()),
          catalog: disconnectedCatalog(),
          playback: playback,
        ),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      final saved = await _afterKill(
        tester,
        () => LocalResumeStore().read(_account),
        (saved) =>
            (saved?['resumes']?[recording.id] as List?)
                ?.single['milliseconds'] ==
            31400,
      );
      expect(
        (saved!['resumes'][recording.id] as List).single['milliseconds'],
        31400,
      );

      await tester.pumpWidget(const SizedBox());
      unawaited(playback.close());
      await tester.pump();
      downloads.dispose();
    },
  );

  testWidgets(
    'a quit from the desktop menu mid-playback saves the last position before the app exits',
    (tester) async {
      final downloads = LocalFiles();
      final engine = TestEngine();
      final playback = Playback(
        downloads: downloads,
        engine: engine,
        store: LocalResumeStore(),
      );
      await finish(tester, playback.bind(account(), [title]));
      await finish(tester, playback.open(title, recording));
      await finish(tester, playback.play());
      engine.emit(0, 31000, playing: true);
      engine.emit(0, 31400, playing: true);
      await tester.pump();
      await tester.pumpWidget(
        BookfinApp(
          appearance: AppearanceController(MemoryAppearanceStore()),
          catalog: disconnectedCatalog(),
          playback: playback,
        ),
      );

      final response = await finish(
        tester,
        tester.binding.handleRequestAppExit(),
      );
      _kill();
      final saved = await finish(tester, LocalResumeStore().read(_account));

      expect(response, AppExitResponse.exit);
      expect(
        (saved!['resumes'][recording.id] as List).single['milliseconds'],
        31400,
      );
      await tester.pumpWidget(const SizedBox());
      unawaited(playback.close());
      await tester.pump();
      downloads.dispose();
    },
  );

  group('the reader', () {
    late LocalFiles downloads;
    late FailingRecords storage;
    late ReaderSession reader;
    setUp(() async {
      downloads = LocalFiles()
        ..files[source.key] = Uri.file('/verified.epub')
        ..files[_otherSource.key] = Uri.file('/other.epub');
      storage = FailingRecords(LocalResumeStore().reading)..writable = true;
      final publication = _twoChapters();
      reader = ReaderSession(
        downloads: downloads,
        store: storage,
        load: (_) async => publication,
      );
      await reader.bind(account(), [book, _otherBook]);
      await reader.open(book, edition);
      reader.acceptVisible(reader.token, visible);
      await reader.flush();
    });
    tearDown(() {
      reader.dispose();
      downloads.dispose();
    });

    test(
      'keeps the new chapter when it is killed right after the chapter changes',
      () async {
        reader.acceptVisible(reader.token, _secondChapter);
        await reader.flush();

        expect(
          (await _readingPlacesAfterKill())[edition.id],
          contains('OPS/two.xhtml'),
        );
      },
    );

    test('keeps the place in the first book when it is killed after another book opens', () async {
      reader.acceptVisible(reader.token, _secondChapter);
      await reader.open(_otherBook, _otherEdition);
      reader.acceptVisible(reader.token, visible);
      await reader.flush();

      final places = await _readingPlacesAfterKill();
      expect(places[edition.id], contains('OPS/two.xhtml'));
      expect(places[_otherEdition.id], contains('OPS/one.xhtml'));
    });

    testWidgets(
      'keeps a place whose save failed when it is killed right after the app is hidden',
      (tester) async {
        storage.writable = false;
        await tester.runAsync(() async {
          reader.acceptVisible(reader.token, _secondChapter);
          await reader.flush();
        });
        storage.writable = true;
        await tester.pumpWidget(
          BookfinApp(
            appearance: AppearanceController(MemoryAppearanceStore()),
            catalog: disconnectedCatalog(),
            reader: reader,
          ),
        );

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        final places = await _afterKill(
          tester,
          _readingPlacesAfterKill,
          (places) => places[edition.id]?.contains('OPS/two.xhtml') ?? false,
        );
        expect(places[edition.id], contains('OPS/two.xhtml'));
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'keeps a place whose save failed when the app quits from the desktop menu',
      (tester) async {
        storage.writable = false;
        await tester.runAsync(() async {
          reader.acceptVisible(reader.token, _secondChapter);
          await reader.flush();
        });
        storage.writable = true;
        await tester.pumpWidget(
          BookfinApp(
            appearance: AppearanceController(MemoryAppearanceStore()),
            catalog: disconnectedCatalog(),
            reader: reader,
          ),
        );

        final response = await finish(
          tester,
          tester.binding.handleRequestAppExit(),
        );
        final places = await finish(tester, _readingPlacesAfterKill());

        expect(response, AppExitResponse.exit);
        expect(places[edition.id], contains('OPS/two.xhtml'));
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
