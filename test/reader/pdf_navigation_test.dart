import 'dart:async';
import 'dart:typed_data';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pdf_viewport_host.dart';

class HeldPdf extends PdfBook {
  final rendering = Completer<PdfRaster>();
  int renders = 0;
  HeldPdf({String? source})
    : source =
          source ??
          List.generate(180, (i) => 'Line $i follows the river.').join(' ');
  final String source;
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
  ReaderAddress decodeAddress(Map<String, dynamic> value) => PdfAddress(
    value['page'] as int,
    value['character'] as int,
    quote: value['quote'] as String? ?? '',
    representation: value['representation'] as String?,
  );
  @override
  Future<void> dispose() async {}
  @override
  Future<PdfText> text(int sourcePage) async => PdfText(
    source: source,
    text: source,
    sourceOffsets: List.generate(source.length, (i) => i),
    status: PdfTextStatus.candidate,
    digest: 'fixture-text',
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
            body: PdfViewportHost(
              book: book,
              fontSize: 20,
              onReady: (_, _) {},
              onAddress: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      for (var turn = 0; turn < 2; turn++) {
        await tester.tap(find.byTooltip('Reflow text'));
        await tester.pump();
        await tester.tap(find.byTooltip('Original page'));
        await tester.pump();
      }
      expect(
        book.renders,
        1,
        reason: 'One page generation owns one native draw.',
      );
      book.rendering.complete(
        PdfRaster(1, 1, Uint8List.fromList([0, 0, 0, 255])),
      );
      // Decoding needs real time, and more of it on a busy machine.
      for (var attempt = 0; attempt < 300; attempt++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (find.byType(RawImage).evaluate().isNotEmpty) break;
      }
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
            body: PdfViewportHost(
              book: book,
              fontSize: 24,
              onReady: (value, _) => navigation = value,
              onAddress: (value) => location = value,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Reflow text'));
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
  testWidgets(
    'Previous onto a short page saves its visible beginning for larger-text restoration',
    (tester) async {
      final book = HeldPdf(
        source: List.generate(12, (i) => 'River sentence $i.').join(' '),
      );
      late DocumentNavigator navigation;
      PdfAddress? location;
      Widget reader(double size, {PdfAddress? initial}) => MaterialApp(
        home: Scaffold(
          body: PdfViewportHost(
            book: book,
            fontSize: size,
            initial: initial,
            onReady: (value, _) => navigation = value,
            onAddress: (value) => location = value,
          ),
        ),
      );
      await tester.pumpWidget(reader(20));
      await tester.pump();
      await tester.tap(find.byTooltip('Reflow text'));
      await tester.pumpAndSettle();
      ScrollController scroll() => tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      expect(scroll().position.maxScrollExtent, 0);
      await navigation.move(true);
      await tester.pumpAndSettle();
      expect(location!.sourcePage, 2);
      await navigation.move(false);
      await tester.pumpAndSettle();
      expect(location!.sourcePage, 1);
      expect(location!.character, 0);
      expect(location!.quote, startsWith('River sentence 0.'));
      final saved = location!;
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(const Size(300, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(reader(40, initial: saved));
      await tester.pump();
      await tester.tap(find.byTooltip('Reflow text'));
      await tester.pumpAndSettle();
      expect(scroll().position.maxScrollExtent, greaterThan(0));
      expect(scroll().offset, 0);
      expect(location!.character, 0);
      expect(location!.quote, startsWith('River sentence 0.'));
      await tester.pumpWidget(const SizedBox());
      book.rendering.complete(PdfRaster(1, 1, Uint8List(4)));
      await tester.pump();
    },
  );
}
