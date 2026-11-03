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
      await tester.tap(find.text('Reflow text'));
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
      await tester.tap(find.text('Original page'));
      await settleNative(tester);
      expect(find.bySemanticsLabel('Original source page 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      reader.dispose();
      downloads.dispose();
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
