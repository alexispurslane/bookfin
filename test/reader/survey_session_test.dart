import 'dart:async';
import 'dart:io';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/reader/survey_files.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'ocr_hop_test.dart' show runInWorker;
import 'ocr_layout_queue_test.dart'
    show Operation, hocrOfPage, pageOfHeight, pagesOfHeights;
import 'page_geometry_test.dart' show layoutOf;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_session_test.dart' show book, edition;

const _words = [
  [100, 100, 300, 140],
  [340, 100, 420, 140],
  [460, 100, 700, 140],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  const pageCount = 8;
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
    root = await Directory.systemTemp.createTemp('bookfin-survey-session-');
    final file = await File('${root.path}/complete')
        .writeAsBytes(pagesOfHeights(pageCount));
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
      surveyStore: SurveyFiles.new,
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

  /// The pages that the engine laid out, in order.
  List<int> laidOut() => [
    for (final name in names())
      if (name.startsWith('layout ')) int.parse(name.substring(7)),
  ];

  /// Waits until the survey of [pdf] gave every page its crop.
  Future<void> surveyed(PdfBook pdf) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while ([
      for (var page = 1; page <= pageCount; page++) pdf.survey.cropOf(page),
    ].contains(null)) {
      if (DateTime.now().isAfter(deadline)) {
        fail('The survey did not finish: ${names()}.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('the survey starts at the shown page, and its layout passes wait '
      'behind the shown page\'s layout pass, its recognition and a '
      'search\'s recognition', () async {
    holding = true;
    final pdf = await open();
    await received(1);
    expect(names(), ['layout 1']);
    final search = [pdf.text(2), pdf.text(3)];
    final shownWords = pdf.geometry(4);
    final shownText = pdf.text(4);
    await queued(4);
    releaseAll();

    await Future.wait([...search, shownWords, shownText]);
    await surveyed(pdf);
    expect(names().sublist(1, 3), ['layout 4', 'recognize kept 4']);
    expect(
      names().sublist(3, 5),
      unorderedEquals(['recognize 2', 'recognize 3']),
    );
    expect(laidOut().skip(2), unorderedEquals([2, 3, 5, 6, 7, 8]));
    EnglishRecognition.instance.checkInvariants();
    pdf.survey.checkInvariants();
  });

  test('the survey follows the page that the reader shows: that page and '
      'the page after it are laid out next', () async {
    holding = true;
    await open();
    await received(1);
    reader.acceptAddress(reader.token, PdfAddress(5, 0));
    releaseAll();
    final pdf = reader.document! as PdfBook;
    await surveyed(pdf);
    expect(laidOut().take(3), [1, 5, 6]);
  });

  test('the survey\'s waiting shows no recognition progress', () async {
    holding = true;
    final pdf = await open();
    await received(1);
    expect(pdf.textSupply!.recognizing.value, isFalse);
    releaseAll();
    await surveyed(pdf);
  });

  test('the survey keeps each layout record, so the word view opens a '
      'surveyed page with no layout pass', () async {
    final pdf = await open();
    await surveyed(pdf);
    await layoutFiles(pageCount);
    final before = names().length;
    expect((await pdf.geometry(6))!.wordCount, 3);
    expect(names(), hasLength(before));
  });

  test('the survey pauses while the app is in the background, and goes on '
      'when it returns', () async {
    holding = true;
    final pdf = await open();
    await received(1);
    reader.suspend();
    releaseAll();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(names(), ['layout 1']);

    reader.resume();
    await surveyed(pdf);
    expect(laidOut()..sort(), [for (var page = 1; page <= 8; page++) page]);
  });

  test('a reopened book goes on with the survey that it kept beside the '
      'download', () async {
    holding = true;
    await open();
    await received(1);
    reader.closeView(reader.token);
    releaseAll();
    final reopened = await open();
    await surveyed(reopened);
    expect(await File('${root.path}/.bookfin-survey/survey').exists(), isTrue);
    expect(laidOut()..sort(), [for (var page = 1; page <= 8; page++) page]);
  });
}
