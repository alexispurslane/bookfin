// A screen reader reads the shown page through the viewport's semantics: one
// node for each text block on the page, in reading order, with the book's
// own text. Headings are headers, links and images are nodes of their own,
// and the page's scroll actions turn pages. A test scheduler runs the page
// source's layout steps, and real time lets the workers finish.
import 'dart:async';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/epub/viewport.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'helpers.dart';
import 'page_source_test.dart' show TestScheduler, book, paragraphs;
import 'pager_test.dart' show linkedBook, showcaseBook;

/// A small red PNG.
List<int> _square() => img.encodePng(
  img.Image(width: 40, height: 40)..clear(img.ColorRgb8(200, 40, 40)),
);

/// A hyphenated English book with long words, and one word that holds the
/// book's own soft hyphen.
Publication _hyphenatedBook() => book(
  [
    '<p>${List.filled(12, 'The extraordinarily characteristic '
    'responsibilities of incomprehensibility unquestionably '
    'overwhelmed the co­operation of the harbour.').join(' ')}</p>',
  ],
  css: 'p { hyphens: auto; text-align: justify }',
  language: 'en',
);

void main() {
  setUpAll(loadReaderFont);

  late TestScheduler scheduler;
  late PageSource source;
  EpubPager? opened;
  final turns = <bool>[];
  final links = <String>[];
  var taps = 0;

  EpubPager pager() => opened!;
  ShownPage shown() => pager().shown.value!;

  void open(Publication publication) {
    source = PageSource(publication, schedule: scheduler.schedule);
    opened = EpubPager(
      EpubDocument(publication),
      onPlace: (_) {},
      onWarning: (_) {},
      source: source,
    );
  }

  setUp(() {
    scheduler = TestScheduler();
    turns.clear();
    links.clear();
    taps = 0;
  });
  tearDown(() {
    opened?.dispose();
    opened = null;
  });

  /// Shows the viewport alone on a screen of [size] logical pixels.
  Future<void> show(
    WidgetTester tester, {
    double fontSize = 20,
    Size size = const Size(412, 671),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      onScreen(
        EpubViewport(
          pager: pager(),
          fontSize: fontSize,
          night: false,
          onTap: () => taps++,
          onTurn: turns.add,
          onLink: links.add,
          onCopy: (_) {},
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
      if ((done?.call() ?? true) && quiet >= 10) return;
    }
    fail('The pager did not settle.');
  }

  /// Opens [publication] in a viewport and waits for its first page.
  Future<void> read(
    WidgetTester tester,
    Publication publication, {
    Size size = const Size(412, 671),
  }) async {
    open(publication);
    await show(tester, size: size);
    await settle(tester, () => pager().shown.value != null);
  }

  /// Runs [work] to its end (see [settle]).
  Future<void> finish(WidgetTester tester, Future<void> work) async {
    var ended = false;
    unawaited(work.whenComplete(() => ended = true));
    await settle(tester, () => ended);
    await work;
  }

  /// The page's semantics node: the one that turns pages.
  SemanticsNode pageNode(WidgetTester tester) {
    SemanticsNode? found;
    bool visit(SemanticsNode node) {
      if (node.getSemanticsData().hasAction(SemanticsAction.scrollLeft)) {
        found = node;
        return false;
      }
      node.visitChildren(visit);
      return found == null;
    }

    visit(tester.getSemantics(find.byType(EpubViewport)));
    expect(found, isNotNull, reason: 'No semantics node turns pages.');
    return found!;
  }

  List<SemanticsNode> inOrder(SemanticsNode node) =>
      node.debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder);

  /// The nodes that a screen reader reads in [node], in reading order.
  List<SemanticsNode> readable(SemanticsNode node) => [
    if (node.getSemanticsData().label.isNotEmpty) node,
    for (final child in inOrder(node)) ...readable(child),
  ];

  /// The page's text blocks and images, in reading order.
  List<SemanticsNode> blocks(WidgetTester tester) {
    final found = inOrder(pageNode(tester));
    expect(found, isNotEmpty, reason: 'The page node has no text blocks.');
    return found;
  }

  /// What a screen reader reads in [node], one label after the other.
  String spoken(SemanticsNode node) =>
      readable(node).map((node) => node.getSemanticsData().label).join(' ');

  bool isImage(SemanticsNode node) =>
      node.getSemanticsData().flagsCollection.isImage;

  /// The text that the page reads, without white space and without images.
  String readText(WidgetTester tester) => [
    for (final block in blocks(tester))
      for (final node in readable(block))
        if (!isImage(node)) node.getSemanticsData().label,
  ].join().replaceAll(RegExp(r'\s'), '');

  /// The visible characters of the book's text on [page], from its DOM,
  /// without the book's soft hyphens.
  String pageText(LaidPage page) {
    final visible = StringBuffer();
    for (final text in source.sectionOf(page).dom.texts) {
      for (final unit in text.text.codeUnits) {
        if (!isSpace(unit)) visible.writeCharCode(unit);
      }
    }
    return visible
        .toString()
        .substring(page.startVisible, page.endVisible)
        .replaceAll('­', '');
  }

  /// The text of [element] in the book, with its white space collapsed.
  String textOf(DomElement element) => element.texts
      .map((text) => text.text)
      .join()
      .replaceAll(RegExp(r'\s+'), ' ');

  testWidgets('the page has one node for each text block on it, in reading '
      'order, and each holds the text of its block\'s lines on this page and '
      'nothing else', (tester) async {
    final handle = tester.ensureSemantics();
    await read(tester, book([paragraphs(6)]));
    final page = shown().page;
    final dom = source.sectionOf(page).dom;
    final texts = [
      for (final element in dom.body.elements)
        if (element.name == 'p') textOf(element),
    ];

    final labels = [
      for (final block in blocks(tester)) block.getSemanticsData().label,
    ];

    expect(labels, hasLength(greaterThan(1)));
    expect(page.last, isFalse, reason: 'The last block goes on.');
    // Each block's text is the start, the whole or the end of one paragraph,
    // and the blocks follow the paragraphs in order.
    for (final (index, label) in labels.indexed) {
      expect(texts[index], contains(label));
    }
    expect(texts.first, labels.first);
    expect(texts[labels.length - 1], startsWith(labels.last));
    expect(texts[labels.length - 1], isNot(labels.last));
    expect(readText(tester), pageText(page));
    handle.dispose();
  });

  testWidgets('a heading is a header node', (tester) async {
    final handle = tester.ensureSemantics();
    await read(tester, linkedBook());

    final heading = blocks(tester).first.getSemanticsData();

    expect(heading.label, 'Start');
    expect(heading.flagsCollection.isHeader, isTrue);
    expect(
      blocks(tester)[1].getSemanticsData().flagsCollection.isHeader,
      isFalse,
    );
    handle.dispose();
  });

  testWidgets('a link is a node of its own in its block, and its tap calls '
      'onLink with its destination and not onTap', (tester) async {
    final handle = tester.ensureSemantics();
    await read(tester, linkedBook());
    final block = blocks(tester)[1];
    final parts = readable(block);

    expect(parts.map((node) => node.getSemanticsData().label), [
      'Before the link.',
      'Follow the lantern',
      'after the link.',
    ]);
    final link = parts[1];
    expect(link.getSemanticsData().flagsCollection.isLink, isTrue);
    expect(parts[0].getSemanticsData().flagsCollection.isLink, isFalse);

    link.owner!.performAction(link.id, SemanticsAction.tap);

    expect(links, ['text/s1.xhtml#target']);
    expect(taps, 0);
    handle.dispose();
  });

  testWidgets('an image is a node labeled with its alt text, and an image '
      'without alt text is labeled Image', (tester) async {
    final handle = tester.ensureSemantics();
    await read(
      tester,
      book(
        [
          '<p>A map follows.</p>'
              '<img src="../images/map.png" alt="A map of the harbour" '
              'style="display:block;width:40px"/>'
              '<p>The pier <img src="../images/map.png" alt="a red flag" '
              'style="width:20px"/> stands.</p>'
              '<img src="../images/map.png" style="display:block;width:40px"/>',
        ],
        files: {'images/map.png': _square()},
      ),
    );

    final heard = [
      for (final block in blocks(tester))
        for (final node in readable(block))
          (node.getSemanticsData().label, isImage(node)),
    ];

    expect(heard, [
      ('A map follows.', false),
      ('A map of the harbour', true),
      ('The pier', false),
      ('a red flag', true),
      ('stands.', false),
      ('Image', true),
    ]);
    handle.dispose();
  });

  testWidgets('the scroll left action asks for the next page, and scroll '
      'right for the previous one', (tester) async {
    final handle = tester.ensureSemantics();
    await read(tester, linkedBook());
    final page = pageNode(tester);

    page.owner!.performAction(page.id, SemanticsAction.scrollLeft);
    page.owner!.performAction(page.id, SemanticsAction.scrollRight);

    expect(turns, [true, false]);
    expect(taps, 0);
    handle.dispose();
  });

  testWidgets('after a turn, the nodes hold the new page\'s text, without a '
      'rebuild of the viewport', (tester) async {
    final handle = tester.ensureSemantics();
    await read(tester, showcaseBook('salt'));
    final first = shown().page;
    final before = readText(tester);
    var rebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is EpubViewport ||
          element.findAncestorWidgetOfExactType<EpubViewport>() != null) {
        rebuilds++;
      }
    };
    try {
      await finish(tester, pager().move(true));
    } finally {
      debugOnRebuildDirtyWidget = null;
    }

    expect(shown().page, isNot(same(first)));
    expect(rebuilds, 0);
    expect(readText(tester), isNot(before));
    expect(readText(tester), pageText(shown().page));
    handle.dispose();
  });

  testWidgets('at twice the text size, the page lays out again and the nodes '
      'hold the new page\'s text', (tester) async {
    final handle = tester.ensureSemantics();
    await read(tester, showcaseBook('salt'));
    final before = readText(tester);

    await show(tester, fontSize: 40);
    await settle(tester, () => shown().page.settings.fontSize == 40);

    expect(readText(tester), isNot(before));
    expect(before, startsWith(readText(tester)));
    expect(readText(tester), pageText(shown().page));
    handle.dispose();
  });

  testWidgets('a hyphenated word and a word with the book\'s own soft hyphen '
      'read whole, without the hyphens that layout draws', (tester) async {
    final handle = tester.ensureSemantics();
    await read(tester, _hyphenatedBook(), size: const Size(240, 671));
    final page = shown().page;
    final dom = source.sectionOf(page).dom;
    // Some line ends inside a word, at a hyphen that layout drew.
    final split = page.slices.any((line) {
      final piece = line.piece;
      if (piece == null) return false;
      final place = piece.map.textPlaceAt(line.units.$2 - 1);
      final text = place == null ? null : dom.textAt(place)?.text;
      return text != null &&
          place!.offset + 1 < text.length &&
          RegExp('[a-z]').hasMatch(text[place.offset + 1]);
    });
    expect(split, isTrue, reason: 'No line of the page breaks in a word.');

    final text = spoken(blocks(tester).single);

    expect(text, isNot(matches(RegExp('[­‐⁠]'))));
    expect(text, contains('incomprehensibility unquestionably'));
    expect(text, contains('the cooperation of'));
    expect(readText(tester), pageText(page));
    handle.dispose();
  });

  testWidgets('raised text, such as a note number, reads in its place', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await read(
      tester,
      book([
        '<p>The tide rose<sup>2</sup> at dawn.</p>'
            '<p>The boats came home.<sup>3</sup></p>',
      ]),
    );

    expect(blocks(tester).map(spoken), [
      'The tide rose2 at dawn.',
      'The boats came home.3',
    ]);
    handle.dispose();
  });

  testWidgets('a paragraph with a hanging first line is one node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final verse =
        'Out past the breakwater the lantern swung, and every boat that '
        'heard the bell came home before the tide.';
    await read(
      tester,
      book([
        '<p class="verse">$verse</p><p>The pier stood.</p>',
      ], css: '.verse { text-indent: -2em; margin-left: 2em }'),
    );

    expect(blocks(tester).map(spoken), [verse, 'The pier stood.']);
    handle.dispose();
  });

  testWidgets('each table cell is a node, cell by cell', (tester) async {
    final handle = tester.ensureSemantics();
    await read(
      tester,
      book([
        '<table><tr><td>North pier</td><td>South pier</td></tr>'
            '<tr><td>Old light</td><td>New light</td></tr></table>',
      ]),
    );

    expect(blocks(tester).map(spoken), [
      'North pier',
      'South pier',
      'Old light',
      'New light',
    ]);
    handle.dispose();
  });
}
