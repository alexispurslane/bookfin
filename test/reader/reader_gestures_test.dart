// One gesture and chrome model for every reader view: a horizontal swipe
// turns the page, a tap on the page enters or leaves full screen, and the
// controls lie over a page that never moves or changes size.
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/viewport.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_reader.dart';
import 'pdf_viewport_test.dart' show DrawnPdf, drawn;
import 'quiet_pdf_test.dart' show openPdf, reflowed;
import 'reader_settings.dart';

/// The system UI modes that the reader asked Android for, in order.
List<String> systemModes(WidgetTester tester) {
  final modes = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
        modes.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return modes;
}

/// The source page that the reader shows.
int shownPage(ReaderSession reader) =>
    (reader.visibleAddress! as PdfAddress).sourcePage;

/// Taps the middle of the page.
Future<void> tapMiddle(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(find.byType(Scaffold)));
  await tester.pump();
}

/// Swipes across the middle of the page, to the left with [forward].
Future<void> swipe(WidgetTester tester, {bool forward = true}) async {
  await tester.dragFrom(
    tester.getCenter(find.byType(Scaffold)),
    Offset(forward ? -200 : 200, 0),
  );
  await tester.pump();
}

/// Every reader control that shows.
Finder controls() => find.byWidgetPredicate(
  (widget) =>
      widget is ReaderDock ||
      widget is AppBar ||
      widget is IconButton ||
      widget is Slider,
);

void main() {
  group('a PDF page', () {
    testWidgets('the reader has no top bar', (tester) async {
      await openPdf(tester, DrawnPdf());
      expect(find.byType(AppBar), findsNothing);
      expect(find.byTooltip('Hide reader controls'), findsNothing);
    });

    testWidgets('a swipe turns the page while the bottom bar is open', (
      tester,
    ) async {
      final reader = await openPdf(tester, DrawnPdf());
      expect(find.byType(ReaderDock), findsOneWidget);
      await swipe(tester);
      await drawn(
        tester,
        shown: find.bySemanticsLabel('Original source page 2'),
      );
      expect(shownPage(reader), 2);
      await swipe(tester, forward: false);
      await drawn(
        tester,
        shown: find.bySemanticsLabel('Original source page 1'),
      );
      expect(shownPage(reader), 1);
    });

    testWidgets('a swipe turns the page while the bottom bar is closed', (
      tester,
    ) async {
      systemModes(tester);
      final reader = await openPdf(tester, DrawnPdf());
      await tapMiddle(tester);
      expect(find.byType(ReaderDock), findsNothing);
      await swipe(tester);
      await drawn(
        tester,
        shown: find.bySemanticsLabel('Original source page 2'),
      );
      expect(shownPage(reader), 2);
    });

    testWidgets('a swipe moves reflowed text on by about a screen', (
      tester,
    ) async {
      final reader = await openPdf(tester, DrawnPdf());
      await chooseSetting(tester, 'Reflow text', settle: tester.pump);
      await drawn(tester, shown: reflowed);
      await tester.pump();
      final before = (reader.visibleAddress! as PdfAddress).character;
      await swipe(tester);
      await tester.pump();
      expect(
        (reader.visibleAddress! as PdfAddress).character,
        greaterThan(before),
      );
    });

    testWidgets('a horizontal drag on the bottom bar does not turn the page', (
      tester,
    ) async {
      final reader = await openPdf(tester, DrawnPdf());
      final dock = tester.getRect(find.byType(ReaderDock));
      // The tool row, away from the scrub bar.
      await tester.dragFrom(
        Offset(dock.center.dx, dock.bottom - 20),
        const Offset(-200, 0),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(shownPage(reader), 1);
    });

    testWidgets('a swipe on a zoomed page moves the page instead of turning '
        'it', (tester) async {
      final reader = await openPdf(tester, DrawnPdf());
      final middle = tester.getCenter(find.byType(Scaffold));
      // Two fingers spread apart zoom the page in.
      final first = await tester.startGesture(middle - const Offset(20, 0));
      final second = await tester.startGesture(
        middle + const Offset(20, 0),
        pointer: 2,
      );
      for (var step = 1; step <= 10; step++) {
        await first.moveBy(const Offset(-15, 0));
        await second.moveBy(const Offset(15, 0));
        await tester.pump();
      }
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      await swipe(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(shownPage(reader), 1);
    });

    testWidgets('a tap in the middle enters full screen and hides every '
        'control and Android\'s system bars', (tester) async {
      final modes = systemModes(tester);
      await openPdf(tester, DrawnPdf());
      expect(controls(), findsWidgets);
      await tapMiddle(tester);
      expect(controls(), findsNothing);
      expect(modes.last, 'SystemUiMode.immersiveSticky');
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
    });

    testWidgets('a second tap leaves full screen', (tester) async {
      final modes = systemModes(tester);
      await openPdf(tester, DrawnPdf());
      await tapMiddle(tester);
      await tapMiddle(tester);
      expect(find.byType(ReaderDock), findsOneWidget);
      expect(modes.last, 'SystemUiMode.edgeToEdge');
    });

    testWidgets('leaving the reader in full screen brings back the system '
        'bars', (tester) async {
      final modes = systemModes(tester);
      await openPdf(tester, DrawnPdf());
      await tapMiddle(tester);
      await tester.pumpWidget(const SizedBox());
      expect(modes.last, 'SystemUiMode.edgeToEdge');
    });

    testWidgets('showing and hiding the controls, and Android\'s system bars, '
        'never moves or resizes the page', (tester) async {
      systemModes(tester);
      // Android's status bar and navigation bar take room at the top and
      // the bottom while they show.
      tester.view.padding = const FakeViewPadding(top: 72, bottom: 144);
      tester.view.viewPadding = const FakeViewPadding(top: 72, bottom: 144);
      addTearDown(tester.view.reset);
      final pdf = DrawnPdf();
      final reader = await openPdf(tester, pdf);
      final page = tester.getRect(find.byType(PdfViewport));
      final place = reader.visibleAddress;
      final renders = pdf.renders;
      await tapMiddle(tester);
      // In full screen, Android hides its bars and reports no room for them.
      tester.view.padding = FakeViewPadding.zero;
      tester.view.viewPadding = FakeViewPadding.zero;
      await tester.pump();
      expect(tester.getRect(find.byType(PdfViewport)), page);
      tester.view.padding = const FakeViewPadding(top: 72, bottom: 144);
      tester.view.viewPadding = const FakeViewPadding(top: 72, bottom: 144);
      await tapMiddle(tester);
      expect(tester.getRect(find.byType(PdfViewport)), page);
      expect(reader.visibleAddress, same(place));
      expect(pdf.renders, renders, reason: 'The page was not drawn again.');
      // The bottom bar lies over the page.
      expect(
        page.contains(tester.getRect(find.byType(ReaderDock)).center),
        isTrue,
      );
    });

    testWidgets('a screen reader can show and hide the controls and turn the '
        'page', (tester) async {
      systemModes(tester);
      final semantics = tester.ensureSemantics();
      final reader = await openPdf(tester, DrawnPdf());
      SemanticsNode pageNode() => tester.getSemantics(
        find.bySemanticsLabel('Original source page ${shownPage(reader)}'),
      );
      SemanticsNode? withAction(SemanticsNode node, String label) {
        final id = CustomSemanticsAction.getIdentifier(
          CustomSemanticsAction(label: label),
        );
        for (SemanticsNode? at = node; at != null; at = at.parent) {
          if (at.getSemanticsData().customSemanticsActionIds?.contains(id) ??
              false) {
            return at;
          }
        }
        return null;
      }

      void perform(String label) {
        final node = withAction(pageNode(), label)!;
        node.owner!.performAction(
          node.id,
          SemanticsAction.customAction,
          CustomSemanticsAction.getIdentifier(
            CustomSemanticsAction(label: label),
          ),
        );
      }

      perform('Hide reader controls');
      await tester.pump();
      expect(find.byType(ReaderDock), findsNothing);
      perform('Show reader controls');
      await tester.pump();
      expect(find.byType(ReaderDock), findsOneWidget);
      SemanticsNode? scrolls(SemanticsNode node) {
        for (SemanticsNode? at = node; at != null; at = at.parent) {
          if (at.getSemanticsData().hasAction(SemanticsAction.scrollLeft)) {
            return at;
          }
        }
        return null;
      }

      final page = scrolls(pageNode())!;
      page.owner!.performAction(page.id, SemanticsAction.scrollLeft);
      await drawn(
        tester,
        shown: find.bySemanticsLabel('Original source page 2'),
      );
      expect(shownPage(reader), 2);
      semantics.dispose();
    });
  });

  group('an EPUB page', () {
    testWidgets('a tap enters full screen, and the page keeps its layout', (
      tester,
    ) async {
      final modes = systemModes(tester);
      final reader = await openNative(tester);
      final page = tester.getRect(find.byType(EpubViewport));
      final shown = shownOf(reader);
      expect(find.byType(AppBar), findsNothing);
      await tapMiddle(tester);
      await tester.pump(const Duration(milliseconds: 16));
      expect(controls(), findsNothing);
      expect(modes.last, 'SystemUiMode.immersiveSticky');
      expect(tester.getRect(find.byType(EpubViewport)), page);
      expect(
        shownOf(reader),
        same(shown),
        reason: 'The page was not laid out again.',
      );
      await tapMiddle(tester);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(ReaderDock), findsOneWidget);
      expect(shownOf(reader), same(shown));
      await closeNative(tester, reader);
    });

    testWidgets('a swipe turns the page while the bottom bar is closed', (
      tester,
    ) async {
      systemModes(tester);
      final reader = await openNative(tester);
      final first = shownOf(reader);
      await tapMiddle(tester);
      await swipe(tester);
      await waitForPage(tester, reader, (shown) => !identical(shown, first));
      expect(find.byType(ReaderDock), findsNothing);
      await closeNative(tester, reader);
    });
  });
}
