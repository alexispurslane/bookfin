import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_text_view.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_reader.dart' show finishReader;
import 'pdf_test_controller.dart';
import 'pdf_navigation_test.dart' show HeldPdf;
import 'pdf_viewport_test.dart' show Reports;

final _lines = List.generate(
  30,
  (index) => 'River ${index.toString().padLeft(2, '0')}',
);
final _source = _lines.join('\n');

class _MappedPdf extends HeldPdf {
  _MappedPdf() : super(source: _source.split('').join('~'));

  @override
  Future<PdfText> textLayer(int sourcePage) async => PdfText(
    source: source,
    text: _source,
    sourceOffsets: List.generate(_source.length, (index) => index * 2),
    status: PdfTextStatus.candidate,
    digest: 'mapped-text',
  );
}

Widget _reader(
  HeldPdf book,
  Reports reports, {
  PdfAddress? initial,
  double fontSize = 20,
  double width = 300,
  double height = 200,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        height: height,
        child: PdfTestController(
          book: book,
          fontSize: fontSize,
          view: PdfPageView.text,
          initial: initial,
          onReady: (navigator, _) => reports.navigator = navigator,
          onAddress: reports.addresses.add,
          onRefinedAddress: reports.addresses.add,
          onCancelRecognition: () {},
          onTap: () {},
          onTurn: (forward) => unawaited(reports.navigator!.move(forward)),
        ),
      ),
    ),
  ),
);

Future<void> _swipe(WidgetTester tester, bool forward) async {
  await tester.drag(find.byType(PdfViewport), Offset(forward ? -180 : 180, 0));
  await tester.pumpAndSettle();
}

Future<Uint8List> _pixels(
  WidgetTester tester,
  Size size,
  void Function(Canvas) draw,
) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  try {
    return (await tester.runAsync(() async {
      final image = await picture.toImage(
        size.width.ceil(),
        size.height.ceil(),
      );
      try {
        final data = (await image.toByteData())!;
        return Uint8List.fromList(data.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    }))!;
  } finally {
    picture.dispose();
  }
}

Future<void> _expectLines(WidgetTester tester, List<String> lines) async {
  final view = tester.widget<PdfTextView>(find.byType(PdfTextView));
  final text = lines.join('\n');
  final expected = TextPainter(
    text: TextSpan(text: text, style: view.screens.style),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 260);
  try {
    final reference = await _pixels(
      tester,
      const Size(260, 176),
      (canvas) => expected.paint(canvas, Offset.zero),
    );
    final actual = await _pixels(
      tester,
      const Size(260, 176),
      (canvas) => view.screens.paint(canvas, view.screen),
    );
    expect(actual, reference);
    expect(find.bySemanticsLabel(text), findsOneWidget);
  } finally {
    expected.dispose();
  }
}

void main() {
  testWidgets('horizontal turns show successive screens of whole lines', (
    tester,
  ) async {
    final book = HeldPdf(source: _source);
    final reports = Reports();
    await tester.pumpWidget(_reader(book, reports));
    await tester.pumpAndSettle();
    expect(reports.addresses.last.character, 0);
    await _swipe(tester, true);
    expect(reports.addresses.last.character, 45);
    await _swipe(tester, true);
    expect(reports.addresses.last.character, 90);
    await _swipe(tester, true);
    expect(reports.addresses.last.character, 135);
    await _swipe(tester, false);
    expect(reports.addresses.last.character, 90);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a vertical drag leaves the displayed text and saved place unchanged',
    (tester) async {
      final book = HeldPdf(source: _source);
      final reports = Reports();
      await tester.pumpWidget(_reader(book, reports));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PdfViewport), const Offset(0, -140));
      await tester.pumpAndSettle();
      expect(reports.addresses.last.character, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'each drawn screen contains whole lines and no part of the next line',
    (tester) async {
      final book = HeldPdf(source: _source);
      final reports = Reports();
      await tester.pumpWidget(_reader(book, reports));
      await tester.pumpAndSettle();
      for (var screen = 0; screen < 3; screen++) {
        await _expectLines(tester, _lines.skip(screen * 5).take(5).toList());
        await _swipe(tester, true);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'width and height changes keep the displayed place on the new screen',
    (tester) async {
      final book = HeldPdf(source: _source);
      final reports = Reports();
      await tester.pumpWidget(_reader(book, reports));
      await tester.pumpAndSettle();
      await _swipe(tester, true);
      final displayed = reports.addresses.last;
      await tester.pumpWidget(_reader(book, reports, width: 180, height: 220));
      await tester.pumpAndSettle();
      expect(reports.addresses.last.character, 27);
      final view = tester.widget<PdfTextView>(find.byType(PdfTextView));
      expect(view.screens.textOf(view.screen), contains('River 05'));
      expect(
        reports.addresses.last.character,
        lessThanOrEqualTo(displayed.character),
      );
      await _swipe(tester, true);
      expect(reports.addresses.last.character, 54);
      await tester.pumpWidget(_reader(book, reports, width: 180, height: 180));
      await tester.pumpAndSettle();
      expect(reports.addresses.last.character, 45);
      expect(
        tester.widget<PdfTextView>(find.byType(PdfTextView)).screens.textOf(2),
        contains('River 06'),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'screen places use source characters rather than normalized text offsets',
    (tester) async {
      final book = _MappedPdf();
      final reports = Reports();
      final saved = book.addressFor(1, await book.text(1), 220);
      await tester.pumpWidget(_reader(book, reports, initial: saved));
      await tester.pumpAndSettle();
      expect(reports.addresses.last.character, 180);
      expect(reports.addresses.last.quote, startsWith('R~i~v~e~r~ ~1~0'));
      await _swipe(tester, true);
      expect(reports.addresses.last.character, 270);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('book-end turns keep the first and last text screens in place', (
    tester,
  ) async {
    final book = HeldPdf(source: _lines.take(2).join('\n'));
    final reports = Reports();
    await tester.pumpWidget(_reader(book, reports));
    await tester.pumpAndSettle();
    await _swipe(tester, false);
    expect(
      (reports.addresses.last.sourcePage, reports.addresses.last.character),
      (1, 0),
    );
    await _swipe(tester, true);
    await _swipe(tester, true);
    expect(
      (reports.addresses.last.sourcePage, reports.addresses.last.character),
      (2, 0),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'turning past either source-page end shows its neighboring screen',
    (tester) async {
      final book = HeldPdf(source: _lines.take(12).join('\n'));
      final reports = Reports();
      await tester.pumpWidget(_reader(book, reports));
      await tester.pumpAndSettle();
      await _swipe(tester, true);
      expect(
        (reports.addresses.last.sourcePage, reports.addresses.last.character),
        (1, 45),
      );
      await _swipe(tester, true);
      expect(
        (reports.addresses.last.sourcePage, reports.addresses.last.character),
        (1, 90),
      );
      await _swipe(tester, true);
      expect(
        (reports.addresses.last.sourcePage, reports.addresses.last.character),
        (2, 0),
      );
      await _swipe(tester, false);
      expect(
        (reports.addresses.last.sourcePage, reports.addresses.last.character),
        (1, 90),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a word-view character opens the text screen that contains it', (
    tester,
  ) async {
    final book = HeldPdf(source: _source);
    final reports = Reports();
    final wordPlace = book.addressFor(1, await book.text(1), 110);
    await tester.pumpWidget(_reader(book, reports, initial: wordPlace));
    await tester.pumpAndSettle();
    expect(reports.addresses.last.character, 90);
    final saved = reports.addresses.last;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_reader(book, reports, initial: saved));
    await tester.pumpAndSettle();
    expect(reports.addresses.last.character, 90);
    expect(reports.addresses.last.representation, saved.representation);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reversing a source-page turn before a frame returns to the previous final screen',
    (tester) async {
      final book = HeldPdf(source: _lines.take(12).join('\n'));
      final reports = Reports();
      await tester.pumpWidget(_reader(book, reports));
      await tester.pumpAndSettle();
      await _swipe(tester, true);
      await _swipe(tester, true);
      expect(
        (reports.addresses.last.sourcePage, reports.addresses.last.character),
        (1, 90),
      );
      await finishReader(tester, reports.navigator!.move(true));
      await finishReader(tester, reports.navigator!.move(false));
      await tester.pumpAndSettle();
      expect(
        (reports.addresses.last.sourcePage, reports.addresses.last.character),
        (1, 90),
      );
      await finishReader(tester, reports.navigator!.move(false));
      await tester.pumpAndSettle();
      expect(
        (reports.addresses.last.sourcePage, reports.addresses.last.character),
        (1, 45),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a turn before the first text layout waits for that page rather than skipping it',
    (tester) async {
      final book = HeldPdf(source: _source);
      final reports = Reports();
      await tester.pumpWidget(_reader(book, reports));
      final turn = reports.navigator!.move(true);
      await tester.pumpAndSettle();
      await turn;
      expect(
        (reports.addresses.last.sourcePage, reports.addresses.last.character),
        (1, 45),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a size step keeps the displayed first character on screen', (
    tester,
  ) async {
    final book = HeldPdf(source: _source);
    final reports = Reports();
    await tester.pumpWidget(_reader(book, reports));
    await tester.pumpAndSettle();
    await _swipe(tester, true);
    await _swipe(tester, true);
    expect(reports.addresses.last.character, 90);
    await tester.pumpWidget(_reader(book, reports, fontSize: 30));
    await tester.pumpAndSettle();
    expect(reports.addresses.last.character, 81);
    await _swipe(tester, true);
    expect(reports.addresses.last.character, 108);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a screen beginning after a paragraph gap starts with its first text line',
    (tester) async {
      final book = HeldPdf(
        source:
            '${_lines.take(5).join('\n')}\n\n\n${_lines.skip(5).join('\n')}',
      );
      final reports = Reports();
      await tester.pumpWidget(_reader(book, reports));
      await tester.pumpAndSettle();
      await _swipe(tester, true);
      expect(reports.addresses.last.character, 47);
      await _expectLines(tester, _lines.skip(5).take(5).toList());
      await _swipe(tester, true);
      expect(reports.addresses.last.character, 92);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
