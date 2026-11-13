import 'dart:async';
import 'dart:io';

import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'book_survey_test.dart' show UnreadSurvey, until;
import 'ocr_hop_test.dart' show runInWorker;
import 'pdf_document_test.dart' show simple, simpleDigest, pdfSource;
import 'pdf_navigation_test.dart' show HeldPdf;
import 'pdf_session_test.dart' show book, edition;

// Observe native release without replacing PDFium's document or page work.
class TrackedDocument implements native.PdfDocument {
  TrackedDocument(this.document);
  final native.PdfDocument document;
  var releases = 0;
  Object? failure;
  StackTrace? failureStack;
  @override
  bool get isEncrypted => document.isEncrypted;
  @override
  List<native.PdfPage> get pages => document.pages;
  @override
  Future<void> reloadPages({List<int>? pageNumbersToReload}) =>
      document.reloadPages(pageNumbersToReload: pageNumbersToReload);
  @override
  Future<void> dispose() async {
    releases++;
    await document.dispose();
    if (failure case final error?) {
      Error.throwWithStackTrace(error, failureStack ?? StackTrace.current);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TrackedEngine implements native.PdfrxEntryFunctions {
  TrackedEngine(this.engine);
  final native.PdfrxEntryFunctions engine;
  final documents = <TrackedDocument>[];
  @override
  Future<native.PdfDocument> openFile(
    String path, {
    native.PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async {
    final document = TrackedDocument(
      await engine.openFile(
        path,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        useProgressiveLoading: useProgressiveLoading,
      ),
    );
    documents.add(document);
    return document;
  }

  @override
  Future<void> stopBackgroundWorker() => engine.stopBackgroundWorker();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class HeldSupply implements PdfTextSupply {
  final closing = Completer<void>();
  final closed = Completer<void>();
  var cancels = 0;
  var releases = 0;
  Object? cancelFailure;
  @override
  void cancel() {
    cancels++;
    if (cancelFailure case final error?) throw error;
  }

  @override
  void bind(PdfTextLease lease) {}
  @override
  Future<void> close() async {
    releases++;
    closing.complete();
    await closed.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FailedSurveyBook extends HeldPdf {
  final started = Completer<void>();
  final result = Completer<ReflowPage?>();
  var attempts = 0;
  @override
  Future<ReflowPage?> reflowPage(int sourcePage, {bool background = false}) {
    attempts++;
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  native.Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  native.Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  final runtime = PdfRuntime.instance;
  late native.PdfrxEntryFunctions engine;
  late TrackedEngine tracked;
  late FlutterExceptionHandler? previousHandler;
  late List<FlutterErrorDetails> reports;

  setUp(() async {
    // Flutter initializes PDFium and fonts before we observe document release.
    final warm = await runtime.open(simple, simpleDigest);
    await warm.dispose();
    engine = native.PdfrxEntryFunctions.instance;
    tracked = TrackedEngine(engine);
    native.PdfrxEntryFunctions.instance = tracked;
    previousHandler = FlutterError.onError;
    reports = [];
    FlutterError.onError = reports.add;
  });
  tearDown(() async {
    FlutterError.onError = previousHandler;
    try {
      await runtime.shutdown();
    } finally {
      native.PdfrxEntryFunctions.instance = engine;
    }
  });

  test(
    'a survey Error still closes the text supply and releases PDFium once',
    () async {
      final started = Completer<void>();
      final gate = Completer<void>();
      final failure = AssertionError('survey contract');
      final stack = StackTrace.current;
      Future<R> hop<M, R>(FutureOr<R> Function(M) work, M input) async {
        if (!started.isCompleted) started.complete();
        await gate.future;
        return runInWorker(work, input);
      }

      final supply = HeldSupply()..closed.complete();
      final pdf = await runtime.open(
        simple,
        simpleDigest,
        textSupply: supply,
        hop: hop,
      );
      final store = UnreadSurvey()..reading.complete(null);
      pdf.survey.start(store, from: 1);
      await started.future;
      final closing = pdf.dispose();
      final checked = expectLater(closing, throwsA(same(failure)));
      expect(identical(closing, pdf.dispose()), isTrue);
      gate.completeError(failure, stack);
      await checked;
      expect(supply.releases, 1);
      expect(supply.cancels, 1);
      expect(tracked.documents.single.releases, 1);
      await expectLater(pdf.dispose(), throwsA(same(failure)));
      runtime.checkInvariants();
      // Shutdown must no longer see the failed book as an owned document.
      await runtime.shutdown();
      expect(tracked.documents.single.releases, 1);
    },
  );

  test(
    'close drains failing page work before text supply and native release',
    () async {
      final started = Completer<void>();
      final gate = Completer<void>();
      final failure = AssertionError('text preparation');
      Future<R> hop<M, R>(FutureOr<R> Function(M) work, M input) async {
        started.complete();
        await gate.future;
        return runInWorker(work, input);
      }

      final supply = HeldSupply();
      final pdf = await runtime.open(
        simple,
        simpleDigest,
        textSupply: supply,
        hop: hop,
      );
      final reading = expectLater(pdf.text(1), throwsA(same(failure)));
      await started.future;
      final closing = pdf.dispose();
      expect(supply.releases, 0);
      expect(tracked.documents.single.releases, 0);
      await expectLater(pdf.text(2), throwsStateError);
      gate.completeError(failure);
      await reading;
      await supply.closing.future;
      expect(tracked.documents.single.releases, 0);
      supply.closed.complete();
      await closing;
      expect(tracked.documents.single.releases, 1);
      await pdf.dispose();
      expect(supply.releases, 1);
      expect(supply.cancels, 1);
    },
  );

  test(
    'closing during survey page work treats the closed book as cancellation',
    () async {
      final started = Completer<void>();
      final gate = Completer<void>();
      Future<R> hop<M, R>(FutureOr<R> Function(M) work, M input) async {
        if (!started.isCompleted) started.complete();
        await gate.future;
        return runInWorker(work, input);
      }

      final pdf = await runtime.open(simple, simpleDigest, hop: hop);
      pdf.survey.start(UnreadSurvey()..reading.complete(null), from: 1);
      await started.future;
      final closing = pdf.dispose();
      gate.complete();
      await closing;
      expect(reports, isEmpty);
      expect(tracked.documents.single.releases, 1);
    },
  );

  test(
    'cleanup retains the first failure when text supply and PDFium both fail',
    () async {
      final supply = HeldSupply();
      final pdf = await runtime.open(simple, simpleDigest, textSupply: supply);
      final failure = AssertionError('text supply close');
      final stack = StackTrace.current;
      tracked.documents.single.failure = StateError('native release');
      final closing = pdf.dispose();
      final checked = closing.then<void>(
        (_) => fail('Close must fail.'),
        onError: (Object error, StackTrace seen) {
          expect(error, same(failure));
          expect(seen, same(stack));
        },
      );
      await supply.closing.future;
      supply.closed.completeError(failure, stack);
      await checked;
      expect(tracked.documents.single.releases, 1);
      await runtime.shutdown();
      runtime.checkInvariants();
    },
  );

  for (final failure in [
    AssertionError('survey invariant'),
    StateError('survey state'),
  ]) {
    test(
      'a completed survey ${failure.runtimeType} stays failed through follow resume and close',
      () async {
        final pdf = FailedSurveyBook();
        final store = UnreadSurvey()..reading.complete(null);
        pdf.survey.start(store, from: 1);
        await pdf.started.future;
        pdf.result.completeError(failure);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        pdf.survey.follow(2);
        pdf.survey.pause();
        pdf.survey.resume();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(pdf.attempts, 1);
        await expectLater(pdf.survey.close(), throwsA(same(failure)));
        await expectLater(pdf.survey.close(), throwsA(same(failure)));
        expect(reports.single.exception, same(failure));
        pdf.survey.checkInvariants();
      },
    );
  }

  for (final failure in [AssertionError('PDF close'), Exception('PDF close')]) {
    test(
      'a reported close ${failure.runtimeType} does not block later open and close',
      () async {
        final downloads = LocalFiles()
          ..files[pdfSource.key] = File(simple).absolute.uri;
        final reader = ReaderSession(
          downloads: downloads,
          store: MemoryResume(),
          load: loadPublication,
          loadDocument: (file, source) =>
              runtime.open(file.uri.toFilePath(), file.digest),
        );
        addTearDown(downloads.dispose);
        addTearDown(reader.dispose);
        await reader.bind(account(), [book]);
        await reader.open(book, edition);
        final first = reader.document;
        tracked.documents.single.failure = failure;
        reader.closeView(reader.token);
        await reader.open(book, edition);
        expect(reader.document, isA<PdfBook>());
        expect(reader.document, isNot(same(first)));
        expect(reader.message, isNull);
        expect(reports.single.exception, same(failure));
        reader.closeView(reader.token);
        await until(
          () => tracked.documents.last.releases == 1,
          'second native release',
        );
        await reader.open(book, edition);
        expect(reader.document, isA<PdfBook>());
        reader.closeView(reader.token);
        await runtime.shutdown();
        expect(tracked.documents.map((document) => document.releases), [
          1,
          1,
          1,
        ]);
        reader.checkInvariants();
        runtime.checkInvariants();
      },
    );
  }

  test(
    'a cancellation Error cannot prevent the session from releasing its book',
    () async {
      final failure = AssertionError('cancel');
      final supply = HeldSupply()..closed.complete();
      final pdf = await runtime.open(simple, simpleDigest, textSupply: supply);
      final downloads = LocalFiles()
        ..files[pdfSource.key] = File(simple).absolute.uri;
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: loadPublication,
        loadDocument: (file, source) async => pdf,
      );
      addTearDown(downloads.dispose);
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      expect(reader.document, same(pdf));
      supply.cancelFailure = failure;
      reader.closeView(reader.token);
      await until(() => reports.isNotEmpty, 'the close failure is reported');
      expect(reader.document, isNull);
      expect(reports.single.exception, same(failure));
      expect(supply.releases, 1);
      expect(supply.cancels, 1);
      expect(tracked.documents.single.releases, 1);
      reader.dispose();
      await runtime.shutdown();
    },
  );

  for (final leaving in ['close', 'account change', 'another open']) {
    test('a late document reports its close failure after $leaving', () async {
      final failure = AssertionError('late document close');
      final stack = StackTrace.current;
      final started = Completer<void>();
      final admit = Completer<void>();
      var opens = 0;
      final downloads = LocalFiles()
        ..files[pdfSource.key] = File(simple).absolute.uri;
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: loadPublication,
        loadDocument: (file, source) async {
          final pdf = await runtime.open(file.uri.toFilePath(), file.digest);
          if (++opens == 1) {
            tracked.documents.single
              ..failure = failure
              ..failureStack = stack;
            started.complete();
            await admit.future;
          }
          return pdf;
        },
      );
      addTearDown(downloads.dispose);
      addTearDown(reader.dispose);
      await reader.bind(account(), [book]);
      final opening = reader.open(book, edition);
      await started.future;
      switch (leaving) {
        case 'close':
          reader.closeView(reader.token);
        case 'account change':
          await reader.bind(account(user: 'bob'), [book]);
        case 'another open':
          await reader.open(book, edition);
      }
      final current = reader.document;
      admit.complete();
      await opening;
      expect(reader.document, same(current));
      expect(tracked.documents.first.releases, 1);
      expect(reports, hasLength(1));
      expect(reports.single.exception, same(failure));
      expect(reports.single.stack, same(stack));
      await reader.open(book, edition);
      expect(reader.document, isA<PdfBook>());
      expect(reader.message, isNull);
      reader.closeView(reader.token);
      await runtime.shutdown();
      expect(
        tracked.documents.every((document) => document.releases == 1),
        isTrue,
      );
      expect(reports, hasLength(1));
      reader.checkInvariants();
      runtime.checkInvariants();
    });
  }
}
