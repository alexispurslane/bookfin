import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'ocr_test.dart' show englishPage;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_navigation_test.dart' show HeldPdf;
import 'pdf_session_test.dart' show book, edition;

/// A recognized page with a heading, entities, whitespace inside words, an
/// empty word, a non-BMP character and a second title property.
const lockedPage =
    '<div class="ocr_page">'
    '<span class="ocr_header" title="bbox 40 20 560 60"><span class="ocrx_word">Chapter</span> <span class="ocrx_word">Two</span></span>'
    '<span class="ocr_line" title="bbox 40 80 560 110"><span class="ocrx_word"> The </span> <span class="ocrx_word">café &amp; its</span> <span class="ocrx_word">garden—</span></span>'
    '<span class="ocr_line" title="bbox 40 120 560 150; baseline 0 -5"><span class="ocrx_word">naïve</span> <span class="ocrx_word"></span> <span class="ocrx_word">𝔅irds</span> <span class="ocrx_word">arrive.</span></span>'
    '</div>';

/// Runs [work] on [input] in a new isolate. It is top-level so that the
/// closure sent to the isolate holds only [work] and [input].
Future<R> runInWorker<M, R>(FutureOr<R> Function(M) work, M input) =>
    Isolate.run(() => work(input));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;

  // Taken from decodeRecognizedPage before it moved to a worker. Saved
  // places name recognized text by these values, so they must not change.
  test('a recognized page keeps the text and address that it had on the UI isolate', () {
    final recognized = decodeRecognizedPage(lockedPage);
    expect(
      recognized.source,
      'Chapter Two\nThe café & its garden—\nnaïve 𝔅irds arrive.',
    );
    expect(
      recognized.text,
      'Chapter Two The café & its garden— naïve 𝔅irds arrive.',
    );
    expect(recognized.sourceOffsets, List.generate(55, (index) => index));
    expect(recognized.status, PdfTextStatus.candidate);
    expect(
      recognized.digest,
      '51e849db457a34e4eebb2f3d023d154281818429a585e62f81ff4fa582b33395',
    );
    expect(
      HeldPdf().addressFor(1, recognized, 15).representation,
      'fixture/fixture/${BundledEnglishText.version}/51e849db457a34e4eebb2f3d023d154281818429a585e62f81ff4fa582b33395',
    );
  });

  group('recognized page decoding', () {
    const channel = MethodChannel('bookfin/ocr');
    late Directory root;
    late LocalFiles downloads;
    late ReaderSession reader;
    late List<Object?> inputs;
    late List<Object?> outputs;
    // While set, each hop reports that it started and waits for the gate.
    ({Completer<void> started, Completer<void> gate})? hold;
    var calls = 0;
    Future<String> Function() recognize = () async => englishPage;

    Future<R> hop<M, R>(FutureOr<R> Function(M) work, M input) async {
      inputs.add(input);
      final held = hold;
      if (held != null) {
        held.started.complete();
        await held.gate.future;
      }
      final output = await runInWorker(work, input);
      outputs.add(output);
      return output;
    }

    Future<PdfBook> open() async {
      await reader.open(book, edition);
      expect(reader.message, isNull);
      return reader.document! as PdfBook;
    }

    Future<PdfText> textWhileCanceled(PdfBook pdf) async {
      final started = Completer<void>();
      final gate = Completer<void>();
      hold = (started: started, gate: gate);
      final text = pdf.text(1);
      await started.future.timeout(const Duration(seconds: 10));
      hold = null;
      pdf.textSupply!.cancel();
      gate.complete();
      return text;
    }

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      calls = 0;
      inputs = [];
      outputs = [];
      hold = null;
      recognize = () async => englishPage;
      root = await Directory.systemTemp.createTemp('bookfin-ocr-hop-');
      final file = await File('tool/research/readers/fixtures/scanned.pdf')
          .copy('${root.path}/complete');
      downloads = LocalFiles()..files[pdfSource.key] = file.uri;
      reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: loadPublication,
        loadDocument: (file, source) => loadReadingDocument(
          file,
          source,
          textSupply: BundledEnglishText(hop: hop),
        ),
      );
      await reader.bind(account(), [book]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'recognize') {
              calls++;
              return recognize();
            }
            return null;
          });
    });

    tearDown(() async {
      hold?.gate.complete();
      reader.dispose();
      await PdfRuntime.instance.shutdown();
      downloads.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
      await root.delete(recursive: true);
    });

    test('a recognized page is decoded in one worker hop that also names its digest', () async {
      final pdf = await open();
      final text = await pdf.text(1);
      expect(inputs, [englishPage]);
      expect(outputs.single, same(text));
      expect(text.text, 'The quiet garden.');
      expect(text.digest, pdfTextDigest('The quiet garden.'));
      expect(calls, 1);
    });

    test('a cached recognized page is decoded in one worker hop', () async {
      await (await open()).text(1);
      reader.closeView(reader.token);
      inputs.clear();
      outputs.clear();
      final text = await (await open()).text(1);
      expect(inputs, [englishPage]);
      expect(outputs.single, same(text));
      expect(text.text, 'The quiet garden.');
      expect(calls, 1);
    });

    test(
      'a page canceled during its decode delivers no late recognized text',
      () async {
        final pdf = await open();
        final canceled = await textWhileCanceled(pdf);
        expect(canceled.status, PdfTextStatus.absent);
        expect(canceled.reason, contains('Recognition canceled'));
        expect((await pdf.text(1)).text, 'The quiet garden.');
        expect(
          calls,
          1,
          reason: 'The started page finished and was saved for the next visit.',
        );
      },
    );

    test(
      'a cached page canceled during its decode delivers no late text',
      () async {
        await (await open()).text(1);
        reader.closeView(reader.token);
        final pdf = await open();
        final canceled = await textWhileCanceled(pdf);
        expect(canceled.status, PdfTextStatus.absent);
        expect(canceled.reason, contains('Recognition canceled'));
        expect((await pdf.text(1)).text, 'The quiet garden.');
        expect(calls, 1);
      },
    );

    test('malformed recognition output from the worker reports a recognition failure', () async {
      recognize = () async => '<div><span class="ocr_line"><span class="ocrx_word">Text</span></span></div>';
      final text = await (await open()).text(1);
      expect(text.status, PdfTextStatus.absent);
      expect(text.reason, contains('English recognition failed'));
    });
  });
}
