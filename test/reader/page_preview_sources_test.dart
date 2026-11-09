import 'dart:async';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pdf_navigation_test.dart' show HeldPdf;
import 'pdf_viewport_host.dart';

/// A two-page PDF that notes each page that it draws, and its width.
class DrawingPdf extends HeldPdf {
  DrawingPdf() {
    rendering.complete(PdfRaster(1, 1, Uint8List.fromList([0, 0, 0, 255])));
  }
  final drawn = <(int, double)>[];
  @override
  Future<PdfRaster> render(int sourcePage, double width) {
    drawn.add((sourcePage, width));
    return super.render(sourcePage, width);
  }
}

void main() {
  testWidgets('a PDF page preview is its source page, drawn at the asked '
      'width, with the pages around it', (tester) async {
    final book = DrawingPdf();
    late DocumentNavigator navigator;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfViewportHost(
            book: book,
            fontSize: 20,
            onReady: (ready, _) => navigator = ready,
            onAddress: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    book.drawn.clear();
    final last = (await tester.runAsync(
      () => navigator.preview(
        (part: 1, progress: .3),
        240,
        Completer<void>().future,
      ),
    ))!;
    expect(book.drawn, [(2, 240.0)]);
    expect(last.part, 1);
    expect((last.start, last.end), (0.0, 1.0));
    expect(last.previous, (part: 0, progress: 0.0));
    expect(last.next, isNull);
    final first = (await tester.runAsync(
      () => navigator.preview(
        (part: 0, progress: 0),
        240,
        Completer<void>().future,
      ),
    ))!;
    expect(first.previous, isNull);
    expect(first.next, (part: 1, progress: 0.0));
    last.image.dispose();
    first.image.dispose();
  });
}
