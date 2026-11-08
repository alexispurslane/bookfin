import 'dart:io';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_session_test.dart' show book, edition;

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
      File('tool/research/readers/fixtures/simple.pdf').absolute.uri,
      pdfSource,
    ) as PdfBook;
  });

  testWidgets(
    'PDF controls reflow real extracted text and keep source-page bookmarks',
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
      await tester.tap(find.byTooltip('Reflow text'));
      await settleNative(tester);
      expect(
        find.textContaining('The river follows the old road.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Pictures and page layout stay in the original page.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Next page'));
      await settleNative(tester);
      expect(find.textContaining('River chapter 2'), findsOneWidget);
      expect((reader.visibleAddress as PdfAddress).sourcePage, 2);
      await tester.tap(find.byTooltip('Bookmark this place'));
      await tester.pumpAndSettle();
      expect(reader.bookmarks.single.position.sourcePage, 2);
      await tester.tap(find.byTooltip('Original page'));
      await settleNative(tester);
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
                  File('tool/research/readers/fixtures/simple.pdf')
                      .absolute
                      .uri,
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
      expect(bar().value, 0);
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
      expect(bar().value, 1 / pages);
      expect(find.text('Source page 2 · Page 2 of $pages'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      reader.dispose();
      downloads.dispose();
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
