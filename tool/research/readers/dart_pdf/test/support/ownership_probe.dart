import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> main(List<String> arguments) async {
  switch (arguments.single) {
    case 'separate-workers':
      await separateWorkers();
    case 'shared-worker':
      stdout.writeln(jsonEncode(await sharedWorker()));
    default:
      throw ArgumentError('Unknown ownership probe');
  }
}

Future<Map<String, Object?>> sharedWorker() async {
  await initialize();
  try {
    final worker = await workerIdentity();
    final allDocumentsOpened = Completer<void>();
    var openedDocumentCount = 0;
    Future<void> waitForDocumentCallers() {
      if (++openedDocumentCount == 3) allDocumentsOpened.complete();
      return allDocumentsOpened.future;
    }

    final callers = await Future.wait([
      observeDocument(whenOpened: waitForDocumentCallers),
      Pdfrx.runAsBackgroundWork(
        () => observeDocument(whenOpened: waitForDocumentCallers),
      ),
      observeDocument(whenOpened: waitForDocumentCallers),
    ]);
    final report = <String, Object?>{
      'callers': callers.length,
      'documents_open_before_reading': openedDocumentCount,
      'same_worker': callers.every((caller) => caller.worker == worker),
      'texts': callers.map((caller) => caller.text).toList(),
      'render_widths': callers.map((caller) => caller.width).toList(),
      'visible_renders': callers.map((caller) => caller.visible).toList(),
      'font_callback_faces': await observeFontCallbacks(),
    };
    final bytes = await File('../fixtures/simple.pdf').readAsBytes();
    var documentCloseCallbacks = 0;
    final reopenedTexts = <String>[];
    var reopenSameWorker = true;
    for (var opening = 0; opening < 2; opening++) {
      final document = await PdfDocument.openData(
        bytes,
        sourceName: 'close-reopen-$opening',
        onDispose: () => documentCloseCallbacks++,
      );
      try {
        reopenedTexts.add((await document.pages.first.loadText())!.fullText);
        reopenSameWorker &= await workerIdentity() == worker;
      } finally {
        await document.dispose();
        await document.dispose();
      }
    }
    report.addAll({
      'reopened_texts': reopenedTexts,
      'reopen_same_worker': reopenSameWorker,
      'document_close_callbacks': documentCloseCallbacks,
    });

    var failedDocumentCloseCallbacks = 0;
    final callerFailure = StateError('document caller failed');
    var callerFailurePropagated = false;
    try {
      final document = await PdfDocument.openData(
        bytes,
        sourceName: 'failed-caller',
        onDispose: () => failedDocumentCloseCallbacks++,
      );
      try {
        await document.pages.first.loadText();
        throw callerFailure;
      } finally {
        await document.dispose();
      }
    } on StateError catch (error) {
      if (!identical(error, callerFailure)) rethrow;
      callerFailurePropagated = true;
    }
    var malformedDocumentRejected = false;
    try {
      final unexpectedDocument = await PdfDocument.openData(
        bytes.sublist(0, 32),
        sourceName: 'truncated-copy',
      );
      await unexpectedDocument.dispose();
    } on PdfException {
      malformedDocumentRejected = true;
    }
    final afterFailure = await observeDocument();
    report.addAll({
      'caller_failure_propagated': callerFailurePropagated,
      'failed_document_close_callbacks': failedDocumentCloseCallbacks,
      'after_failure_text': afterFailure.text,
      'malformed_document_rejected': malformedDocumentRejected,
    });

    final workerExits = [await stopWorkerAndObserveExit()];
    final restarted = await observeDocument();
    final restartFontFaces = await observeFontCallbacks();
    workerExits.add(await stopWorkerAndObserveExit());
    report.addAll({
      'worker_exit_events': workerExits,
      'restart_has_new_worker': restarted.worker != worker,
      'restart_text': restarted.text,
      'restart_render_visible': restarted.visible,
      'restart_font_callback_faces': restartFontFaces,
      'dart_font_mapper_enabled': !Pdfrx.useProcessWidePdfiumGate,
    });
    return report;
  } finally {
    await PdfrxEntryFunctions.instance.stopBackgroundWorker();
  }
}

Future<List<String>> observeFontCallbacks() async {
  final document = await PdfDocument.openFile('../fixtures/simple.pdf');
  try {
    final event = await document.events
        .where((event) => event is PdfDocumentMissingFontsEvent)
        .cast<PdfDocumentMissingFontsEvent>()
        .first
        .timeout(const Duration(seconds: 5));
    return event.missingFonts.map((font) => font.face).toList();
  } finally {
    await document.dispose();
  }
}

Future<Object?> stopWorkerAndObserveExit() async {
  final exited = ReceivePort();
  try {
    await PdfrxEntryFunctions.instance.compute(
      (SendPort listener) => Isolate.current.addOnExitListener(
        listener,
        response: Isolate.current.debugName,
      ),
      exited.sendPort,
    );
    await PdfrxEntryFunctions.instance.stopBackgroundWorker();
    return await exited.first.timeout(const Duration(seconds: 5));
  } finally {
    exited.close();
  }
}

Future<SendPort> workerIdentity() => PdfrxEntryFunctions.instance.compute(
  (_) => Isolate.current.controlPort,
  null,
);

Future<({SendPort worker, String text, int width, bool visible})>
observeDocument({Future<void> Function()? whenOpened}) async {
  final document = await PdfDocument.openFile('../fixtures/simple.pdf');
  try {
    await whenOpened?.call();
    final worker = await workerIdentity();
    final page = document.pages.first;
    final text = await page.loadText();
    final image = await page.render(
      fullWidth: 120,
      fullHeight: page.height * 120 / page.width,
    );
    try {
      return (
        worker: worker,
        text: text!.fullText,
        width: image!.width,
        visible: image.pixels.any((value) => value < 200),
      );
    } finally {
      image?.dispose();
    }
  } finally {
    await document.dispose();
  }
}

Future<void> initialize() async {
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  await pdfrxInitialize();
}

Future<void> separateWorkers() async {
  final replies = ReceivePort();
  final events = StreamIterator<dynamic>(replies);
  final first = await Isolate.spawn(independentCaller, replies.sendPort);
  await events.moveNext();
  final firstCommands = events.current as SendPort;
  final second = await Isolate.spawn(independentCaller, replies.sendPort);
  await events.moveNext();
  final secondCommands = events.current as SendPort;
  stdout.writeln('Two independent PDF workers initialized; loading on first.');
  firstCommands.send(replies.sendPort);
  await events.moveNext();
  stdout.writeln(jsonEncode(events.current));
  secondCommands.send(replies.sendPort);
  await events.moveNext();
  first.kill(priority: Isolate.immediate);
  second.kill(priority: Isolate.immediate);
  await events.cancel();
  replies.close();
}

Future<void> independentCaller(SendPort parent) async {
  await initialize();
  final commands = ReceivePort();
  parent.send(commands.sendPort);
  await for (final reply in commands) {
    final document = await PdfDocument.openFile('../fixtures/simple.pdf');
    try {
      final text = await document.pages.first.loadText();
      (reply as SendPort).send({'text': text!.fullText});
    } finally {
      await document.dispose();
    }
  }
}
