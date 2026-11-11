// In the reader's History, a tile of a listening place names where Go to
// lands in the open ebook (docs/plans/cross-edition-places.md, "What the
// person sees"). The reader names a place by the open book's map, which it
// measures once the book shows. Until then, the tile names the landing by
// its share of the book and its chapter, from the text outline, and then
// by its page.
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/crossings/crossings.dart';
import 'package:bookfin/crossings/scope.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/timeline.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/scope.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/reader/text_outline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../crossings/crossings_test.dart' show MemoryOutlines;
import '../downloads/verified_reads.dart';
import '../playback/mapped_moves_test.dart' show MediumSpy;
import '../playback/playback_test.dart'
    show account, LocalFiles, MemoryResume, TestEngine;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_screen_test.dart' show settleNative;

/// The two source pages of simple.pdf.
const pages = Edition(
  id: 'pages',
  kind: EditionKind.text,
  label: 'PDF',
  files: [pdfSource],
  memberIds: ['pdf'],
);

/// A recording of [pages] with a chapter mark for each of its chapters, a
/// minute each.
const narration = Edition(
  id: 'narration',
  kind: EditionKind.audio,
  label: 'Narrator',
  files: [
    SourceFile(
      itemId: 'audio',
      displayName: 'River',
      mediaSourceId: 'm',
      revision: 'a1',
      durationMs: 120000,
      container: 'mp3',
      sizeBytes: 1,
      chapters: [AudioChapter('One', 0), AudioChapter('Two', 60000)],
    ),
  ],
  memberIds: ['audio:m'],
);

const both = Book(
  id: 'river',
  title: 'River',
  author: 'Writer',
  editions: [pages, narration],
);

/// The outline of [pages]: chapter One on the first page and chapter Two on
/// the second, 1000 visible characters each.
final outline = TextOutline(
  parts: const [
    (path: 'page:1', characters: 1000),
    (path: 'page:2', characters: 1000),
  ],
  entries: const [
    (title: 'One', depth: 0, start: 0),
    (title: 'Two', depth: 0, start: 1000),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  final simple = File('tool/research/readers/fixtures/simple.pdf').absolute;

  testWidgets('in the reader, a listening move names its landing by its '
      'share of the ebook and its chapter until the reader measures the '
      'open book, and then by its page', (tester) async {
    final downloads = LocalFiles()
      ..files[pdfSource.key] = simple.uri
      ..files[narration.files.single.key] = Uri.file('/narration.mp3');
    addTearDown(downloads.dispose);
    final document = await tester.runAsync(
      () => loadReadingDocument(verified(simple), pdfSource),
    );
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: loadPublication,
      loadDocument: (_, _) async => document!,
    );
    final crossings = Crossings(
      store: MemoryOutlines(),
      measure: (_) async => outline,
      hop: <M, R>(work, input) async => work(input),
    );
    addTearDown(crossings.dispose);
    // A listening move from the start to 90 s, half of chapter Two. The
    // player runs on real time, as the app's does.
    late final Playback playback;
    await tester.runAsync(() async {
      playback = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: MediumSpy(),
      );
      await playback.bind(account(), [both]);
      await playback.open(both, narration, autoplay: false);
      await playback.seekEdition(90000);
      await playback.flush();
      playback.dismissUndo();
    });
    await reader.bind(account(), [both]);
    await tester.runAsync(() => reader.open(both, pages));
    await tester.runAsync(
      () => crossings.landing(
        playback.history.first.after,
        from: narration,
        into: pages,
      ),
    );

    // The History opens over the open book before the reader shows it, so
    // the reader has not measured it.
    final shown = ValueNotifier(false);
    addTearDown(shown.dispose);
    late BuildContext page;
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: CrossingsScope(
          crossings: crossings,
          child: ReaderScope(
            reader: reader,
            show: (_) {},
            child: Builder(
              builder: (context) {
                page = context;
                return ValueListenableBuilder(
                  valueListenable: shown,
                  builder: (_, shown, _) => shown
                      ? ReaderScreen(reader: reader, onNightChanged: (_) {})
                      : const SizedBox.expand(),
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(reader.bookMap, isNull);
    openHistory(page, playback, book: both, showing: EditionKind.text);
    await tester.pumpAndSettle();
    Finder inTimeline(Finder finder) =>
        find.descendant(of: find.byType(HistoryTimeline), matching: finder);
    await tester.tap(inTimeline(find.text('→ 1:30')));
    await tester.pumpAndSettle();
    Finder inTile(String role, Finder finder) => find.descendant(
      of: find
          .ancestor(
            of: inTimeline(find.text(role)),
            matching: find.byType(InkWell),
          )
          .first,
      matching: finder,
    );

    // Half of chapter Two: 1500 of the book's 2000 characters.
    expect(inTile('AFTER', find.text('about 75%')), findsOneWidget);
    expect(inTile('AFTER', find.text('Two')), findsOneWidget);
    expect(inTile('BEFORE', find.text('about 0%')), findsOneWidget);
    expect(inTile('BEFORE', find.text('One')), findsOneWidget);
    expect(inTimeline(find.text('1:30')), findsNothing);

    // The reader shows the book under the sheet, and measures it.
    shown.value = true;
    for (var wait = 0; wait < 40 && reader.bookMap == null; wait++) {
      await settleNative(tester);
    }
    expect(reader.bookMap, isNotNull);
    await tester.pumpAndSettle();
    expect(inTile('AFTER', find.text('about p. 2')), findsOneWidget);
    expect(inTile('AFTER', find.text('Two')), findsOneWidget);
    expect(inTile('BEFORE', find.text('about p. 1')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    reader.dispose();
    await tester.runAsync(reader.flush);
    await tester.runAsync(playback.close);
    await tester.pump();
  });
}
