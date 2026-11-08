import 'dart:async';

import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_test.dart' show GatedRecordStore;
import 'playback_test.dart'
    show LocalFiles, TestEngine, MemoryResume, account, title, recording;

/// The Undo offer after a position change is a one-line pill under the
/// transport controls. These tests measure it on a Pixel 8 sized screen,
/// in the app's own Outfit font, so line breaks match the phone.
void main() {
  setUpAll(() async {
    final outfit = FontLoader('Outfit')
      ..addFont(rootBundle.load('assets/fonts/Outfit.ttf'));
    await outfit.load();
  });

  /// [theme] with all its text in Outfit, the typeface of the approved
  /// mockup. Text that names no family would use the test font, whose
  /// glyphs are all one em wide.
  ThemeData appTypeface(ThemeData theme) =>
      theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Outfit'));

  /// The Pixel 8 screen: 1080 by 2400 pixels at 2.625 pixels per point.
  void pixel8(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  group('with a book open', () {
    late Playback playback;
    late LocalFiles downloads;
    setUp(() async {
      downloads = LocalFiles();
      playback = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: MemoryResume(),
      );
      await playback.bind(account(), [title]);
      await playback.open(title, recording, autoplay: false);
    });
    tearDown(() async {
      await playback.close();
      downloads.dispose();
    });

    /// Shows the player on its own stage, or in the glass pane that the
    /// mini player opens.
    Future<void> showPlayer(
      WidgetTester tester, {
      required bool pane,
      required Brightness brightness,
    }) async {
      pixel8(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(brightness),
          home: Scaffold(
            body: pane
                ? Builder(
                    builder: (context) => TextButton(
                      onPressed: () => openPlayer(context, playback),
                      child: const Text('Open'),
                    ),
                  )
                : PlayerView(playback: playback),
          ),
        ),
      );
      if (pane) {
        await tester.tap(find.text('Open'));
      }
      await tester.pumpAndSettle();
    }

    for (final pane in [false, true]) {
      for (final brightness in Brightness.values) {
        final where = pane ? 'in the popup pane' : 'on the stage';
        final when = brightness == Brightness.dark ? 'at night' : 'by day';
        testWidgets('$where $when the tool row stays in place while Undo '
            'appears and goes', (tester) async {
          await showPlayer(tester, pane: pane, brightness: brightness);
          Offset toolRow() => tester.getTopLeft(find.text('Chapters'));
          final before = toolRow();

          await tester.runAsync(() async {
            await playback.seekEdition(75000);
            await playback.flush();
          });
          await tester.pumpAndSettle();
          expect(find.text('Undo'), findsOneWidget);
          expect(toolRow(), before);
          expect(
            tester.getBottomLeft(find.text('History')).dy,
            lessThanOrEqualTo(tester.view.physicalSize.height / 2.625),
          );

          await tester.tap(find.byTooltip('Dismiss Undo'));
          await tester.pumpAndSettle();
          expect(find.text('Undo'), findsNothing);
          expect(toolRow(), before);
        });
      }
    }

    testWidgets('Undo in the popup pane goes back to the previous place', (
      tester,
    ) async {
      await showPlayer(tester, pane: true, brightness: Brightness.light);
      await tester.runAsync(() async {
        await playback.seekEdition(75000);
        await playback.flush();
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Undo'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(playback.editionMilliseconds, 0);
    });
  });

  group('while audio plays', () {
    late Playback playback;
    late LocalFiles downloads;
    late TestEngine engine;
    late _HeldOrFailingStore store;
    setUp(() async {
      downloads = LocalFiles();
      engine = TestEngine();
      store = _HeldOrFailingStore();
      playback = Playback(downloads: downloads, engine: engine, store: store);
      await playback.bind(account(), [title]);
      await playback.open(title, recording, autoplay: false);
    });
    tearDown(() async {
      await playback.close();
      downloads.dispose();
    });

    testWidgets('the Undo pill says Saving until the previous place is saved', (
      tester,
    ) async {
      pixel8(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(body: PlayerView(playback: playback)),
        ),
      );
      store.fail = true;
      await tester.runAsync(() => playback.seekEdition(75000));
      await tester.pump();
      expect(find.text('Saving your previous place'), findsOneWidget);
      store.fail = false;
      await tester.runAsync(playback.flush);
      await tester.pump();
      expect(find.text('Your previous place is saved'), findsOneWidget);
    });

    // A playing tick saves the place where audio plays now, which is not
    // the previous place that Undo returns to.
    testWidgets('the Undo pill stays saved while a playing tick saves the '
        'place', (tester) async {
      pixel8(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(body: PlayerView(playback: playback)),
        ),
      );
      await tester.runAsync(() async {
        await playback.play();
        await playback.seekEdition(75000);
        await playback.flush();
      });
      await tester.pump();
      expect(find.text('Your previous place is saved'), findsOneWidget);
      // The held save and the tick run in real time, because a future made
      // on the test clock completes only when that clock moves.
      late Completer<void> gate;
      await tester.runAsync(() async {
        gate = store.gate = Completer<void>();
        // The tick crosses a whole second, so Playback saves the place.
        engine.emit(engine.index, engine.milliseconds + 1000, playing: true);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      final saving = playback.unsavedChanges;
      final shown = find.text('Your previous place is saved').evaluate().length;
      await tester.runAsync(() async {
        gate.complete();
        // A closing Playback stops what plays, and that save must run in
        // real time, so the test pauses here.
        await playback.pause();
        await playback.flush();
      });
      expect(saving, isTrue);
      expect(shown, 1);
    });
  });

  for (final unsaved in [false, true]) {
    testWidgets('the Undo pill tells ${unsaved ? 'that the previous place is '
                  'still saving' : 'that the previous place is saved'} on one '
        'line beside Undo', (tester) async {
      pixel8(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTypeface(bookfinTheme(Brightness.light)),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              // The stage's tool row margin on each side.
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: UndoNotice(
                  unsaved: unsaved,
                  onUndo: () {},
                  onDismiss: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final message = find.descendant(
        of: find.byType(UndoNotice),
        matching: find.byWidgetPredicate(
          (widget) => widget is Text && widget.data != 'Undo',
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(message);
      final length = paragraph.text.toPlainText().length;
      final lineTops = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: length),
          )
          .map((box) => box.top)
          .toSet();
      expect(lineTops, hasLength(1));
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        tester.getCenter(message).dy,
        moreOrLessEquals(tester.getCenter(find.text('Undo')).dy, epsilon: 1),
      );
    });
  }
}

/// A record store whose saves can wait at [gate], or fail while [fail] is
/// set, as on a slow or full disk.
class _HeldOrFailingStore extends GatedRecordStore {
  bool fail = false;
  @override
  Future<void> save(String accountKey, ListeningChanges changes) async {
    if (fail) throw Exception('disk full');
    await super.save(accountKey, changes);
  }
}
