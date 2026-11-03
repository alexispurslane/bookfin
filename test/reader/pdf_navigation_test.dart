import 'dart:async';
import 'dart:typed_data';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class HeldPdf extends PdfBook {
  final rendering = Completer<PdfRaster>();
  int renders = 0;
  final source = List.generate(
    180,
    (i) => 'Line $i follows the river.',
  ).join(' ');
  @override
  String get originalDigest => 'fixture';
  @override
  String get identity => 'fixture';
  @override
  String get engine => 'fixture';
  @override
  String get policy => 'fixture';
  @override
  String get format => 'pdf';
  @override
  int get pageCount => 2;
  @override
  bool accepts(ReaderAddress address) =>
      address is PdfAddress && address.sourcePage <= 2;
  @override
  ReaderAddress decodeAddress(Map<String, dynamic> value) =>
      PdfAddress(value['page'] as int, value['character'] as int);
  @override
  Future<void> dispose() async {}
  @override
  Future<PdfText> text(int sourcePage) async => PdfText(
    source: source,
    text: source,
    sourceOffsets: List.generate(source.length, (i) => i),
    status: PdfTextStatus.candidate,
  );
  @override
  Future<PdfRaster> render(int sourcePage, double width) {
    renders++;
    return rendering.future;
  }
}

void main() {
  testWidgets(
    'repeated original-page requests share one pending draw and release its image',
    (tester) async {
      final book = HeldPdf();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfViewport(
              book: book,
              fontSize: 20,
              onReady: (_, _) {},
              onAddress: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Original page'));
      await tester.pump();
      await tester.tap(find.text('Original page'));
      await tester.pump();
      expect(
        book.renders,
        1,
        reason: 'One page generation owns one native draw.',
      );
      book.rendering.complete(
        PdfRaster(1, 1, Uint8List.fromList([0, 0, 0, 255])),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect(image.debugDisposed, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(image.debugDisposed, isTrue);
    },
  );

  testWidgets(
    'Previous from a reflow page boundary returns to the preceding final viewport',
    (tester) async {
      final book = HeldPdf();
      late DocumentNavigator navigation;
      PdfAddress? location;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfViewport(
              book: book,
              fontSize: 24,
              onReady: (value, _) => navigation = value,
              onAddress: (value) => location = value,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Reflow text'));
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      expect(
        scroll.position.maxScrollExtent,
        greaterThan(scroll.position.viewportDimension * 2),
      );
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      await navigation.move(true);
      await tester.pumpAndSettle();
      expect(location!.sourcePage, 2);
      expect(scroll.offset, 0);
      await navigation.move(false);
      await tester.pumpAndSettle();
      expect(location!.sourcePage, 1);
      expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
      expect(location!.character, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      book.rendering.complete(PdfRaster(1, 1, Uint8List(4)));
      await tester.pump();
    },
  );
}
