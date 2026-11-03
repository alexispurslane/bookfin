import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_session_test.dart' show book, edition;

const englishPage =
    '''<div class="ocr_page"><span class="ocr_line" title="bbox 10 10 500 40"><span class="ocrx_word" title="bbox 10 10 100 40">The</span> <span class="ocrx_word" title="bbox 110 10 300 40">quiet</span> <span class="ocrx_word" title="bbox 310 10 500 40">garden.</span></span></div>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  const channel = MethodChannel('bookfin/ocr');
  late Directory root;
  late LocalFiles downloads;
  late ReaderSession reader;
  var calls = 0;
  Future<String> Function() recognize = () async => englishPage;

  Future<PdfBook> open() async {
    await reader.open(book, edition);
    expect(reader.message, isNull);
    return reader.document! as PdfBook;
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls = 0;
    recognize = () async => englishPage;
    root = await Directory.systemTemp.createTemp('bookfin-ocr-');
    final file = await File('tool/research/readers/fixtures/scanned.pdf')
        .copy('${root.path}/complete');
    downloads = LocalFiles()..files[pdfSource.key] = file.uri;
    reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: loadPublication,
      loadDocument: (uri, source) =>
          loadReadingDocument(uri, source, textSupply: BundledEnglishText()),
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
    reader.dispose();
    await PdfRuntime.instance.shutdown();
    downloads.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    await root.delete(recursive: true);
  });

  test(
    'recognized page text keeps the existing PDF identity and source address',
    () async {
      final pdf = await open();
      final identity = pdf.identity;
      final text = await pdf.text(1);
      expect(text.status, PdfTextStatus.candidate);
      expect(text.text, 'The quiet garden.');
      expect(text.sourceOffsets, hasLength(text.text.length));
      final address = PdfAddress(
        1,
        text.sourceOffsets[text.text.indexOf('garden')],
      );
      expect(pdf.restore(pdf.save(address))!.toJson(), address.toJson());
      expect(pdf.identity, identity);
      expect((await pdf.render(1, 360)).width, 360);
      expect(calls, 1);
    },
  );

  test('unreliable extracted text keeps its fallback until English recognition is requested', () async {
    await File('tool/research/readers/fixtures/columns.pdf')
        .copy('${root.path}/complete');
    final pdf = await open();
    expect((await pdf.text(1)).status, PdfTextStatus.unreliable);
    expect(calls, 0);
    pdf.textSupply!.retry(1);
    expect((await pdf.text(1)).text, 'The quiet garden.');
    expect(calls, 1);
  });

  test('corrupt cached text is recognized again rather than trusted or made permanent', () async {
    await (await open()).text(1);
    final cache = (await Directory(
      '${root.path}/.bookfin-ocr',
    ).list().toList()).whereType<File>().single;
    await cache.writeAsString('{"broken":true}');
    reader.closeView(reader.token);
    expect((await (await open()).text(1)).text, 'The quiet garden.');
    expect(calls, 2);
  });

  test(
    'changed source bytes cannot reuse recognition from the previous PDF',
    () async {
      await (await open()).text(1);
      reader.closeView(reader.token);
      final file = File('${root.path}/complete');
      await file.writeAsBytes([...await file.readAsBytes(), 10]);
      expect((await (await open()).text(1)).text, 'The quiet garden.');
      expect(calls, 2);
    },
  );

  test(
    'a cache record from a different engine and model version is not reused',
    () async {
      final pdf = await open();
      await pdf.text(1);
      reader.closeView(reader.token);
      final cache = (await Directory(
        '${root.path}/.bookfin-ocr',
      ).list().toList()).whereType<File>().single;
      final previousKey = sha256
          .convert(
            utf8.encode(
              'previous-engine/previous-model/${pdf.originalDigest}/1',
            ),
          )
          .toString();
      final record =
          jsonDecode(await cache.readAsString()) as Map<String, dynamic>;
      record['key'] = previousKey;
      await cache.writeAsString(jsonEncode(record));
      await cache.rename('${cache.parent.path}/$previousKey.json');
      expect((await (await open()).text(1)).text, 'The quiet garden.');
      expect(calls, 2);
    },
  );

  test(
    'reopening uses verified cached text without running the engine again',
    () async {
      expect((await (await open()).text(1)).text, 'The quiet garden.');
      reader.closeView(reader.token);
      expect((await (await open()).text(1)).text, 'The quiet garden.');
      expect(calls, 1);
    },
  );

  test(
    'recognition failure keeps the original and the next request retries',
    () async {
      recognize = () async => throw PlatformException(code: 'recognition');
      final pdf = await open();
      expect((await pdf.text(1)).status, PdfTextStatus.absent);
      expect((await pdf.render(1, 360)).width, 360);
      recognize = () async => englishPage;
      expect((await pdf.text(1)).text, 'The quiet garden.');
      expect(calls, 2);
    },
  );

  test('a recognition-close failure is reported without retaining the PDF native owner', () async {
    final pdf = await open();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'close') throw PlatformException(code: 'close');
          return englishPage;
        });
    await expectLater(pdf.dispose(), throwsA(isA<PlatformException>()));
    await expectLater(PdfRuntime.instance.shutdown(), completes);
  });

  test('retry during cancellation waits for the native page then recognizes a fresh request', () async {
    final held = Completer<String>();
    final started = Completer<void>();
    recognize = () {
      started.complete();
      return held.future;
    };
    final pdf = await open();
    final first = pdf.text(1);
    await started.future;
    pdf.textSupply!.cancel();
    recognize = () async => englishPage;
    final retry = pdf.text(1);
    held.complete(englishPage);
    expect((await first).status, PdfTextStatus.absent);
    expect((await retry).text, 'The quiet garden.');
    expect(calls, 2);
  });

  test(
    'leaving rejects a late native result and reopening recognizes again',
    () async {
      final held = Completer<String>();
      final started = Completer<void>();
      recognize = () {
        started.complete();
        return held.future;
      };
      final pdf = await open();
      final pending = pdf.text(1);
      await started.future.timeout(const Duration(seconds: 5));
      reader.closeView(reader.token);
      held.complete(englishPage);
      expect((await pending).status, PdfTextStatus.absent);
      recognize = () async => englishPage;
      expect((await (await open()).text(1)).text, 'The quiet garden.');
      expect(calls, 2);
    },
  );
}
