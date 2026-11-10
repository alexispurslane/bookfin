import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/page_geometry.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'ocr_hop_test.dart' show runInWorker;
import 'page_geometry_test.dart' show hocrOf, layoutOf;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_session_test.dart' show book, edition;

/// A PDF of [count] blank pages. Page n is 100 points wide and 100 + 10n
/// points high, so a render 1600 pixels wide names its page by its height.
List<int> pagesOfHeights(int count) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count $count /Kids [${List.generate(count, (i) => '${i + 3} 0 R').join(' ')}] >>',
    for (var i = 1; i <= count; i++)
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 ${100 + 10 * i}] /Resources << >> >>',
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

/// The page that a render [height] pixels high shows (see [pagesOfHeights]).
int pageOfHeight(int height) => (height / 16 - 100) ~/ 10;

const _words = [
  [100, 100, 300, 140],
  [340, 100, 420, 140],
  [460, 100, 700, 140],
];

/// The recognized text of page [page]: "Page [page] text."
String hocrOfPage(int page, int height) => hocrOf(1600, height, [
  [('Page', _words[0]), ('$page', _words[1]), ('text.', _words[2])],
]);

/// One native operation that the mock engine received, for the test to
/// hold or to let finish.
class Operation {
  Operation(this.name);

  /// What the engine did: 'layout 2', 'recognize 2', or 'recognize kept 2'
  /// for recognition of the page that the last layout pass kept.
  final String name;
  final release = Completer<void>();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  const channel = MethodChannel('bookfin/ocr');
  late Directory root;
  late LocalFiles downloads;
  late ReaderSession reader;
  late List<Operation> operations;
  late List<Function> hopped;

  /// Whether new operations wait until the test releases them.
  var holding = false;

  /// The page that the mock engine keeps after a layout pass, as
  /// TesseractEngine does in OcrChannel.kt.
  int? kept;

  Future<R> hop<M, R>(FutureOr<R> Function(M) work, M input) {
    hopped.add(work);
    return runInWorker(work, input);
  }

  Future<PdfBook> open() async {
    await reader.open(book, edition);
    expect(reader.message, isNull);
    return reader.document! as PdfBook;
  }

  List<String> names() => [for (final operation in operations) operation.name];

  Future<void> received(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (operations.length < count) {
      if (DateTime.now().isAfter(deadline)) {
        fail('The engine received ${names()}, not $count operations.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// Waits until [count] pieces of work wait in the queue.
  Future<void> queued(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (EnglishRecognition.instance.debugWaiting != count) {
      if (DateTime.now().isAfter(deadline)) {
        fail(
          '${EnglishRecognition.instance.debugWaiting} pieces of work wait, not $count.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// Releases every held operation, now and later.
  void releaseAll() {
    holding = false;
    for (final operation in operations) {
      if (!operation.release.isCompleted) operation.release.complete();
    }
  }

  Future<void> layoutFiles(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    Future<int> saved() async {
      final cache = Directory('${root.path}/.bookfin-ocr');
      if (!await cache.exists()) return 0;
      return cache.list().where((entry) => entry.path.endsWith('.json')).length;
    }

    while (await saved() < count) {
      if (DateTime.now().isAfter(deadline)) fail('The cache was not saved.');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    operations = [];
    hopped = [];
    holding = false;
    kept = null;
    root = await Directory.systemTemp.createTemp('bookfin-ocr-layout-');
    final file = await File('${root.path}/complete')
        .writeAsBytes(pagesOfHeights(5));
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
          if (call.method == 'close') {
            kept = null;
            return null;
          }
          final arguments = call.arguments as Map?;
          final height = arguments?['height'] as int?;
          final Operation operation;
          final int page;
          if (call.method == 'layout') {
            page = pageOfHeight(height!);
            kept = page;
            operation = Operation('layout $page');
          } else if (arguments == null) {
            final keptPage = kept;
            kept = null;
            if (keptPage == null) {
              throw PlatformException(code: 'recognition');
            }
            page = keptPage;
            operation = Operation('recognize kept $page');
          } else {
            kept = null;
            page = pageOfHeight(height!);
            operation = Operation('recognize $page');
          }
          operations.add(operation);
          if (!holding) operation.release.complete();
          await operation.release.future;
          if (call.method == 'layout') {
            return layoutOf(1600, height!, [_words]);
          }
          return hocrOfPage(page, 1600 * (100 + 10 * page) ~/ 100);
        });
  });

  tearDown(() async {
    releaseAll();
    reader.dispose();
    await PdfRuntime.instance.shutdown();
    downloads.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    await root.delete(recursive: true);
  });

  test('a scanned page\'s words are ready before its text', () async {
    final pdf = await open();
    holding = true;
    final geometry = pdf.geometry(1);
    await received(1);
    final text = pdf.text(1);
    await queued(1);
    operations.single.release.complete();

    final words = await geometry.timeout(const Duration(seconds: 10));
    expect(words!.wordCount, 3);
    await received(2);
    expect(names(), ['layout 1', 'recognize kept 1']);
    var arrived = false;
    unawaited(text.then((_) => arrived = true));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(arrived, isFalse);
    releaseAll();
    expect((await text).text, 'Page 1 text.');
  });

  test(
    'a saved layout record opens the page\'s words with no layout pass',
    () async {
      final first = await (await open()).geometry(1);
      expect(names(), ['layout 1']);
      await layoutFiles(1);
      reader.closeView(reader.token);

      final again = await (await open()).geometry(1);
      expect(names(), ['layout 1']);
      expect(again!.boxes, first!.boxes);
      expect(again.lineStarts, first.lineStarts);
    },
  );

  test(
    'a damaged layout record is laid out again rather than trusted',
    () async {
      await (await open()).geometry(1);
      await layoutFiles(1);
      reader.closeView(reader.token);
      final record = (await Directory(
        '${root.path}/.bookfin-ocr',
      ).list().toList()).whereType<File>().single;
      await record.writeAsString('{"broken":true}');

      expect((await (await open()).geometry(1))!.wordCount, 3);
      expect(names(), ['layout 1', 'layout 1']);
    },
  );

  test('a page recognized before word geometry gets one layout pass on its '
      'first visit, and its text is not recognized again', () async {
    final pdf = await open();
    expect((await pdf.text(1)).text, 'Page 1 text.');
    expect((await pdf.geometry(1))!.wordCount, 3);
    expect((await pdf.text(1)).text, 'Page 1 text.');
    await layoutFiles(2);
    reader.closeView(reader.token);
    final reopened = await open();
    expect((await reopened.geometry(1))!.wordCount, 3);
    expect((await reopened.text(1)).text, 'Page 1 text.');
    expect(names(), ['recognize 1', 'layout 1']);
  });

  test('the shown page\'s layout pass and then its recognition run before '
      'other waiting recognition', () async {
    final pdf = await open();
    holding = true;
    final pages = [pdf.text(1), pdf.text(2), pdf.text(3)];
    await received(1);
    await queued(2);
    final shownWords = pdf.geometry(4);
    final shownText = pdf.text(4);
    await queued(4);
    releaseAll();

    expect((await shownWords)!.wordCount, 3);
    expect((await shownText).text, 'Page 4 text.');
    for (final (index, page) in pages.indexed) {
      expect((await page).text, 'Page ${index + 1} text.');
    }
    // The pages of the search reach the queue in any order; the shown
    // page's work comes right after the page that ran.
    expect(names().sublist(1, 3), ['layout 4', 'recognize kept 4']);
    expect([
      names().first,
      ...names().sublist(3),
    ], unorderedEquals(['recognize 1', 'recognize 2', 'recognize 3']));
    EnglishRecognition.instance.checkInvariants();
    (pdf.textSupply! as BundledEnglishText).checkInvariants();
  });

  test('the shown page\'s recognition follows its layout pass even when its '
      'text was asked for first', () async {
    final pdf = await open();
    holding = true;
    final pages = [pdf.text(1), pdf.text(2)];
    await received(1);
    await queued(1);
    final shownText = pdf.text(3);
    final shownWords = pdf.geometry(3);
    await queued(3);
    releaseAll();

    await Future.wait([...pages, shownText, shownWords]);
    expect(names().sublist(1, 3), ['layout 3', 'recognize kept 3']);
    expect([
      names().first,
      ...names().sublist(3),
    ], unorderedEquals(['recognize 1', 'recognize 2']));
  });

  test('a page\'s recognition never reads the image that another page\'s '
      'layout pass kept', () async {
    final pdf = await open();
    holding = true;
    final firstWords = pdf.geometry(1);
    await received(1);
    final firstText = pdf.text(1);
    await queued(1);
    // The person turns to page 2 while page 1's layout pass runs; search
    // still waits for page 1's text.
    final secondWords = pdf.geometry(2);
    await queued(2);
    releaseAll();

    expect((await firstWords)!.wordCount, 3);
    expect((await secondWords)!.wordCount, 3);
    expect((await firstText).text, 'Page 1 text.');
    expect(names(), ['layout 1', 'layout 2', 'recognize 1']);
  });

  test('after the native worker closes, recognition of a page laid out '
      'before sends that page again', () async {
    final pdf = await open();
    await pdf.geometry(1);
    reader.closeView(reader.token);
    // Nothing waits or holds the worker, so it closed and freed its image.
    expect((await (await open()).text(1)).text, 'Page 1 text.');
    expect(names(), ['layout 1', 'recognize 1']);
  });

  test('a failed layout pass gives no words, and the page\'s text is still '
      'recognized from its own image', () async {
    final pdf = await open();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'close') {
            kept = null;
            return null;
          }
          final arguments = call.arguments as Map?;
          if (call.method == 'layout') {
            operations.add(Operation('layout failed'));
            kept = null;
            throw PlatformException(code: 'recognition');
          }
          if (arguments == null) {
            operations.add(Operation('recognize kept'));
            throw PlatformException(code: 'recognition');
          }
          final page = pageOfHeight(arguments['height'] as int);
          operations.add(Operation('recognize $page'));
          return hocrOfPage(page, arguments['height'] as int);
        });
    final words = pdf.geometry(1);
    await received(1);
    final text = pdf.text(1);
    expect(await words, isNull);
    expect((await text).text, 'Page 1 text.');
    expect(names(), ['layout failed', 'recognize 1']);
  });

  test('a reader that stops waiting for the words leaves the layout pass '
      'that has not started', () async {
    final pdf = await open();
    holding = true;
    final first = pdf.text(1);
    await received(1);
    final words = pdf.geometry(2);
    // The layout pass of page 2 reaches the queue behind the running page.
    await queued(1);
    pdf.textSupply!.cancel();
    releaseAll();
    expect((await first).status, PdfTextStatus.failed);
    expect(await words, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(names(), ['recognize 1']);
    EnglishRecognition.instance.checkInvariants();
  });

  test('the recognized text attaches to the page\'s words, and decoding and '
      'attachment run in a hop', () async {
    final pdf = await open();
    final geometry = (await pdf.geometry(1))!;
    final attached = await pdf.attachedText(1, geometry);

    expect(attached.text.text, 'Page 1 text.');
    final attachment = attached.attachment!;
    expect(
      [
        for (var word = 0; word < geometry.wordCount; word++)
          attached.text.source.substring(
            attachment[word * 2],
            attachment[word * 2 + 1],
          ),
      ],
      ['Page', '1', 'text.'],
    );
    geometry.checkInvariants(
      attachment: attachment,
      source: attached.text.source,
    );
    expect(hopped, containsAll(<Function>[pageGeometryFromLayout, attachText]));
    expect(hopped, contains(decodeRecognizedPage));
  });

  test(
    'a page whose text layer is usable gets no words from the layout pass',
    () async {
      // A text layer page gets its words from its character boxes (W2).
      final pdf = await open();
      final layer = PdfText(
        source: 'Text',
        text: 'Text',
        sourceOffsets: const [0, 1, 2, 3],
        status: PdfTextStatus.candidate,
        digest: pdfTextDigest('Text'),
      );
      expect(await pdf.textSupply!.geometry(pdf, 1, layer), isNull);
      expect(operations, isEmpty);
      expect(Uint8List(0), isEmpty);
    },
  );
}
