import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_text_view.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pdf_viewport_host.dart';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../playback/playback_test.dart' show account, LocalFiles;
import 'ocr_test.dart' show englishPage;
import 'ocr_quality_test.dart' show line;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_session_test.dart' show book, edition;

Uint8List twoPageScan() {
  final output = BytesBuilder();
  final offsets = <int>[0];
  void text(String value) => output.add(ascii.encode(value));
  void object(int number, String value) {
    offsets.add(output.length);
    text('$number 0 obj\n$value\nendobj\n');
  }

  text('%PDF-1.4\n');
  object(1, '<< /Type /Catalog /Pages 2 0 R >>');
  object(2, '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>');
  for (final page in [3, 4]) {
    object(
      page,
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Resources << >> /Contents 5 0 R >>',
    );
  }
  const drawing = '0.8 g 10 10 280 380 re f';
  object(5, '<< /Length ${drawing.length} >>\nstream\n$drawing\nendstream');
  final xref = output.length;
  text('xref\n0 6\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    text('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  text('trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return output.takeBytes();
}

Future<Result?> native<Result>(
  WidgetTester tester,
  Future<Result> Function() action,
) async {
  var settled = false;
  Result? value;
  Object? failure;
  StackTrace? trace;
  await tester.runAsync(() async {
    action().then(
      (result) {
        value = result;
        settled = true;
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
        trace = stack;
        settled = true;
      },
    );
  });
  for (var attempt = 0; !settled && attempt < 500; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  if (!settled) fail('Native document work did not settle.');
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  return value;
}

void main() {
  final reflowed = find.descendant(
    of: find.byType(PdfViewport),
    matching: find.byType(PdfTextView),
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  const channel = MethodChannel('bookfin/ocr');
  late Directory root;
  late LocalFiles downloads;
  late LocalResumeStore store;
  late RecordDatabase database;
  late ReaderSession reader;
  late DocumentNavigator navigation;
  var placeReported = false;
  var calls = 0;
  Future<String> Function() recognize = () async => englishPage;

  ReaderSession session() => ReaderSession(
    downloads: downloads,
    store: store.reading,
    load: loadPublication,
    loadDocument: (file, source) =>
        loadReadingDocument(file, source, textSupply: BundledEnglishText()),
  );

  /// Shows the open book in a viewport, in reflow with [reflow].
  Future<void> showReader(WidgetTester tester, {bool reflow = false}) async {
    placeReported = false;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await native(tester, () => reader.flush());
      await native(tester, () => PdfRuntime.instance.shutdown());
    });
    final token = reader.token;
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfViewportHost(
              book: reader.document! as PdfBook,
              fontSize: 20,
              reflow: reflow,
              initial: reader.initialAddress as PdfAddress?,
              onReady: (value, entries) {
                navigation = value;
                reader.attachDocument(token, value, entries);
              },
              onAddress: (value) {
                placeReported = true;
                reader.acceptAddress(token, value);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> drawOriginal(WidgetTester tester, int page) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (find
          .bySemanticsLabel('Original source page $page')
          .evaluate()
          .isNotEmpty) {
        return;
      }
    }
    expect(find.bySemanticsLabel('Original source page $page'), findsOneWidget);
  }

  /// Waits until [finder] finds what the viewport shows. Reflow asks for
  /// the page's text for reading, which arrives after a few frames.
  Future<void> shows(WidgetTester tester, Finder finder) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      if (finder.evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(finder, findsOneWidget);
  }

  /// Waits until the shown viewport is done with its page text. The
  /// viewport reports a place only once its page text arrived, failed or
  /// stopped being awaited.
  Future<void> finishText(WidgetTester tester) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (placeReported) return;
    }
    fail('The current source-page text must settle.');
  }

  Future<void> restart(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await native(tester, () async {
      await reader.flush();
      reader.dispose();
      await PdfRuntime.instance.shutdown();
      await database.close();
      database = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: '${root.path}/records.sqlite',
      );
      store = LocalResumeStore(openDatabase: () async => database);
      reader = session();
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      expect(reader.message, isNull);
    });
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookfin-ocr-position-');
    final original = await File('${root.path}/complete')
        .writeAsBytes(twoPageScan());
    downloads = LocalFiles()..files[pdfSource.key] = original.uri;
    SharedPreferences.setMockInitialValues({});
    database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: '${root.path}/records.sqlite',
    );
    store = LocalResumeStore(openDatabase: () async => database);
    reader = session();
    calls = 0;
    recognize = () async => englishPage;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'recognize') return null;
          calls++;
          return recognize();
        });
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
  });

  tearDown(() async {
    reader.dispose();
    await PdfRuntime.instance.shutdown();
    await database.close();
    downloads.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  test('the document separates extracted, recognized and changed-model character meanings even for identical words', () async {
    final pdf = reader.document! as PdfBook;
    final recognized = decodeRecognizedPage(englishPage).text;
    final extracted = PdfText(
      source: recognized.source,
      text: recognized.text,
      sourceOffsets: recognized.sourceOffsets,
      status: PdfTextStatus.candidate,
      digest: recognized.digest,
    );
    final extractedAddress = pdf.addressFor(2, extracted, 10);
    final recognizedAddress = pdf.addressFor(2, recognized, 10);
    expect(pdf.resolveAddress(extractedAddress, recognized), isNull);
    expect(pdf.resolveAddress(recognizedAddress, extracted), isNull);
    final differentModel = PdfText(
      source: recognized.source,
      text: recognized.text,
      sourceOffsets: recognized.sourceOffsets,
      status: recognized.status,
      recognition: 'previous-model',
      digest: recognized.digest,
    );
    expect(pdf.resolveAddress(recognizedAddress, differentModel), isNull);
    expect(pdf.resolveAddress(recognizedAddress, recognized)!.character, 10);
    expect(pdf.resolveAddress(PdfAddress(2, 10), recognized), isNull);
    expect(pdf.resolveAddress(PdfAddress(2, 0), recognized)!.character, 0);
    expect(pdf.restore(pdf.save(recognizedAddress))!.resource, 'page:2');
    final changedOriginal = pdf.save(recognizedAddress)
      ..['original'] = 'different-source';
    expect(pdf.restore(changedOriginal), isNull);
  });

  testWidgets(
    'matching recognized coordinates restore nonzero reflow positions after SQLite restart',
    (tester) async {
      recognize = () async =>
          '<div>${List.generate(70, (index) => line('The quiet garden follows the long river number $index.', 10, index * 40 + 10, 600, index * 40 + 30)).join()}</div>';
      await showReader(tester);
      await finishText(tester);
      final report = (await native(
        tester,
        () => navigation.search('garden', 30),
      ))!;
      final hit = report.hits.last.address as PdfAddress;
      expect(hit.sourcePage, 2);
      expect(hit.character, greaterThan(1000));
      await native(tester, () => navigation.display(hit));
      await tester.tap(find.byTooltip('Reflow text'));
      await shows(tester, reflowed);
      await tester.pump();
      expect(
        (reader.visibleAddress as PdfAddress).character,
        greaterThan(1000),
      );
      await restart(tester);
      expect(
        (reader.initialAddress as PdfAddress).character,
        greaterThan(1000),
      );
      await showReader(tester);
      await finishText(tester);
      await tester.tap(find.byTooltip('Reflow text'));
      await shows(tester, reflowed);
      await tester.pump();
      final screen = tester.widget<PdfTextView>(reflowed);
      expect(screen.screen, greaterThan(0));
      expect((reader.visibleAddress as PdfAddress).sourcePage, 2);
      expect(
        (reader.visibleAddress as PdfAddress).character,
        greaterThan(1000),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'recognition of an out-of-order text layer stays selected for actual search and revisit',
    (tester) async {
      await native(tester, () async {
        reader.closeView(reader.token);
        await PdfRuntime.instance.shutdown();
        await File('tool/research/readers/fixtures/columns.pdf')
            .copy('${root.path}/complete');
        await reader.open(book, edition);
        final pdf = reader.document! as PdfBook;
        expect((await pdf.textLayer(1)).status, PdfTextStatus.unreliable);
        expect((await pdf.text(1)).text, 'The quiet garden.');
      });
      await showReader(tester);
      await finishText(tester);
      final report = (await native(
        tester,
        () => navigation.search('garden', 1),
      ))!;
      expect(report.error, isNull);
      expect(report.hits, hasLength(1));
      await native(
        tester,
        () => navigation.display(report.hits.single.address),
      );
      await tester.pump();
      expect((reader.visibleAddress! as PdfAddress).character, 10);
      await restart(tester);
      await showReader(tester);
      await finishText(tester);
      expect(
        (await native(tester, () => navigation.search('garden', 2)))!.hits,
        hasLength(1),
      );
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a fatal native worker offers the original page and restart, not recognition retry',
    (tester) async {
      recognize = () async =>
          throw PlatformException(code: 'recognition-fatal');
      await showReader(tester);
      await finishText(tester);
      await drawOriginal(tester, 1);
      await tester.tap(find.byTooltip('Reflow text'));
      await shows(tester, find.textContaining('Restart Bookfin'));
      expect(find.text('Retry recognition'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final cacheState in ['missing', 'corrupt']) {
    for (final failure in ['empty', 'exception', 'cancel']) {
      testWidgets(
        'page-two recognized resume survives $cacheState cache and $failure through SQLite restart',
        (tester) async {
          await showReader(tester);
          await finishText(tester);
          final report = (await native(
            tester,
            () => navigation.search('garden', 10),
          ))!;
          final hit = report.hits.last.address as PdfAddress;
          expect(hit.sourcePage, 2);
          expect(hit.character, 10);
          reader.acceptAddress(reader.token, hit);
          await native(tester, () async {
            await reader.addBookmark(title: 'Recognized page two');
            await reader.flush();
            for (final cache in await Directory(
              '${root.path}/.bookfin-ocr',
            ).list().toList()) {
              if (cache is File) {
                if (cacheState == 'missing') {
                  await cache.delete();
                } else {
                  await cache.writeAsString('{"broken":true}');
                }
              }
            }
          });
          final started = Completer<void>();
          final held = Completer<String>();
          recognize = () async {
            if (!started.isCompleted) started.complete();
            if (failure == 'cancel') return held.future;
            if (failure == 'exception') {
              throw PlatformException(code: 'recognition');
            }
            return '<div/>';
          };
          await restart(tester);
          expect((reader.initialAddress as PdfAddress).character, 10);
          // Only reflow recognizes a page.
          await showReader(tester, reflow: true);
          await drawOriginal(tester, 2);
          await native(
            tester,
            () => started.future.timeout(const Duration(seconds: 5)),
          );
          if (failure == 'cancel') {
            await tester.tap(find.byTooltip('Original page'));
            await tester.pump();
            held.complete(englishPage);
          }
          await finishText(tester);
          await native(tester, () => reader.flush());
          expect((reader.visibleAddress as PdfAddress).toJson(), hit.toJson());
          await restart(tester);
          expect((reader.initialAddress as PdfAddress).toJson(), hit.toJson());
          expect(
            reader.document!
                .restore(
                  jsonDecode(reader.bookmarks.single.position.anchor)
                      as Map<String, dynamic>,
                )!
                .toJson(),
            hit.toJson(),
          );
          await showReader(tester);
          await drawOriginal(tester, 2);
          await native(tester, () => navigation.contents('page:1'));
          await tester.pump();
          expect((reader.visibleAddress as PdfAddress).sourcePage, 1);
          expect((reader.visibleAddress as PdfAddress).character, 0);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  for (final change in ['text', 'model', 'policy', 'legacy']) {
    testWidgets(
      '$change changes keep page two without applying an incompatible recognized character',
      (tester) async {
        await showReader(tester);
        await finishText(tester);
        final report = (await native(
          tester,
          () => navigation.search('garden', 20),
        ))!;
        final pdf = reader.document! as PdfBook;
        final hit = report.hits.last.address as PdfAddress;
        final anchor = pdf.save(hit);
        final representation =
            anchor['representation'] as String? ??
            'ocr/${BundledEnglishText.version}';
        if (change == 'model') {
          anchor['representation'] = representation.replaceFirst(
            BundledEnglishText.version,
            'previous-model',
          );
        } else if (change == 'policy') {
          anchor['policy'] = 'previous-text-policy';
          anchor['representation'] = 'previous-text-policy/$representation';
        } else if (change == 'legacy') {
          anchor.remove('representation');
        }
        final restored = pdf.restore(anchor);
        expect(restored, isA<PdfAddress>());
        reader.acceptAddress(reader.token, restored!);
        if (change == 'text') {
          await native(tester, () async {
            for (final cache in await Directory(
              '${root.path}/.bookfin-ocr',
            ).list().toList()) {
              if (cache is File) await cache.delete();
            }
          });
          recognize = () async => englishPage.replaceAll('quiet', 'noisy');
        }
        await restart(tester);
        expect((reader.initialAddress as PdfAddress).sourcePage, 2);
        expect((reader.initialAddress as PdfAddress).character, 10);
        await showReader(tester);
        await finishText(tester);
        await tester.tap(find.byTooltip('Reflow text'));
        await tester.pump();
        await drawOriginal(tester, 2);
        expect(reflowed, findsNothing);
        expect((reader.visibleAddress as PdfAddress).character, 10);
        await native(tester, () => navigation.contents('page:2'));
        await tester.pump();
        expect((reader.visibleAddress as PdfAddress).character, 0);
        expect(reflowed, findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
