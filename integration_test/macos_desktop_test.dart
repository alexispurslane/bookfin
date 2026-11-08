// The macOS desktop acceptance run. It drives the real app, with its real
// plugins and runner, against the showcase fixture, and saves an image of
// each step.
//
// Start the fixture first, in the default shell:
//   nix develop --command dart run tool/showcase_fixture.dart 18431 --sync-conflict
// Then run, in the macOS shell:
//   nix develop .#macos --command bash tool/bookfin accept-macos
//
// The app runs in the App Sandbox, so the images land in its container:
// ~/Library/Containers/dev.bookfin.bookfin/Data/tmp/bookfin-macos-acceptance
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bookfin/catalog/model.dart' show EditionKind;
import 'package:bookfin/catalog/book_page.dart' show EditionPanel;
import 'package:bookfin/main.dart';
import 'package:bookfin/reader/pdf_viewport.dart' show PdfViewport;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const server = String.fromEnvironment(
  'BOOKFIN_FIXTURE',
  defaultValue: 'http://127.0.0.1:18431',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Each pump draws its frame itself. macOS sends no display refresh to a
  // window that other windows cover, and a pump that waited for one would
  // wait forever.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  late Directory images;

  Future<void> wait(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final end = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        throw TestFailure('Timed out waiting for $finder. ${shown()}');
      }
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 400));
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(
        Offset.zero & view.size,
        pixelRatio: view.flutterView.devicePixelRatio,
      );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${images.path}/$name.png')
          .writeAsBytes(png!.buffer.asUint8List());
    });
    debugPrint('MACOS_ACCEPTANCE_IMAGE $name ${shown()}');
  }

  /// Goes back, as the Android back gesture does, until [until] shows. It
  /// stops when no navigator can go back, because a back with nothing to
  /// close quits a macOS app.
  Future<void> back(WidgetTester tester, {required Finder until}) async {
    bool canPop() => find
        .byType(Navigator)
        .evaluate()
        .any(
          (element) =>
              (element as StatefulElement).state is NavigatorState &&
              (element.state as NavigatorState).canPop(),
        );
    for (
      var step = 0;
      step < 6 && until.hitTestable().evaluate().isEmpty && canPop();
      step++
    ) {
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 1));
    }
  }

  /// Drags the first scrollable by [dy] until [target] can take a tap. A
  /// negative [dy] scrolls down the page.
  Future<void> scrollTo(
    WidgetTester tester,
    Finder target, {
    double dy = -300,
  }) async {
    for (
      var drag = 0;
      drag < 20 && target.hitTestable().evaluate().isEmpty;
      drag++
    ) {
      await tester.drag(find.byType(Scrollable).first, Offset(0, dy));
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  setUpAll(() async {
    images = Directory('${Directory.systemTemp.path}/bookfin-macos-acceptance');
    if (await images.exists()) await images.delete(recursive: true);
    await images.create(recursive: true);
    debugPrint('MACOS_ACCEPTANCE_DIRECTORY ${images.path}');
  });

  testWidgets('the macOS app signs in, lists, plays, reads and syncs', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    unawaited(runBookfin());
    await wait(tester, find.byType(Scaffold));
    await tester.pump(const Duration(seconds: 2));
    if (find.text('Sign in').evaluate().isNotEmpty) {
      await capture(tester, '01-signed-out');
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), server);
      await tester.enterText(fields.at(1), 'reader');
      await tester.enterText(fields.at(2), 'showcase');
      await tester.tap(find.text('Sign in'));
    }
    await wait(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data == 'Ebooks' || widget.data == 'Save libraries'),
      ),
    );
    if (find.text('Save libraries').evaluate().isNotEmpty) {
      final audiobooks = find.widgetWithText(CheckboxListTile, 'Audiobooks');
      if (tester.widget<CheckboxListTile>(audiobooks).value != true) {
        await tester.tap(audiobooks);
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.tap(find.text('Save libraries'));
    }
    await tester.pump(const Duration(seconds: 3));
    await capture(tester, '02-library');
    debugPrint('MACOS_ACCEPTANCE_LABELS ${labels(tester)}');

    // The library has a looping cover animation, so nothing here waits for
    // the frames to settle.
    final orchard = find.textContaining('Orchard Cycle');
    await scrollTo(tester, orchard);
    await tester.tap(orchard.hitTestable().first);
    await tester.pump(const Duration(seconds: 2));
    await capture(tester, '03-series');
    debugPrint('MACOS_ACCEPTANCE_LABELS ${labels(tester)}');
    await tester.tap(find.text('First Frost').hitTestable().first);
    await wait(tester, find.text('Listen'));
    await capture(tester, '04-book');

    // Listening: download the recording, play it, and pause it.
    final downloaded = find.byTooltip(RegExp(r'Remove download$'));
    if (downloaded.evaluate().isEmpty) {
      await tester.tap(find.byTooltip('Download'));
    }
    await wait(tester, downloaded, timeout: const Duration(minutes: 3));
    await capture(tester, '05-downloaded');
    await tester.tap(find.text('Listen'));
    await wait(tester, find.byTooltip('Pause'));
    await tester.pump(const Duration(seconds: 5));
    await capture(tester, '06-playing');
    await tester.tap(find.byTooltip('Pause').hitTestable().first);
    await wait(tester, find.byTooltip('Play'));
    await capture(tester, '07-paused');

    // Reading: download the PDF edition of Windfall and open it.
    await back(tester, until: orchard);
    await tester.tap(orchard.hitTestable().first);
    await wait(tester, find.text('Windfall'));
    await scrollTo(tester, find.text('Windfall'));
    await tester.tap(find.text('Windfall').hitTestable().first);
    await wait(tester, find.text('Read'));
    final pdf = find.byWidgetPredicate(
      (widget) =>
          widget is EditionPanel && widget.edition.kind == EditionKind.text,
    );
    final pdfDownload = find.descendant(
      of: pdf,
      matching: find.widgetWithText(OutlinedButton, 'Download'),
    );
    final pdfRemove = find.descendant(
      of: pdf,
      matching: find.widgetWithText(TextButton, 'Remove'),
    );
    await scrollTo(
      tester,
      pdfRemove.evaluate().isEmpty ? pdfDownload : pdfRemove,
    );
    if (pdfDownload.evaluate().isNotEmpty) {
      await tester.tap(pdfDownload.hitTestable());
    }
    await wait(tester, pdfRemove, timeout: const Duration(minutes: 3));
    await capture(tester, '08-pdf-downloaded');
    await scrollTo(tester, find.text('Read'), dy: 300);
    await tester.tap(find.text('Read').hitTestable().first);
    await wait(tester, find.byType(PdfViewport));
    await tester.pump(const Duration(seconds: 6));
    await capture(tester, '09-pdf');

    // Personal records: sync twice. The fixture answers the second sync
    // with a conflict from a made-up second device.
    await back(tester, until: find.text('Settings'));
    await tester.tap(find.text('Settings').last);
    await wait(tester, find.text('Personal-record sync'));
    await tester.tap(find.text('Personal-record sync'));
    for (final name in ['10-synced', '11-sync-conflict']) {
      await wait(tester, find.text('Sync now'));
      await tester.tap(find.text('Sync now'));
      await tester.pump(const Duration(seconds: 1));
      await wait(
        tester,
        find.text('Sync now'),
        timeout: const Duration(minutes: 2),
      );
      await tester.pump(const Duration(seconds: 2));
      await capture(tester, name);
    }

    // The window: the phone layout at a laptop window and at the minimum.
    await back(tester, until: find.text('Library'));
    await tester.tap(find.text('Library').last);
    final view = tester.view;
    for (final (width, height) in [(1280.0, 800.0), (360.0, 600.0)]) {
      view.physicalSize = Size(width, height) * view.devicePixelRatio;
      await tester.pump(const Duration(seconds: 2));
      await capture(tester, '12-library-${width.toInt()}x${height.toInt()}');
    }
    view.resetPhysicalSize();
    await tester.pump(const Duration(seconds: 1));

    // Sign out, so the next build starts without a saved sign-in.
    await tester.tap(find.text('Settings').last);
    await wait(tester, find.text('Sign out'));
    await scrollTo(tester, find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await wait(tester, find.text('Sign in'));
    await capture(tester, '13-signed-out');
    semantics.dispose();
  });
}

/// The semantics labels on screen, for the log.
String labels(WidgetTester tester) {
  final found = <String>[];
  void visit(SemanticsNode node) {
    if (node.label.isNotEmpty) found.add(node.label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  final root =
      tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
  if (root != null) visit(root);
  return found.take(60).join(' | ');
}

/// The texts on screen, for the log.
String shown() => find
    .byType(Text)
    .evaluate()
    .map((element) => (element.widget as Text).data)
    .whereType<String>()
    .take(40)
    .join(' | ');
