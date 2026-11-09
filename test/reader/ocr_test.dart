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

// A real blank PDF keeps native rendering in the coordinator regressions.
List<int> blankPages(int count) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count $count /Kids [${List.generate(count, (i) => '${i + 3} 0 R').join(' ')}] >>',
    for (var i = 0; i < count; i++) '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << >> >>',
  ];
  final output = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(output.length);
    output.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = output.length;
  output.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    output.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  output.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return ascii.encode(output.toString());
}

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

  test('a page whose text layer is out of order is recognized without a request, and its text layer stays as it is', () async {
    await File('tool/research/readers/fixtures/columns.pdf')
        .copy('${root.path}/complete');
    final pdf = await open();
    expect((await pdf.textLayer(1)).status, PdfTextStatus.unreliable);
    expect(calls, 0);
    expect((await pdf.text(1)).text, 'The quiet garden.');
    expect(calls, 1);
    expect((await pdf.text(1)).text, 'The quiet garden.');
    reader.closeView(reader.token);
    expect((await (await open()).text(1)).text, 'The quiet garden.');
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

  test('fatal native recognition requires restart rather than another unsafe admission', () async {
    recognize = () async => throw PlatformException(code: 'recognition-fatal');
    final pdf = await open();
    final text = await pdf.text(1);
    expect(text.status, PdfTextStatus.absent);
    expect(text.reason, contains('Restart Bookfin'));
    recognize = () async => englishPage;
    expect((await pdf.text(1)).status, PdfTextStatus.absent);
    expect(calls, 1);
    expect((await pdf.render(1, 360)).width, 360);
  });

  test('chosen recognition stays consistent for this document when its cache cannot be saved', () async {
    await File('tool/research/readers/fixtures/columns.pdf')
        .copy('${root.path}/complete');
    final pdf = await open();
    expect((await pdf.textLayer(1)).status, PdfTextStatus.unreliable);
    recognize = () async {
      final key = sha256.convert(
        utf8.encode('${BundledEnglishText.version}/${pdf.originalDigest}/1'),
      );
      await Directory('${root.path}/.bookfin-ocr/$key.json')
          .create(recursive: true);
      return englishPage;
    };
    final selected = await pdf.text(1);
    expect(selected.text, 'The quiet garden.');
    recognize = () async => englishPage.replaceAll('garden', 'meadow');
    expect((await pdf.text(1)).text, selected.text);
    expect(calls, 1);
  });

  test(
    'unsaved selected text survives recognition of sixteen later pages',
    () async {
      await File('${root.path}/complete').writeAsBytes(blankPages(17));
      final pdf = await open();
      recognize = () async {
        if (calls == 1) {
          final key = sha256.convert(
            utf8.encode(
              '${BundledEnglishText.version}/${pdf.originalDigest}/1',
            ),
          );
          await Directory('${root.path}/.bookfin-ocr/$key.json')
              .create(recursive: true);
        }
        return englishPage;
      };
      // The text shows although its cache could not be saved.
      expect((await pdf.text(1)).text, 'The quiet garden.');
      for (var page = 2; page <= 17; page++) {
        expect((await pdf.text(page)).text, 'The quiet garden.');
      }
      recognize = () async => throw PlatformException(code: 'recognition');
      expect((await pdf.text(1)).text, 'The quiet garden.');
      expect(calls, 17);
      (pdf.textSupply! as BundledEnglishText).checkInvariants();
    },
  );

  test(
    'selected text stays available while two other recognition requests drain',
    () async {
      await File('${root.path}/complete').writeAsBytes(blankPages(3));
      final pdf = await open();
      expect((await pdf.text(1)).text, 'The quiet garden.');
      final held = Completer<String>();
      final started = Completer<void>();
      recognize = () {
        if (!started.isCompleted) started.complete();
        return held.future;
      };
      final second = pdf.text(2);
      await started.future;
      final third = pdf.text(3);
      try {
        expect(
          (await pdf.text(1).timeout(const Duration(seconds: 3))).text,
          'The quiet garden.',
        );
        expect(calls, 2);
      } finally {
        held.complete(englishPage);
        await Future.wait([second, third]);
      }
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
}
