// In reflow, a page whose own content cannot reflow shows its original
// page fitted to the screen, and nothing else: a cover of a few short
// lines, a contents page of titles beside page numbers, or a page with no
// text. Only a failure that the person can act on keeps its quiet line.
import 'dart:io';

import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'ocr_cancel_screen_test.dart' show PendingScan, waitFor;
import 'ocr_position_test.dart' show native;
import 'ocr_test.dart' show blankPage, blankPages;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_session_test.dart' show book, edition;
import 'quiet_pdf_test.dart' show notices;

String _line(String words, int left, int top, int right, int bottom) =>
    '<span class="ocr_line" title="bbox $left $top $right $bottom">'
    '${words.split(' ').map((word) => '<span class="ocrx_word">$word</span>').join(' ')}'
    '</span>';

/// Recognition output of a book cover: the publisher, the title, the
/// subtitle and the author, one short line under the other.
final coverPage =
    '<div class="ocr_page">'
    '${_line('palgrave', 600, 100, 1000, 160)}'
    '${_line('macmillan', 600, 170, 1000, 230)}'
    '${_line('Nihil Unbound', 300, 700, 1300, 800)}'
    '${_line('Enlightenment and Extinction', 300, 850, 1300, 920)}'
    '${_line('Ray Brassier', 500, 1800, 1100, 1870)}'
    '</div>';

/// Recognition output of a contents page: each chapter title with its page
/// number beside it on the same row.
final contentsPage =
    '<div class="ocr_page">'
    '${_line('Part I: Destroying the Manifest Image', 100, 300, 1100, 350)}'
    '${_line('1', 1400, 300, 1430, 350)}'
    '${_line('The Apoptosis of Belief', 100, 400, 1100, 450)}'
    '${_line('3', 1400, 400, 1430, 450)}'
    '${_line('The Myth of the Given and the Origin', 100, 500, 1100, 550)}'
    '${_line('32', 1400, 500, 1450, 550)}'
    '</div>';

void main() {
  const channel = MethodChannel('bookfin/ocr');
  late Directory root;
  late PendingScan pdf;
  late LocalFiles downloads;
  late ReaderSession reader;
  late Future<String> Function() recognize;
  var nativeCalls = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookfin-reflow-original-');
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'close') return null;
          if (call.method != 'recognize') {
            throw StateError('Unexpected OCR method: ${call.method}');
          }
          nativeCalls++;
          return recognize();
        });
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    expect(reader.message, isNull);
  });

  /// Shows the reader in reflow on source page 1, and waits until the
  /// recognition of that page finished and its original page is drawn.
  Future<void> reflowFirstPage(WidgetTester tester) async {
    reader.setReflow(true);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await native(tester, () async {
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
    pdf.finishRender();
    await waitFor(
      tester,
      () =>
          nativeCalls == 1 &&
          !pdf.textSupply.recognizing.value &&
          find.bySemanticsLabel('Original source page 1').evaluate().isNotEmpty,
    );
    // The page's text reaches the view a few frames after recognition.
    for (var frame = 0; frame < 10; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  /// The reflowed text of the shown page.
  final reflowed = find.descendant(
    of: find.byType(PdfViewport),
    matching: find.byType(SingleChildScrollView),
  );

  testWidgets('a cover of a few short lines shows its original page in reflow, '
      'with no message', (tester) async {
    recognize = () async => coverPage;
    await reflowFirstPage(tester);
    expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
    expect(reflowed, findsNothing);
    expect(notices(tester), isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'a contents page of titles beside page numbers shows its original page '
    'in reflow, with no message',
    (tester) async {
      recognize = () async => contentsPage;
      await reflowFirstPage(tester);
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
      expect(reflowed, findsNothing);
      expect(notices(tester), isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a page with no text shows its original page in reflow, with no message',
    (tester) async {
      recognize = () async => blankPage;
      await reflowFirstPage(tester);
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
      expect(reflowed, findsNothing);
      expect(notices(tester), isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a page whose recognition fails keeps its quiet line over the original '
    'page',
    (tester) async {
      recognize = () async => throw PlatformException(code: 'recognition');
      await reflowFirstPage(tester);
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
      expect(notices(tester), ['Text recognition failed on this page.']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
