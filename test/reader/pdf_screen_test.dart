import 'dart:io';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_text_view.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/reader/word_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_session_test.dart' show book, edition;
import 'reader_settings.dart';
import '../downloads/verified_reads.dart';

Future<void> settleNative(WidgetTester tester) async {
  for (var attempt = 0; attempt < 12; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  late PdfBook document;
  setUpAll(() async {
    document = await loadReadingDocument(
      verified(File('tool/research/readers/fixtures/simple.pdf').absolute),
      pdfSource,
    ) as PdfBook;
  });

  testWidgets(
    'PDF controls reflow real word images and keep source-page bookmarks',
    (tester) async {
      final downloads = LocalFiles()
        ..files[pdfSource.key] = File(
          'tool/research/readers/fixtures/simple.pdf',
        ).absolute.uri;
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: loadPublication,
        loadDocument: (_, _) async => document,
      );
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
        ),
      );
      await settleNative(tester);
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
      await chooseSetting(
        tester,
        'Page words',
        settle: () => settleNative(tester),
      );
      WordScreen shown() => tester
          .widget<WordScreenView>(find.byType(WordScreenView))
          .screen
          .value!;
      expect(shown().page, 1);
      expect(shown().bands, isNotEmpty);
      expect(
        (await tester.runAsync(() => document.text(1)))!.text,
        contains('The river follows the old road.'),
      );
      expect(
        find.textContaining('Pictures and page layout'),
        findsNothing,
        reason: 'No notice covers a reflowed page.',
      );
      for (var turn = 0; turn < 20 && shown().page == 1; turn++) {
        await tester.tap(find.byTooltip('Next page'));
        await settleNative(tester);
      }
      expect(shown().page, 2);
      expect(shown().bands, isNotEmpty);
      expect(
        (await tester.runAsync(() => document.text(2)))!.text,
        contains('River chapter 2'),
      );
      expect((reader.visibleAddress as PdfAddress).sourcePage, 2);
      final wordPlace = reader.visibleAddress as PdfAddress;
      await chooseSetting(tester, 'Text', settle: () => settleNative(tester));
      expect(find.byType(WordScreenView), findsNothing);
      final readingText = find.byType(PdfTextView);
      expect(readingText, findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('River chapter 2')), findsOneWidget);
      expect(
        tester.widget<PdfTextView>(readingText).screens.style.fontFamily,
        'Source Serif 4',
      );
      expect(
        (reader.visibleAddress as PdfAddress).sourcePage,
        wordPlace.sourcePage,
      );
      await tester.tap(find.byTooltip('Bookmark this place'));
      await tester.pumpAndSettle();
      expect(reader.bookmarks.single.position.sourcePage, 2);
      await chooseSetting(
        tester,
        'Original page',
        settle: () => settleNative(tester),
      );
      expect(find.bySemanticsLabel('Original source page 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      reader.dispose();
      downloads.dispose();
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'the PDF bar measures the whole document, previews a source page while '
    'it is dragged and opens that page on release',
    (tester) async {
      final downloads = LocalFiles()
        ..files[pdfSource.key] = File(
          'tool/research/readers/fixtures/simple.pdf',
        ).absolute.uri;
      // The session releases its document when it closes, so this test
      // opens a document of its own.
      final document =
          (await tester.runAsync(
                () => loadReadingDocument(
                  verified(
                    File('tool/research/readers/fixtures/simple.pdf').absolute,
                  ),
                  pdfSource,
                ),
              ))!
              as PdfBook;
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: loadPublication,
        loadDocument: (_, _) async => document,
      );
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
        ),
      );
      await settleNative(tester);
      final pages = document.pageCount;
      expect(pages, greaterThan(1));
      Slider bar() => tester.widget<Slider>(find.byType(Slider));
      // The shown page counts as read.
      expect(bar().value, 1 / pages);
      // The second source page holds the second of the equal shares.
      final second = 1.5 / pages;
      bar().onChangeStart!(0);
      bar().onChanged!(second);
      await tester.pump();
      expect(find.text('Page 2 of $pages'), findsOneWidget);
      expect((reader.visibleAddress as PdfAddress).sourcePage, 1);
      bar().onChangeEnd!(second);
      await settleNative(tester);
      expect((reader.visibleAddress as PdfAddress).sourcePage, 2);
      expect(bar().value, 2 / pages);
      expect(
        find.bySemanticsLabel('Source page 2 · Page 2 of $pages'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      reader.dispose();
      downloads.dispose();
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
