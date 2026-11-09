import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../downloads/verified_reads.dart';

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
        verified(File('tool/research/readers/fixtures/simple.pdf').absolute),
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

  test('an address inside an extracted page keeps the representation that '
      'saved places use', () async {
    final bytes = await File('tool/research/readers/fixtures/simple.pdf')
        .readAsBytes();
    final book = await PdfRuntime.instance.open(bytes);
    addTearDown(book.dispose);
    // Saved places inside a page compare this value, so a change here
    // would move every such place back to the start of its page.
    expect(
      book.addressFor(1, await book.text(1), 10).representation,
      'bookfin-pdf-source-pages-1/pdfrx-0.9.0-pdfium-8125/extracted/'
      '6809befa2062965afe8125645eb4e02934d3edbf04af2c75be151563f835558e',
    );
  });

  test(
    'each page text is prepared in one worker hop that also names its digest',
    () async {
      final bytes = await File('tool/research/readers/fixtures/simple.pdf')
          .readAsBytes();
      final inputs = <Object?>[];
      final outputs = <Object?>[];
      Future<R> hop<M, R>(FutureOr<R> Function(M) work, M input) async {
        inputs.add(input);
        final output = await Isolate.run(() => work(input));
        outputs.add(output);
        return output;
      }

      final book = await PdfRuntime.instance.open(bytes, hop: hop);
      addTearDown(book.dispose);
      final text = await book.text(1);
      await book.text(1);
      expect(inputs, hasLength(1));
      final page = inputs.single! as ({String source, Float64List boxes});
      expect(page.boxes, hasLength(page.source.length * 4));
      expect(outputs.single, same(text));
      expect(text.text, contains('The river follows the old road.'));
      expect(
        text.digest,
        '6809befa2062965afe8125645eb4e02934d3edbf04af2c75be151563f835558e',
      );
      await book.text(2);
      expect(inputs, hasLength(2));
    },
  );

  test(
    'a scanned source page keeps its visible original without inventing text',
    () async {
      final document = await loadReadingDocument(
        verified(File('tool/research/readers/fixtures/scanned.pdf').absolute),
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
          verified(
            File('tool/research/readers/fixtures/$fixture.pdf').absolute,
          ),
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
