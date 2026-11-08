import 'dart:io';

import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_screen_test.dart' show settleNative;
import 'pdf_session_test.dart' show book, edition;

/// The widgets that rebuilt while [during] ran.
Future<List<Widget>> _rebuildsDuring(Future<void> Function() during) async {
  final rebuilt = <Widget>[];
  debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
  try {
    await during();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return rebuilt;
}

/// The tooltips of the reader's own controls, apart from the PDF viewport's.
const _controls = {
  'Contents',
  'Search book',
  'Reading settings',
  'Bookmark this place',
  'Previous page',
  'Next page',
  'Hide reader controls',
};

Iterable<IconButton> _controlButtons(List<Widget> rebuilt) => rebuilt
    .whereType<IconButton>()
    .where((button) => _controls.contains(button.tooltip));

Iterable<Text> _texts(List<Widget> rebuilt, bool Function(String) test) =>
    rebuilt.whereType<Text>().where(
      (text) => text.data != null && test(text.data!),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  late PdfBook document;
  // Closing the session closes its document, so each test loads its own.
  setUp(() async {
    document = await loadReadingDocument(
      File('tool/research/readers/fixtures/simple.pdf').absolute.uri,
      pdfSource,
    ) as PdfBook;
  });

  /// Opens the reader on the PDF fixture and waits until its first page
  /// shows.
  Future<ReaderSession> openPdf(WidgetTester tester) async {
    final downloads = LocalFiles()
      ..files[pdfSource.key] = File('tool/research/readers/fixtures/simple.pdf')
          .absolute
          .uri;
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: loadPublication,
      loadDocument: (_, _) async => document,
    );
    addTearDown(downloads.dispose);
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
      ),
    );
    await settleNative(tester);
    expect(reader.ready, isTrue);
    return reader;
  }

  Future<void> close(WidgetTester tester, ReaderSession reader) async {
    await tester.pumpWidget(const SizedBox());
    reader.dispose();
    await tester.pump();
  }

  testWidgets('a page turn redraws the page label and the scrub bar, not the '
      'viewport, the title or the controls row', (tester) async {
    final reader = await openPdf(tester);
    final pages = document.pageCount;
    // The viewport reports a new page, as it does after a swipe.
    final rebuilt = await _rebuildsDuring(() async {
      reader.acceptAddress(reader.token, PdfAddress(2, 0, pageCount: pages));
      await tester.pump();
    });
    expect(
      _texts(rebuilt, (text) => text.endsWith('Page 2 of $pages')),
      isNotEmpty,
    );
    expect(rebuilt.whereType<Slider>(), isNotEmpty);
    expect(rebuilt.whereType<PdfViewport>(), isEmpty);
    expect(_controlButtons(rebuilt), isEmpty);
    expect(
      _texts(rebuilt, (text) => text == book.title),
      isEmpty,
      reason: 'the title in the app bar',
    );
    await close(tester, reader);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'choosing reflow redraws the viewport, not the title or the dock',
    (tester) async {
      final reader = await openPdf(tester);
      final rebuilt = await _rebuildsDuring(() async {
        reader.setReflow(true);
        await tester.pump();
      });
      final viewports = rebuilt.whereType<PdfViewport>();
      expect(viewports, isNotEmpty);
      expect(viewports.map((viewport) => viewport.reflow), everyElement(true));
      expect(_controlButtons(rebuilt), isEmpty);
      expect(
        _texts(rebuilt, (text) => text == book.title),
        isEmpty,
        reason: 'the title in the app bar',
      );
      await close(tester, reader);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'a text size change redraws the viewport, not the page label or the '
    'controls row',
    (tester) async {
      final reader = await openPdf(tester);
      final rebuilt = await _rebuildsDuring(() async {
        await reader.setFontSize(reader.fontSize + 2);
        await tester.pump();
      });
      final viewports = rebuilt.whereType<PdfViewport>();
      expect(viewports, isNotEmpty);
      expect(
        viewports.map((viewport) => viewport.fontSize),
        everyElement(reader.fontSize),
      );
      expect(_texts(rebuilt, (text) => text.contains('Page ')), isEmpty);
      expect(rebuilt.whereType<Slider>(), isEmpty);
      expect(_controlButtons(rebuilt), isEmpty);
      await close(tester, reader);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
