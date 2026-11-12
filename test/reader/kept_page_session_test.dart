// A reopen of an EPUB or MOBI book first shows the kept picture of the page
// that the book opens at, before the book loads, and the true page replaces
// it (boo-sy2d). The session reads the kept page when an open starts,
// keeps the shown page with each saved place, and drops the kept page once
// the true page shows.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/reader/book_map.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/reader/epub/kept_page.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/epub/viewport.dart';
import 'package:bookfin/reader/kept_pages.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles;
import 'epub/corpus/book.dart' show madeUpEpub, showcaseBooks;
import 'epub/helpers.dart' show loadReaderFont, prose, readerPage, section;
import 'epub/layout_run_test.dart' show runToEnd;
import 'session_native_test.dart'
    show SpyStore, bookOf, epubEdition, epubFile, snapshot, accountKey;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReaderFont);

  late Directory folder;
  late File download;
  late LocalFiles downloads;
  late SpyStore store;
  final sessions = <ReaderSession>[];
  final keptPages = KeptPages(engine: () async => 'engine-one');

  /// The loads that sessions started since the last [setUp].
  var loads = 0;
  final showcase = showcaseBooks()['showcase-frost']!;

  /// The downloaded book's file.
  late Uint8List bytes;

  setUp(() async {
    bytes = showcase;
    folder = await Directory.systemTemp.createTemp('bookfin-kept-session-');
    download = await File('${folder.path}/complete').writeAsBytes(bytes);
    downloads = LocalFiles()..files[epubFile.key] = download.uri;
    store = SpyStore();
  });
  tearDown(() async {
    for (final session in sessions) {
      session.dispose();
    }
    sessions.clear();
    downloads.dispose();
    await folder.delete(recursive: true);
  });

  /// A new session of the account, as after a restart, whose loads wait
  /// for [loading].
  ReaderSession sessionOf({Future<void>? loading}) {
    final reader = ReaderSession(
      downloads: downloads,
      store: store,
      load: (_) => throw UnimplementedError(),
      loadDocument: (file, source) async {
        loads++;
        await loading;
        return loadReadingDocument(file, source);
      },
      keptPages: keptPages,
    );
    sessions.add(reader);
    return reader;
  }

  Future<void> until(bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) throw StateError('timed out');
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  /// Presents [settings] to the session's pager, as the viewport does, and
  /// gives the page that it shows for them once its saves ended.
  Future<LaidPage> present(
    ReaderSession reader, [
    PageSettings settings = readerPage,
  ]) async {
    final pager = reader.pager!;
    final before = pager.shown.value?.page;
    pager.present(settings);
    await until(() {
      final page = pager.shown.value?.page;
      return page != null &&
          page.settings == settings &&
          !identical(page, before);
    });
    await reader.flush();
    return pager.shown.value!.page;
  }

  /// Waits until the open of [reader] that runs read the kept page: a load
  /// after the [before] loads started, which follows the start of the read.
  Future<void> read(ReaderSession reader, int before) =>
      until(() => loads > before && !reader.readingKeptPage);

  /// Opens the book in a new session, shows its first page and turns
  /// [turns] pages, and gives that session.
  Future<ReaderSession> readTo(int turns) async {
    final reader = sessionOf();
    await reader.bind(account(), [bookOf(epubEdition)]);
    await reader.open(bookOf(epubEdition), epubEdition);
    await present(reader);
    for (var turn = 0; turn < turns; turn++) {
      final before = reader.pager!.shown.value!.page;
      await reader.move(true);
      await until(() => !identical(reader.pager!.shown.value!.page, before));
      await reader.flush();
    }
    return reader;
  }

  VerifiedFile verified() =>
      VerifiedFile(download.uri, sha256.convert(bytes).toString());

  test('a reopen shows the kept page of its saved place before the book '
      'loads, and drops it once the true page shows', () async {
    final first = await readTo(2);
    final page = first.pager!.shown.value!.page;
    final loading = Completer<void>();

    final second = sessionOf(loading: loading.future);
    await second.bind(account(), [bookOf(epubEdition)]);
    unawaited(second.open(bookOf(epubEdition), epubEdition));
    await until(() => second.keptPage != null);

    expect(second.pager, isNull);
    expect(second.keptPage!.depicts(page), isTrue);

    loading.complete();
    await until(() => second.pager != null);
    final shown = await present(second);
    expect(second.keptPage, isNull);
    expect(shown.startPlace, page.startPlace);
  });

  test('the shown page is kept with each saved place', () async {
    final reader = await readTo(3);

    final kept = await keptPages.read(verified(), reader.position!);
    addTearDown(() => kept?.dispose());

    expect(kept, isNotNull);
    expect(kept!.depicts(reader.pager!.shown.value!.page), isTrue);
  });

  test('a book that styles its text with its own font keeps its shown page '
      'too', () async {
    bytes = madeUpEpub(
      [for (var index = 0; index < 3; index++) '<p>${prose(40)}</p>'],
      css:
          '@font-face{font-family:Outfit;src:url(fonts/outfit.woff)}'
          'p{font-family:Outfit,serif}',
      fonts: {
        'fonts/outfit.woff': File('test/reader/epub/fixtures/outfit-ascii.woff')
            .readAsBytesSync(),
      },
    );
    await download.writeAsBytes(bytes);
    final reader = await readTo(2);

    final kept = await keptPages.read(verified(), reader.position!);
    addTearDown(() => kept?.dispose());

    expect(kept, isNotNull);
    expect(kept!.depicts(reader.pager!.shown.value!.page), isTrue);
  });

  test('an open at a chosen place shows no kept page', () async {
    final first = await readTo(2);
    final chosen = first.history
        .firstWhere((event) => event.after.anchor != first.position!.anchor)
        .after;
    final loading = Completer<void>();
    addTearDown(() {
      if (!loading.isCompleted) loading.complete();
    });

    final second = sessionOf(loading: loading.future);
    await second.bind(account(), [bookOf(epubEdition)]);
    final started = loads;
    unawaited(second.open(bookOf(epubEdition), epubEdition, at: chosen));
    await read(second, started);

    expect(second.keptPage, isNull);
  });

  test('a saved place that changed since its page was kept, as when another '
      'device moved it, shows no kept page', () async {
    final first = await readTo(2);
    first.dispose();
    sessions.remove(first);
    store.values[accountKey] = snapshot(
      resumes: ['{"cfi":"epubcfi(/6/2!/4/2/1:0)","quote":""}'],
    );
    final loading = Completer<void>();
    addTearDown(() {
      if (!loading.isCompleted) loading.complete();
    });

    final second = sessionOf(loading: loading.future);
    await second.bind(account(), [bookOf(epubEdition)]);
    final started = loads;
    unawaited(second.open(bookOf(epubEdition), epubEdition));
    await read(second, started);

    expect(second.keptPage, isNull);
  });

  test('a page kept after a jump into the middle of a page and a new text '
      'size is the page that the reopen shows, or no page of that size is '
      'kept', () async {
    const larger = PageSettings(
      width: 412,
      height: 671,
      fontSize: 27,
      night: false,
    );
    final first = await readTo(1);
    // Once the main run of the section ended, the jump shows the true page
    // that holds its target, which starts before the target.
    await until(() => first.pager!.pageNumber.value?.count != null);
    final before = first.pager!.shown.value!.page;
    await first.goTo(
      BookTarget(fraction: .5, part: before.section, progress: .53),
    );
    await until(() => !identical(first.pager!.shown.value!.page, before));
    await first.flush();
    await present(first, larger);
    first.dispose();
    sessions.remove(first);
    final loading = Completer<void>();

    final second = sessionOf(loading: loading.future);
    await second.bind(account(), [bookOf(epubEdition)]);
    final started = loads;
    unawaited(second.open(bookOf(epubEdition), epubEdition));
    await read(second, started);
    // The viewport draws only a kept page of its own settings.
    final kept = switch (second.keptPage) {
      final kept? when kept.settings == larger => kept.encoded,
      _ => null,
    };
    loading.complete();
    await until(() => second.pager != null);
    final shown = await present(second, larger);

    if (kept != null) {
      expect(KeptPage.alike(kept, KeptPage.encode(shown)!), isTrue);
    }
  });

  test('a reopen that shows its kept page writes no new kept page', () async {
    final first = await readTo(2);
    first.dispose();
    sessions.remove(first);
    final file = File('${folder.path}/.bookfin-layout/last-page');
    final written = await file.lastModified();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final second = sessionOf();
    await second.bind(account(), [bookOf(epubEdition)]);
    await second.open(bookOf(epubEdition), epubEdition);
    await present(second);

    expect(await file.lastModified(), written);
  });

  testWidgets('the reader shows the paper while it reads the kept page, then '
      'the kept page, and shows that the book loads only when no page was '
      'kept', (tester) async {
    final pages = runToEnd(
      prepareSections([section(prose(10))], readerPage).single,
    );
    addTearDown(() {
      for (final page in pages) {
        page.dispose();
      }
    });
    for (final found in [true, false]) {
      final reads = Completer<KeptPage?>();
      final loading = Completer<Publication>();
      final reader = ReaderSession(
        downloads: LocalFiles()
          ..files[epubFile.key] = Uri.file('/verified.epub'),
        store: SpyStore()
          ..values[accountKey] = snapshot(
            resumes: ['{"cfi":"epubcfi(/6/2!/4/2/1:0)","quote":""}'],
          ),
        load: (_) => loading.future,
        keptPages: _GatedPages(reads.future),
      );
      await reader.bind(account(), [bookOf(epubEdition)]);
      unawaited(reader.open(bookOf(epubEdition), epubEdition));
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(EpubViewport), findsNothing);

      reads.complete(
        found ? KeptPage.decode(KeptPage.encode(pages.first)!) : null,
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byType(EpubViewport),
        found ? findsOneWidget : findsNothing,
        reason: 'found: $found',
      );
      expect(
        find.byType(CircularProgressIndicator),
        found ? findsNothing : findsOneWidget,
        reason: 'found: $found',
      );
      await tester.pumpWidget(const SizedBox());
      reader.dispose();
    }
  });
}

/// Kept pages whose read gives [read].
class _GatedPages extends KeptPages {
  _GatedPages(this._read) : super(engine: () async => 'engine-one');
  final Future<KeptPage?> _read;

  @override
  Future<KeptPage?> read(VerifiedFile original, TextPosition at) => _read;
}
