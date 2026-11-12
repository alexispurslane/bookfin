import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../downloads/verified_reads.dart';
import 'ocr_test.dart' show englishPage;

const pdfSource = SourceFile(
  itemId: 'pdf',
  displayName: 'Simple.pdf',
  mediaSourceId: 'original',
  revision: 'one',
  durationMs: null,
  container: 'pdf',
  sizeBytes: 1000,
);

/// A two-page PDF of text.
const simple = 'tool/research/readers/fixtures/simple.pdf';

/// The SHA-256 of simple.pdf, as Downloads records it.
const simpleDigest =
    '51d05de2a89dd83fb8f04301ac254419b2d616d48f6e8bb9fbe0938745bc04ce';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  test('an extraction isolate cannot initialize a second native font-callback owner', () async {
    await expectLater(
      Isolate.run(() async => PdfRuntime.instance.open('', '')),
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

  test('opening a downloaded PDF takes its original digest from Downloads '
      'instead of hashing the file', () async {
    // Downloads hashed the file when its download completed. A digest that
    // differs from the file's own hash shows that the open did not hash it.
    final recorded = 'd' * 64;
    final document = await loadReadingDocument(
      VerifiedFile(
        File('tool/research/readers/fixtures/simple.pdf').absolute.uri,
        recorded,
      ),
      pdfSource,
    );
    addTearDown(document.dispose);
    expect(document.originalDigest, recorded);
  });

  test('a PDF place saved before t6-doxp opens at the same place', () async {
    // The place that the reader saved for simple.pdf before t6-doxp, when
    // each open hashed the file itself.
    const saved = {
      'version': 1,
      'processed':
          '39cd1ab8b3cd4b412994d1e5bfd7174075542b35c2a7866b9978d48edaf4a823',
      'original':
          '51d05de2a89dd83fb8f04301ac254419b2d616d48f6e8bb9fbe0938745bc04ce',
      'policy': 'bookfin-pdf-source-pages-1',
      'engine': 'pdfrx-0.9.0-pdfium-8125',
      'page': 2,
      'character': 12,
      'quote':
          'r 2\r\nThe river follows the old road.\r\nA reader can change the '
          'text size without changing\r\nthe saved source location.',
      'representation':
          'bookfin-pdf-source-pages-1/pdfrx-0.9.0-pdfium-8125/extracted/'
          '578cbaabc45fbdc4510f6166f42cc3a7a72654e9c4cbcff31581c7dbb88cccc4',
    };
    final pdf = await loadReadingDocument(
      verified(File('tool/research/readers/fixtures/simple.pdf').absolute),
      pdfSource,
    ) as PdfBook;
    addTearDown(pdf.dispose);
    expect(pdf.identity, saved['processed']);
    final place = pdf.restore(saved)! as PdfAddress;
    final resolved = pdf.resolveAddress(place, await pdf.text(2))!;
    expect(resolved.sourcePage, 2);
    expect(resolved.character, 12);
    expect(resolved.representation, saved['representation']);
  });

  test('a page recognized before t6-doxp and t0-0hl7 still finds its cached '
      'text', () async {
    final root = await Directory.systemTemp.createTemp('bookfin-pdf-digest-');
    addTearDown(() => root.delete(recursive: true));
    final original = File('${root.path}/complete');
    await File('tool/research/readers/fixtures/scanned.pdf')
        .copy(original.path);
    // The cache file that recognition of page 1 of scanned.pdf wrote before
    // t6-doxp, under the key that the original digest names. The code before
    // t0-0hl7, which hashed the file for the cache, wrote the same file.
    const key =
        '2463ffa5ec92806519a3759dd66fc0510d2b116eec33209727ddf72aed29af3f';
    const hocr =
        '<div class="ocr_page"><span class="ocr_line" title="bbox 10 10 500 '
        '40"><span class="ocrx_word" title="bbox 10 10 100 40">The</span> '
        '<span class="ocrx_word" title="bbox 110 10 300 40">quiet</span> '
        '<span class="ocrx_word" title="bbox 310 10 500 40">garden.</span>'
        '</span></div>';
    await Directory('${root.path}/.bookfin-ocr').create();
    await File('${root.path}/.bookfin-ocr/$key.json').writeAsString(
      jsonEncode({
        'key': key,
        'hocr': hocr,
        'sha256':
            '5b6d5021081a776932423066a6b0c95410f9a2a66dace270ee4cb8abf352b661',
      }),
    );
    var recognitions = 0;
    const channel = MethodChannel('bookfin/ocr');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'recognize') recognitions++;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final supply = BundledEnglishText();
    final scan = await loadReadingDocument(
      verified(original),
      pdfSource,
      textSupply: supply,
    ) as PdfBook;
    addTearDown(scan.dispose);
    supply.bind((read) => read(verified(original), () => true));
    expect((await scan.text(1)).text, 'The quiet garden.');
    expect(recognitions, 0);
  });

  test(
    'the first recognized page of a scanned PDF does not hash the file',
    () async {
      final root = await Directory.systemTemp.createTemp('bookfin-pdf-trust-');
      addTearDown(() => root.delete(recursive: true));
      final original = File('${root.path}/complete');
      await File('tool/research/readers/fixtures/scanned.pdf')
          .copy(original.path);
      const channel = MethodChannel('bookfin/ocr');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'recognize' ? englishPage : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final supply = BundledEnglishText();
      final scan = await loadReadingDocument(
        verified(original),
        pdfSource,
        textSupply: supply,
      ) as PdfBook;
      addTearDown(scan.dispose);
      // Downloads gives the digest of the book that it verified. The bytes
      // on disk no longer have it, so a cache that hashed the file again
      // would refuse the page.
      await original.writeAsBytes([1, 2, 3]);
      supply.bind(
        (read) =>
            read(VerifiedFile(original.uri, scan.originalDigest), () => true),
      );

      expect((await scan.text(1)).text, 'The quiet garden.');
      expect(await Directory('${root.path}/.bookfin-ocr').list().length, 1);
    },
  );

  test('an address inside an extracted page keeps the representation that '
      'saved places use', () async {
    final book = await PdfRuntime.instance.open(simple, simpleDigest);
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
      final inputs = <Object?>[];
      final outputs = <Object?>[];
      Future<R> hop<M, R>(FutureOr<R> Function(M) work, M input) async {
        inputs.add(input);
        final output = await Isolate.run(() => work(input));
        outputs.add(output);
        return output;
      }

      final book = await PdfRuntime.instance.open(
        simple,
        simpleDigest,
        hop: hop,
      );
      addTearDown(book.dispose);
      final text = await book.text(1);
      await book.text(1);
      expect(inputs, hasLength(1));
      final page =
          inputs.single!
              as ({
                String source,
                Float64List boxes,
                double width,
                double height,
              });
      expect(page.boxes, hasLength(page.source.length * 4));
      expect((page.width, page.height), (612, 792));
      expect((outputs.single! as PreparedPdfPage).text, same(text));
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
        expect((await document.render(1, 360)).width, 360);
      },
    );
  }

  test(
    'closing drains admitted page work and the shared engine can restart',
    () async {
      final books = await Future.wait([
        PdfRuntime.instance.open(simple, simpleDigest),
        PdfRuntime.instance.open(simple, simpleDigest),
      ]);
      final rendering = books.first.render(1, 360);
      final text = books.last.text(2);
      final closing = PdfRuntime.instance.shutdown();
      expect((await rendering).width, 360);
      expect((await text).text, contains('River chapter 2'));
      await closing;
      await expectLater(books.first.render(1, 360), throwsStateError);
      PdfRuntime.instance.checkInvariants();
      final reopened = await PdfRuntime.instance.open(simple, simpleDigest);
      expect((await reopened.text(1)).text, contains('River chapter 1'));
      await reopened.dispose();
    },
  );

  group('a page that the open did not measure (boo-yjq6)', () {
    /// A PDF file of pages with the [sizes] in points and the [texts], one
    /// each, written by hand.
    Future<String> pdfOf(List<(int, int)> sizes, List<String> texts) async {
      final folder = await Directory.systemTemp.createTemp('bookfin-pdf-');
      addTearDown(() => folder.delete(recursive: true));
      final count = sizes.length;
      final objects = <String>[
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Count $count /Kids '
            '[${[for (var page = 0; page < count; page++) '${4 + page * 2} 0 R'].join(' ')}] >>',
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        for (final (page, (width, height)) in sizes.indexed) ...[
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $width $height] '
              '/Resources << /Font << /F1 3 0 R >> >> '
              '/Contents ${5 + page * 2} 0 R >>',
          () {
            final drawing =
                'BT /F1 12 Tf 20 ${height - 40} Td '
                '(${texts[page]}) Tj ET';
            return '<< /Length ${drawing.length} >>\nstream\n$drawing\nendstream';
          }(),
        ],
      ];
      final output = StringBuffer('%PDF-1.4\n');
      final offsets = <int>[];
      for (final (index, object) in objects.indexed) {
        offsets.add(output.length);
        output.write('${index + 1} 0 obj\n$object\nendobj\n');
      }
      final xref = output.length;
      output.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
      for (final offset in offsets) {
        output.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
      }
      output.write(
        'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
        'startxref\n$xref\n%%EOF\n',
      );
      final file = File('${folder.path}/book.pdf');
      await file.writeAsString(output.toString());
      return file.path;
    }

    test('draws at its own size, not at the size of the first page', () async {
      final path = await pdfOf(
        [(400, 600), (600, 300), (400, 600)],
        ['First page', 'A wide plate', 'Last page'],
      );
      final book = await PdfRuntime.instance.open(path, 'a' * 64);
      addTearDown(book.dispose);

      final wide = await book.render(2, 600);

      expect((wide.width, wide.height), (600, 300));
    });

    test('keeps its own size when other pages are measured at the same '
        'time', () async {
      final path = await pdfOf(
        [(400, 600), (600, 300), (300, 600)],
        ['First page', 'A wide plate', 'A tall plate'],
      );
      final book = await PdfRuntime.instance.open(path, 'a' * 64);
      addTearDown(book.dispose);

      final [wide, tall] = await Future.wait([
        book.render(2, 600),
        book.render(3, 300),
      ]);

      expect((wide.width, wide.height), (600, 300));
      expect((tall.width, tall.height), (300, 600));
    });

    test('gives its own text, and the book counts every page', () async {
      final path = await pdfOf(
        [(400, 600), (600, 300), (400, 600)],
        ['First page', 'A wide plate', 'Last page'],
      );
      final book = await PdfRuntime.instance.open(path, 'a' * 64);
      addTearDown(book.dispose);

      expect(book.pageCount, 3);
      expect((await book.text(3)).text, 'Last page');
    });
  });
}
