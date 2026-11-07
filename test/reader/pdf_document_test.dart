import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const pdfSource = SourceFile(
  itemId: 'pdf',
  displayName: 'Simple.pdf',
  mediaSourceId: 'original',
  revision: 'one',
  durationMs: null,
  container: 'pdf',
  sizeBytes: 1000,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  test('an extraction isolate cannot initialize a second native font-callback owner', () async {
    await expectLater(
      Isolate.run(() async => PdfRuntime.instance.open(Uint8List(0))),
      throwsStateError,
    );
  });
  test(
    'the production importer opens the verified PDF as original source pages',
    () async {
      final document = await loadReadingDocument(
        File('tool/research/readers/fixtures/simple.pdf').absolute.uri,
        pdfSource,
      );
      expect(document.format, 'pdf');
      addTearDown(document.dispose);
      final pdf = document as PdfBook;
      expect(pdf.pageCount, 2);
      final text = await pdf.text(1);
      expect(text.status, PdfTextStatus.candidate);
      expect(text.text, contains('The river follows the old road.'));
      expect(text.sourceOffsets, hasLength(text.text.length));
      final image = await pdf.render(1, 360);
      expect(image.width, 360);
      expect(image.bgra.any((value) => value < 200), isTrue);
    },
  );

  test('an opened PDF keeps the digest and identity that saved places and OCR caches use', () async {
    final bytes = await File('tool/research/readers/fixtures/simple.pdf')
        .readAsBytes();
    final book = await PdfRuntime.instance.open(bytes);
    addTearDown(book.dispose);
    // Saved reading places and OCR caches are keyed by these values, so a
    // change here would orphan them.
    expect(
      book.originalDigest,
      '51d05de2a89dd83fb8f04301ac254419b2d616d48f6e8bb9fbe0938745bc04ce',
    );
    expect(
      book.identity,
      '39cd1ab8b3cd4b412994d1e5bfd7174075542b35c2a7866b9978d48edaf4a823',
    );
  });

  test(
    'a scanned source page keeps its visible original without inventing text',
    () async {
      final document = await loadReadingDocument(
        File('tool/research/readers/fixtures/scanned.pdf').absolute.uri,
        pdfSource,
      ) as PdfBook;
      addTearDown(document.dispose);
      expect((await document.text(1)).status, PdfTextStatus.absent);
      final image = await document.render(1, 360);
      expect(image.bgra.any((value) => value < 200), isTrue);
    },
  );

  for (final fixture in ['columns', 'table']) {
    test(
      '$fixture pages keep the original instead of offering misleading text order',
      () async {
        final document = await loadReadingDocument(
          File('tool/research/readers/fixtures/$fixture.pdf').absolute.uri,
          pdfSource,
        ) as PdfBook;
        addTearDown(document.dispose);
        final text = await document.text(1);
        expect(text.source, isNotEmpty);
        expect(text.status, PdfTextStatus.unreliable);
        expect(text.reason, contains('original page'));
        expect((await document.render(1, 360)).width, 360);
      },
    );
  }

  test(
    'closing drains admitted page work and the shared engine can restart',
    () async {
      final bytes = await File('tool/research/readers/fixtures/simple.pdf')
          .readAsBytes();
      final books = await Future.wait([
        PdfRuntime.instance.open(bytes),
        PdfRuntime.instance.open(bytes),
      ]);
      final rendering = books.first.render(1, 360);
      final text = books.last.text(2);
      final closing = PdfRuntime.instance.shutdown();
      expect((await rendering).width, 360);
      expect((await text).text, contains('River chapter 2'));
      await closing;
      await expectLater(books.first.render(1, 360), throwsStateError);
      PdfRuntime.instance.checkInvariants();
      final reopened = await PdfRuntime.instance.open(bytes);
      expect((await reopened.text(1)).text, contains('River chapter 1'));
      await reopened.dispose();
    },
  );
}
