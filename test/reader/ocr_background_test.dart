import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'ocr_test.dart' show blankPages, englishPage;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_session_test.dart' show book, edition;

const _otherSource = SourceFile(
  itemId: 'other-pdf',
  displayName: 'Other.pdf',
  mediaSourceId: 'original',
  revision: 'one',
  durationMs: null,
  container: 'pdf',
  sizeBytes: 1000,
);
const _otherEdition = Edition(
  id: 'other-pdf-edition',
  kind: EditionKind.text,
  label: 'PDF',
  files: [_otherSource],
  memberIds: ['other-pdf'],
);
const _otherBook = Book(
  id: 'other-work',
  title: 'Other PDF book',
  author: 'Writer',
  editions: [_otherEdition],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  const channel = MethodChannel('bookfin/ocr');
  late Directory root;
  late Directory otherRoot;
  late LocalFiles downloads;
  late ReaderSession reader;

  /// The native recognitions that the engine received, in order. The first
  /// one waits until its test completes it; later ones finish at once.
  late List<Completer<String>> native;

  /// How many times the native worker was asked to close.
  var closes = 0;

  Future<PdfBook> open([Book chosen = book, Edition selected = edition]) async {
    await reader.open(chosen, selected);
    expect(reader.message, isNull);
    return reader.document! as PdfBook;
  }

  /// The recognized pages that the cache in [directory] holds.
  Future<int> savedPages(Directory directory) async {
    final cache = Directory('${directory.path}/.bookfin-ocr');
    if (!await cache.exists()) return 0;
    return cache.list().where((entry) => entry.path.endsWith('.json')).length;
  }

  /// Waits until the cache in [directory] holds [count] recognized pages.
  Future<void> saved(int count, [Directory? directory]) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (await savedPages(directory ?? root) < count) {
      if (DateTime.now().isAfter(deadline)) {
        fail(
          'The cache holds ${await savedPages(directory ?? root)} recognized pages, not $count.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Waits until the native engine received [count] pages.
  Future<void> started(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (native.length < count) {
      if (DateTime.now().isAfter(deadline)) {
        fail('The native engine received ${native.length} pages, not $count.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// Waits until the reader of [pdf] waits for recognition.
  Future<void> waiting(PdfBook pdf) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!pdf.textSupply!.recognizing.value) {
      if (DateTime.now().isAfter(deadline)) {
        fail('The reader does not wait for recognition.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    native = [];
    closes = 0;
    root = await Directory.systemTemp.createTemp('bookfin-ocr-background-');
    otherRoot = await Directory.systemTemp.createTemp('bookfin-ocr-other-');
    final file = await File('${root.path}/complete')
        .writeAsBytes(blankPages(3));
    final other = await File('${otherRoot.path}/complete')
        .writeAsBytes(blankPages(2));
    downloads = LocalFiles()
      ..files[pdfSource.key] = file.uri
      ..files[_otherSource.key] = other.uri;
    reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: loadPublication,
      loadDocument: (uri, source) =>
          loadReadingDocument(uri, source, textSupply: BundledEnglishText()),
    );
    await reader.bind(account(), [book, _otherBook]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'close') closes++;
          if (call.method != 'recognize') return null;
          final page = Completer<String>();
          native.add(page);
          if (native.length > 1) page.complete(englishPage);
          return page.future;
        });
  });

  tearDown(() async {
    for (final page in native) {
      if (!page.isCompleted) page.complete(englishPage);
    }
    reader.dispose();
    await PdfRuntime.instance.shutdown();
    downloads.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    await root.delete(recursive: true);
    await otherRoot.delete(recursive: true);
  });

  test('canceling stops only the wait, and the started page is saved for the next visit', () async {
    final pdf = await open();
    final first = pdf.text(1);
    await started(1);

    pdf.textSupply!.cancel();

    final shown = await first.timeout(const Duration(seconds: 3));
    expect(shown.status, PdfTextStatus.absent);
    EnglishRecognition.instance.checkInvariants();
    (pdf.textSupply! as BundledEnglishText).checkInvariants();
    native.single.complete(englishPage);
    await saved(1);
    expect((await pdf.text(1)).text, 'The quiet garden.');
    expect(native, hasLength(1));
  });

  test(
    'a page turn during recognition saves the page that the reader left',
    () async {
      final pdf = await open();
      final first = pdf.text(1);
      await started(1);

      pdf.textSupply!.cancel();
      final second = pdf.text(2);
      native.first.complete(englishPage);

      expect((await first).status, PdfTextStatus.absent);
      expect((await second).text, 'The quiet garden.');
      await saved(2);
      expect((await pdf.text(1)).text, 'The quiet garden.');
      expect(native, hasLength(2));
    },
  );

  test('returning to a page that still recognizes waits for that page instead of starting it again', () async {
    final pdf = await open();
    final first = pdf.text(1);
    await started(1);
    pdf.textSupply!.cancel();

    final returned = pdf.text(1);
    native.single.complete(englishPage);

    expect((await first).status, PdfTextStatus.absent);
    expect((await returned).text, 'The quiet garden.');
    expect(native, hasLength(1));
  });

  test(
    'closing the book during recognition saves the page for the next opening',
    () async {
      final pdf = await open();
      final first = pdf.text(1);
      await started(1);

      reader.closeView(reader.token);
      native.single.complete(englishPage);

      expect((await first).status, PdfTextStatus.absent);
      await saved(1);
      expect((await (await open()).text(1)).text, 'The quiet garden.');
      expect(native, hasLength(1));
    },
  );

  test('another book opens without waiting for recognition of the book that closed', () async {
    final pdf = await open();
    unawaited(pdf.text(1));
    await started(1);

    final other = await open(
      _otherBook,
      _otherEdition,
    ).timeout(const Duration(seconds: 3));
    final otherText = other.text(1);

    native.first.complete(englishPage);
    await saved(1);
    expect((await otherText).text, 'The quiet garden.');
    await saved(1, otherRoot);
  });

  test(
    'a page keeps recognizing and is saved while the app is in the background',
    () async {
      final pdf = await open();
      final first = pdf.text(1);
      await started(1);

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
          state,
        );
      }
      await reader.flush();
      native.single.complete(englishPage);

      expect((await first).text, 'The quiet garden.');
      await saved(1);
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
    },
  );

  test(
    'the native worker stays open for the page of a closed book, then closes',
    () async {
      final pdf = await open();
      unawaited(pdf.text(1));
      await started(1);

      await open(_otherBook, _otherEdition);

      expect(closes, 0, reason: 'A running page keeps the native worker.');
      EnglishRecognition.instance.checkInvariants();
      native.single.complete(englishPage);
      await saved(1);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (closes == 0 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(closes, 1, reason: 'No open book holds the native worker.');
      EnglishRecognition.instance.checkInvariants();
    },
  );

  test(
    'quick page turns never refuse the page that the reader stops on',
    () async {
      final pdf = await open();
      unawaited(pdf.text(1));
      await started(1);

      pdf.textSupply!.cancel();
      final skipped = pdf.text(2);
      await waiting(pdf);
      pdf.textSupply!.cancel();
      final last = pdf.text(3);

      EnglishRecognition.instance.checkInvariants();
      native.first.complete(englishPage);
      expect((await skipped).status, PdfTextStatus.absent);
      expect((await last).text, 'The quiet garden.');
      expect(
        native,
        hasLength(2),
        reason:
            'The page that the reader skipped before it started is dropped.',
      );
      await saved(2);
    },
  );

  test('a page whose cache write a killed process left unfinished is recognized again and saved whole', () async {
    final pdf = await open();
    final key = sha256
        .convert(
          utf8.encode('${BundledEnglishText.version}/${pdf.originalDigest}/1'),
        )
        .toString();
    final cache = await Directory('${root.path}/.bookfin-ocr')
        .create(recursive: true);
    await File('${cache.path}/$key.json.pending')
        .writeAsString('{"key":"$key","hocr":"<div');

    final first = pdf.text(1);
    await started(1);
    native.single.complete(englishPage);

    expect((await first).text, 'The quiet garden.');
    expect(await File('${cache.path}/$key.json.pending').exists(), isFalse);
    reader.closeView(reader.token);
    expect((await (await open()).text(1)).text, 'The quiet garden.');
    expect(native, hasLength(1));
  });
}
