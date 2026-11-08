import 'dart:async';
import 'dart:io';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'ocr_position_test.dart' show native;
import 'ocr_test.dart' show blankPages, englishPage;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_navigation_test.dart' show HeldPdf;
import 'pdf_session_test.dart' show book, edition;
import 'reader_settings.dart';

class PendingScan extends HeldPdf {
  PendingScan(this.originalDigest);
  @override
  final String originalDigest;
  @override
  final BundledEnglishText textSupply = BundledEnglishText();
  Future<void>? _closing;

  @override
  Future<PdfText> text(int sourcePage) => textSupply.text(
    this,
    sourcePage,
    const PdfText(
      source: '',
      text: '',
      sourceOffsets: [],
      status: PdfTextStatus.absent,
    ),
  );

  @override
  Future<void> dispose() => _closing ??= textSupply.close();

  void finishRender() {
    if (!rendering.isCompleted) {
      rendering.complete(PdfRaster(1, 1, Uint8List.fromList([0, 0, 0, 255])));
    }
  }
}

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (ready()) return;
  }
  fail('The reader did not reach the expected visible state.');
}

/// Whether the reflowed view is done with the page text: it no longer
/// checks the text, and shows the text or says why it cannot.
bool textSettled() =>
    find.text('Checking source-page text.').evaluate().isEmpty;

void main() {
  const channel = MethodChannel('bookfin/ocr');
  late Directory root;
  late PendingScan pdf;
  late LocalFiles downloads;
  late ReaderSession reader;
  late Completer<String> firstRecognition;
  var nativeCalls = 0;
  var retryFails = false;
  var holdFirstNative = false;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookfin-cancel-screen-');
    final bytes = blankPages(2);
    final original = await File('${root.path}/complete').writeAsBytes(bytes);
    pdf = PendingScan(sha256.convert(bytes).toString());
    downloads = LocalFiles()..files[pdfSource.key] = original.uri;
    reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: loadPublication,
      loadDocument: (_, _) async => pdf,
    );
    nativeCalls = 0;
    retryFails = false;
    holdFirstNative = false;
    firstRecognition = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'close') return null;
          if (call.method != 'recognize') {
            throw StateError('Unexpected OCR method: ${call.method}');
          }
          nativeCalls++;
          if (holdFirstNative && nativeCalls == 1) {
            final text = await firstRecognition.future;
            if (retryFails) throw PlatformException(code: 'recognition');
            return text;
          }
          if (retryFails) throw PlatformException(code: 'recognition');
          return englishPage;
        });
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    expect(reader.message, isNull);
  });

  Future<void> showReader(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await native(tester, () async {
        pdf.finishRender();
        if (!firstRecognition.isCompleted) {
          firstRecognition.complete(englishPage);
        }
        await reader.flush();
        reader.dispose();
        await pdf.dispose();
        downloads.dispose();
        await root.delete(recursive: true);
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
      ),
    );
    await waitFor(tester, () => pdf.textSupply.recognizing.value);
  }

  testWidgets(
    'cancel and retry preserve an unresolved nonzero saved place until an explicit source-page choice',
    (tester) async {
      await native(tester, () async {
        reader.acceptAddress(
          reader.token,
          PdfAddress(
            2,
            10,
            quote: 'garden.',
            representation: 'previous-recognition',
          ),
        );
        await reader.addBookmark(title: 'Saved scan passage');
        await reader.flush();
        pdf = PendingScan(pdf.originalDigest);
        await reader.open(book, edition);
      });
      final savedAnchor = reader.bookmarks.single.position.anchor;
      expect((reader.initialAddress as PdfAddress).character, 10);
      await showReader(tester);
      await tester.tap(find.text('Stop waiting'));
      await tester.pump();
      expect(find.byType(ErrorWidget), findsNothing);
      expect(reader.position!.anchor, savedAnchor);
      expect(reader.position!.sourceKey, pdfSource.key);
      await tester.tap(find.text('Retry recognition'));
      await tester.pump();
      pdf.finishRender();
      await waitFor(
        tester,
        () =>
            find
                .bySemanticsLabel('Original source page 2')
                .evaluate()
                .isNotEmpty &&
            nativeCalls == 1,
      );
      await chooseSetting(tester, 'Reflow text', settle: tester.pump);
      await waitFor(tester, textSettled);
      expect(
        find.descendant(
          of: find.byType(PdfViewport),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
      expect(
        find.textContaining('The saved text position is not available'),
        findsOneWidget,
      );
      expect(reader.position!.anchor, savedAnchor);
      expect(reader.bookmarks.single.position.anchor, savedAnchor);
      await native(tester, () => reader.goToContents('page:2'));
      await tester.pump();
      expect(find.text('The quiet garden.'), findsOneWidget);
      expect((reader.visibleAddress as PdfAddress).sourcePage, 2);
      expect((reader.visibleAddress as PdfAddress).character, 0);
      expect(nativeCalls, 1, reason: 'The selected OCR text remains reusable.');
      expect(reader.bookmarks.single.position.anchor, savedAnchor);
      pdf.textSupply.checkInvariants();
      reader.checkInvariants();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final pending in ['render', 'native recognition']) {
    for (final outcome in ['success', 'failure']) {
      testWidgets(
        'cancel during pending $pending keeps controls and original fallback through retry $outcome',
        (tester) async {
          retryFails = outcome == 'failure';
          holdFirstNative = pending == 'native recognition';
          await showReader(tester);
          if (pending == 'native recognition') {
            pdf.finishRender();
            await waitFor(tester, () => nativeCalls == 1);
          } else {
            expect(nativeCalls, 0);
            expect(
              find.bySemanticsLabel('Original source page 1'),
              findsNothing,
            );
          }
          expect(find.text('Recognizing English text…'), findsOneWidget);
          await tester.tap(find.text('Stop waiting'));
          await tester.pump();
          expect(find.byType(ErrorWidget), findsNothing);
          expect(find.text('Retry recognition'), findsOneWidget);
          expect(find.byTooltip('Next page'), findsOneWidget);
          expect((reader.visibleAddress as PdfAddress).toJson(), {
            'page': 1,
            'character': 0,
            'quote': '',
          });
          expect(find.textContaining('of null'), findsNothing);
          // The scrub bar counts the shown page of the two as read.
          expect(tester.widget<Slider>(find.byType(Slider)).value, .5);

          await tester.tap(find.text('Retry recognition'));
          await tester.pump();
          expect(
            nativeCalls,
            pending == 'render' ? 0 : 1,
            reason: 'Retry joins the page that started.',
          );
          pdf.finishRender();
          firstRecognition.complete(englishPage);
          await waitFor(
            tester,
            () => find
                .bySemanticsLabel('Original source page 1')
                .evaluate()
                .isNotEmpty,
          );
          await chooseSetting(tester, 'Reflow text', settle: tester.pump);
          await waitFor(tester, textSettled);
          expect(nativeCalls, 1);
          expect(find.byType(ErrorWidget), findsNothing);
          if (retryFails) {
            expect(
              find.descendant(
                of: find.byType(PdfViewport),
                matching: find.byType(SingleChildScrollView),
              ),
              findsNothing,
            );
            expect(
              find.bySemanticsLabel('Original source page 1'),
              findsOneWidget,
            );
            expect(find.text('Retry recognition'), findsOneWidget);
          } else {
            expect(find.text('The quiet garden.'), findsOneWidget);
            expect(reader.position!.sourceKey, pdfSource.key);
            expect(tester.widget<Slider>(find.byType(Slider)).value, .5);
          }
          pdf.textSupply.checkInvariants();
          reader.checkInvariants();
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    }
  }
}
