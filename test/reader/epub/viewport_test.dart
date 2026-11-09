// The viewport draws the pager's shown page and reports what the person did:
// taps, links, swipes, keys and trackpad scrolls. Its only request of the
// pager is present, from its own layout. A test scheduler runs the page
// source's layout steps, real time lets the workers finish, and the pager's
// invariants are checked after every step.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/epub/viewport.dart';
import 'package:bookfin/reader/page_previews.dart';
import 'package:bookfin/reader/scrub_deck.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'page_source_test.dart' show TestScheduler;
import 'pager_test.dart' show linkedBook, noteBook, showcaseBook;

void main() {
  setUpAll(loadReaderFont);

  late TestScheduler scheduler;
  late PageSource source;
  EpubPager? opened;
  final reported = <EpubAddress>[];
  final warnings = <String>[];
  final turns = <bool>[];
  final links = <EpubLink>[];
  var taps = 0;
  final boundary = GlobalKey();

  EpubPager pager() => opened!;

  void open(Publication publication) {
    source = PageSource(publication, schedule: scheduler.schedule);
    final made = EpubPager(
      EpubDocument(publication),
      onPlace: reported.add,
      onWarning: warnings.add,
      source: source,
    );
    scheduler.afterStep = made.checkInvariants;
    opened = made;
  }

  setUp(() {
    scheduler = TestScheduler();
    reported.clear();
    warnings.clear();
    turns.clear();
    links.clear();
    taps = 0;
  });
  tearDown(() {
    opened?.dispose();
    opened = null;
  });

  Widget viewport({double fontSize = 20, bool night = false}) => EpubViewport(
    pager: pager(),
    fontSize: fontSize,
    night: night,
    onTap: () => taps++,
    onTurn: turns.add,
    onLink: links.add,
    onCopy: (_) {},
  );

  /// Shows the viewport alone on a screen of [size] logical pixels, at one
  /// physical pixel each.
  Future<void> show(
    WidgetTester tester, {
    double fontSize = 20,
    bool night = false,
    Size size = const Size(412, 671),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      onScreen(
        RepaintBoundary(
          key: boundary,
          child: viewport(fontSize: fontSize, night: night),
        ),
      ),
    );
  }

  /// Runs layout steps, real time for the workers and frames until [done]
  /// holds and no step has run for a while.
  Future<void> settle(WidgetTester tester, [bool Function()? done]) async {
    var quiet = 0;
    for (var turn = 0; turn < 5000; turn++) {
      if (scheduler.runOne()) {
        quiet = 0;
      } else {
        quiet++;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      await tester.pump();
      pager().checkInvariants();
      if ((done?.call() ?? true) && quiet >= 10) return;
    }
    fail('The pager did not settle.');
  }

  /// Runs [work] to its end (see [settle]).
  Future<void> finish(WidgetTester tester, Future<void> work) async {
    var ended = false;
    unawaited(work.whenComplete(() => ended = true));
    await settle(tester, () => ended);
    await work;
  }

  ShownPage shown() => pager().shown.value!;

  Future<Uint8List> pixels(WidgetTester tester, ui.Image Function() draw) =>
      tester
          .runAsync(() async {
            final image = draw();
            final bytes = await image.toByteData();
            image.dispose();
            return bytes!.buffer.asUint8List();
          })
          .then((bytes) => bytes!);

  /// What the viewport painted, one byte per channel, RGBA.
  Future<Uint8List> painted(WidgetTester tester) => pixels(
    tester,
    () => tester
        .renderObject<RenderRepaintBoundary>(find.byKey(boundary))
        .toImageSync(),
  );

  /// [picture] drawn on its own at [size].
  Future<Uint8List> drawn(WidgetTester tester, ui.Picture picture, Size size) =>
      pixels(
        tester,
        () => picture.toImageSync(size.width.round(), size.height.round()),
      );

  /// The centre of the visible character [offset] of text node [text] on
  /// the shown page, from the page's top left corner.
  Offset pointOf(DomText text, int offset) {
    final page = shown().page;
    final place = EpubPlace(page.section, text.order, offset);
    for (final piece in page.pieces) {
      for (var unit = 0; unit < piece.map.length; unit++) {
        if (piece.map.textPlaceAt(unit) != place) continue;
        final box = piece.paragraph.getBoxesForRange(unit, unit + 1).first;
        return Offset(
          piece.x + (box.left + box.right) / 2,
          piece.y - page.top + (box.top + box.bottom) / 2,
        );
      }
    }
    throw StateError('$place is not on the shown page.');
  }

  /// Whether [page] holds the first visible character of [before].
  bool holdsStart(LaidPage page, LaidPage before) =>
      page.section == before.section &&
      page.startVisible <= before.startVisible &&
      before.startVisible < page.endVisible;

  /// Counts the rebuilds of the viewport and of everything inside it while
  /// [body] runs.
  Future<int> rebuildsDuring(Future<void> Function() body) async {
    var rebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is EpubViewport ||
          element.findAncestorWidgetOfExactType<EpubViewport>() != null) {
        rebuilds++;
      }
    };
    try {
      await body();
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    return rebuilds;
  }

  testWidgets('before the first page, the viewport paints the paper of its '
      'theme', (tester) async {
    open(linkedBook());
    await show(tester, night: true);
    final night = const PageSettings(
      width: 1,
      height: 1,
      fontSize: 20,
      night: true,
    ).paper;
    expect(pager().shown.value, isNull);
    final bytes = await painted(tester);
    expect(bytes, hasLength(412 * 671 * 4));
    for (var index = 0; index < bytes.length; index += 4) {
      expect(
        Color.fromARGB(
          bytes[index + 3],
          bytes[index],
          bytes[index + 1],
          bytes[index + 2],
        ),
        night,
        reason: 'pixel ${index ~/ 4}',
      );
    }
  });

  testWidgets('the viewport presents its own size, text size and theme, and '
      'paints the pager\'s shown picture at that size', (tester) async {
    open(showcaseBook('salt'));
    await show(tester);
    await settle(tester, () => pager().shown.value != null);

    expect(
      shown().page.settings,
      const PageSettings(width: 412, height: 671, fontSize: 20, night: false),
    );
    expect(
      await painted(tester),
      await drawn(tester, shown().picture, const Size(412, 671)),
    );
    expect(warnings, isEmpty);
  });

  testWidgets('a new shown page repaints the viewport without rebuilding it', (
    tester,
  ) async {
    open(showcaseBook('salt'));
    await show(tester);
    await settle(tester, () => pager().shown.value != null);
    final first = shown().page;

    final rebuilds = await rebuildsDuring(
      () => finish(tester, pager().move(true)),
    );

    expect(shown().page, isNot(same(first)));
    expect(rebuilds, 0);
    expect(
      await painted(tester),
      await drawn(tester, shown().picture, const Size(412, 671)),
    );
  });

  testWidgets('a tap away from links calls onTap, and a tap on a link calls '
      'onLink with its destination and not onTap', (tester) async {
    open(linkedBook());
    await show(tester);
    await settle(tester, () => pager().shown.value != null);
    final dom = source.sectionOf(shown().page).dom;
    final link = dom.texts.firstWhere(
      (text) => text.text == 'Follow the lantern',
    );
    final plain = dom.texts.firstWhere(
      (text) => text.text.startsWith('Before the link'),
    );

    await tester.tapAt(pointOf(link, 4));
    expect(links, [(href: 'text/s1.xhtml#target', noteref: false)]);
    expect(taps, 0);

    await tester.tapAt(pointOf(plain, 2));
    expect(taps, 1);
    expect(links, hasLength(1));
    expect(turns, isEmpty);
  });

  testWidgets('a horizontal swipe of more than 60 pixels with less than 50 '
      'vertical turns the page, to the next page for a swipe to the left', (
    tester,
  ) async {
    open(linkedBook());
    await show(tester);
    await settle(tester, () => pager().shown.value != null);
    const middle = Offset(206, 335);

    await tester.dragFrom(middle, const Offset(-100, 0));
    expect(turns, [true]);
    await tester.dragFrom(middle, const Offset(100, 0));
    expect(turns, [true, false]);
    await tester.dragFrom(middle, const Offset(-61, 49));
    expect(turns, [true, false, true]);
    expect(taps, 0);
  });

  testWidgets('a short drag, a diagonal drag and a mouse drag turn nothing', (
    tester,
  ) async {
    open(linkedBook());
    await show(tester);
    await settle(tester, () => pager().shown.value != null);
    const middle = Offset(206, 335);

    await tester.dragFrom(middle, const Offset(-60, 0));
    await tester.dragFrom(middle, const Offset(40, 0));
    await tester.dragFrom(middle, const Offset(-100, 50));
    await tester.dragFrom(middle, const Offset(100, -80));
    // On a desktop, a mouse drag selects text.
    await tester.dragFrom(
      middle,
      const Offset(-100, 0),
      kind: PointerDeviceKind.mouse,
    );
    expect(turns, isEmpty);
    expect(links, isEmpty);
  });

  testWidgets('with focus, the right arrow, Page Down and Space turn to the '
      'next page, and the left arrow and Page Up to the previous one', (
    tester,
  ) async {
    open(linkedBook());
    await show(tester);
    await settle(tester, () => pager().shown.value != null);

    for (final key in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.keyA,
    ]) {
      await tester.sendKeyEvent(key);
    }
    expect(turns, [true, true, true, false, false]);
  });

  testWidgets('a horizontal trackpad scroll of 80 pixels turns the page once, '
      'to the next page for a scroll to the right', (tester) async {
    open(linkedBook());
    await show(tester);
    await settle(tester, () => pager().shown.value != null);
    const middle = Offset(206, 335);
    var id = 10;

    /// Two fingers that move [pan] over the trackpad in one gesture.
    Future<void> pan(List<Offset> steps) async {
      final fingers = TestPointer(id++, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(fingers.panZoomStart(middle));
      for (final step in steps) {
        await tester.sendEventToBinding(
          fingers.panZoomUpdate(middle, pan: step),
        );
      }
      await tester.sendEventToBinding(fingers.panZoomEnd());
    }

    // The fingers move left to scroll the page to the right.
    await pan([const Offset(-40, 0), const Offset(-90, 0)]);
    expect(turns, [true]);
    await pan([const Offset(90, 0)]);
    expect(turns, [true, false]);
    await pan([const Offset(-70, 0)]);
    await pan([const Offset(-90, -120)]);
    expect(turns, [true, false]);
    await pan([const Offset(-90, 0), const Offset(-200, 0)]);
    expect(turns, [true, false, true]);

    // A trackpad that reports scroll signals, as on Linux.
    final scroller = TestPointer(id++, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(scroller.hover(middle));
    await tester.sendEventToBinding(scroller.scroll(const Offset(50, 0)));
    expect(turns, hasLength(3));
    await tester.sendEventToBinding(scroller.scroll(const Offset(40, 0)));
    expect(turns, [true, false, true, true]);
    await tester.sendEventToBinding(scroller.scroll(const Offset(-90, 0)));
    expect(turns, [true, false, true, true, false]);
    await tester.sendEventToBinding(scroller.scroll(const Offset(0, 300)));
    expect(turns, hasLength(5));
    expect(taps, 0);
  });

  testWidgets('a resize presents the new page size, and the shown place '
      'stays', (tester) async {
    open(showcaseBook('salt'));
    await show(tester);
    await settle(tester, () => pager().shown.value != null);
    await finish(tester, pager().move(true));
    await finish(tester, pager().move(true));
    final before = shown().page;
    final saved = reported.length;

    tester.view.physicalSize = const Size(520, 700);
    await tester.pump();
    await settle(tester, () => shown().page.settings.width == 520);

    expect(
      shown().page.settings,
      const PageSettings(width: 520, height: 700, fontSize: 20, night: false),
    );
    expect(holdsStart(shown().page, before), isTrue);
    expect(reported, hasLength(saved), reason: 'The place did not move.');
    expect(
      await painted(tester),
      await drawn(tester, shown().picture, const Size(520, 700)),
    );
  });

  /// Changes the viewport from cream at 20 pixels to [fontSize] and
  /// [night], and checks that the old page stays painted until the new one
  /// arrives at the same place.
  Future<void> changeAppearance(
    WidgetTester tester, {
    required double fontSize,
    required bool night,
  }) async {
    open(showcaseBook('salt'));
    await show(tester);
    await settle(tester, () => pager().shown.value != null);
    await finish(tester, pager().move(true));
    final before = shown();
    final oldPixels = await painted(tester);
    final saved = reported.length;

    await show(tester, fontSize: fontSize, night: night);
    expect(pager().shown.value, same(before));
    expect(await painted(tester), oldPixels);

    final wanted = PageSettings(
      width: 412,
      height: 671,
      fontSize: fontSize,
      night: night,
    );
    await settle(tester, () => shown().page.settings == wanted);
    expect(holdsStart(shown().page, before.page), isTrue);
    expect(reported, hasLength(saved));
    expect(
      await painted(tester),
      await drawn(tester, shown().picture, const Size(412, 671)),
    );
  }

  testWidgets('a text size change presents new settings, and the old page '
      'stays painted until the new one arrives', (tester) async {
    await changeAppearance(tester, fontSize: 26, night: false);
  });

  testWidgets('a theme change presents new settings, and the old page stays '
      'painted until the new one arrives', (tester) async {
    await changeAppearance(tester, fontSize: 20, night: true);
  });

  testWidgets('the scrub deck keeps the viewport as its page, and opening '
      'the deck neither rebuilds it nor presents again', (tester) async {
    open(showcaseBook('salt'));
    final deck = ValueNotifier<DeckView?>(null);
    addTearDown(deck.dispose);
    tester.view
      ..physicalSize = const Size(412, 671)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ScrubDeck(
          deck: deck,
          paper: const Color(0xfff6efe2),
          page: viewport(),
        ),
      ),
    );
    await settle(tester, () => pager().shown.value != null);
    final before = shown();
    final state = tester.state(find.byType(EpubViewport));

    final rebuilds = await rebuildsDuring(() async {
      deck.value = const DeckView(front: DeckCard.blank());
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    });

    expect(rebuilds, 0);
    expect(tester.state(find.byType(EpubViewport)), same(state));
    await settle(tester);
    expect(pager().shown.value, same(before));
  });

  group('the note view', () {
    /// The note of the note reference of [noteBook], laid out at [width],
    /// after the viewport shows the book's first page.
    Future<LaidNote> laidNote(WidgetTester tester, {double width = 412}) async {
      open(noteBook());
      await show(tester);
      await settle(tester, () => pager().shown.value != null);
      LaidNote? note;
      await finish(
        tester,
        pager()
            .note((href: 'text/s1.xhtml#note-1', noteref: true), width: width)
            .then((laid) => note = laid),
      );
      addTearDown(note!.dispose);
      return note!;
    }

    /// The point of [note]'s view at code unit [index] of the first text
    /// that holds [word].
    Offset pointIn(LaidNote note, String word, [int index = 0]) {
      final page = note.page;
      final text = page.dom.texts.firstWhere(
        (text) => text.text.contains(word),
      );
      final place = EpubPlace(
        page.section,
        text.order,
        text.text.indexOf(word) + index,
      );
      for (final piece in page.pieces) {
        for (var unit = 0; unit < piece.map.length; unit++) {
          if (piece.map.textPlaceAt(unit) != place) continue;
          return piece.paragraph
              .getBoxesForRange(unit, unit + 1)
              .first
              .toRect()
              .shift(Offset(piece.x, piece.y - page.top))
              .center;
        }
      }
      throw StateError('$word is not in the note.');
    }

    testWidgets('the note view is as tall as the note, and a screen reader '
        'reads its text block by block', (tester) async {
      final handle = tester.ensureSemantics();
      final note = await laidNote(tester, width: 300);
      await tester.pumpWidget(
        onScreen(
          Align(
            alignment: Alignment.topLeft,
            child: EpubNoteView(note: note, onCopy: (_) {}),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(EpubNoteView)),
        Size(300, note.page.height),
      );
      expect(
        find.semantics.byLabel('The lantern note explains the harbour.'),
        findsOneWidget,
      );
      expect(
        find.semantics.byLabel('Its second paragraph ends it.'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a long press selects a word of the note, and Copy reports '
        'it through onCopy', (tester) async {
      final note = await laidNote(tester);
      final copies = <String>[];
      await tester.pumpWidget(
        onScreen(
          Align(
            alignment: Alignment.topLeft,
            child: EpubNoteView(note: note, onCopy: copies.add),
          ),
        ),
      );

      await tester.longPressAt(pointIn(note, 'lantern', 2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copies, ['lantern']);
    });
  });
}
