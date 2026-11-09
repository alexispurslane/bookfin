import 'package:bookfin/foundation/scrub_bar.dart';
import 'package:bookfin/reader/book_map.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'book_map_test.dart' show contents, threeSections;
import 'epub/helpers.dart' show loadReaderFont;
import 'epub/page_source_test.dart' show paragraphs;
import 'native_reader.dart';
import 'screen_test.dart' show ControlNavigator;
import 'session_native_test.dart' show navBook;
import 'session_test.dart' show source, edition, book;

void main() {
  final publication = threeSections();
  int size(String resource) => publication.resources[resource]!.length;
  final whole =
      size('OPS/one.xhtml') + size('OPS/two.xhtml') + size('OPS/three.xhtml');

  /// Where a place [progress] of the way through "two" sits in the book.
  double inTwo(double progress) =>
      (size('OPS/one.xhtml') + size('OPS/two.xhtml') * progress) / whole;

  /// [fraction] of the book as the place label names it, such as "37%".
  String percent(double fraction) => '${(fraction * 100).round()}%';

  /// A place [progress] of the way through "two", as the viewport reports
  /// it, on page [page] of 8 of the section.
  ReadingLocation inSectionTwo(double progress, {int page = 3}) =>
      ReadingLocation.fromJson({
        'cfi': 'epubcfi(/6/4!/4/2/1:0)',
        'resource': 'OPS/two.xhtml',
        'quote': '',
        'chapter': 'Two',
        'page': page,
        'pages': 8,
        'progress': progress,
      });

  /// Opens the three-section book with the reader's contents, shown on
  /// [navigator].
  Future<ReaderSession> openReader(ControlNavigator navigator) async {
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub');
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: (_) async => publication,
    );
    addTearDown(() {
      reader.dispose();
      downloads.dispose();
    });
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    reader.attachDocument(reader.token, navigator, contents);
    return reader;
  }

  Future<void> show(WidgetTester tester, ReaderSession reader) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  Slider bar(WidgetTester tester) => tester.widget<Slider>(find.byType(Slider));

  test('the session maps the open book once its contents arrive', () async {
    final reader = await openReader(ControlNavigator());
    await pumpEventQueue();
    final map = reader.bookMap!;
    expect(map.chapters.map((chapter) => chapter.title), [
      'One',
      'Two',
      'Half',
      'Three',
    ]);
    reader.closeView(reader.token);
    expect(reader.bookMap, isNull, reason: 'A closed book has no map.');
  });

  test('going to a scrub target shows that part of the book at that '
      'progress', () async {
    final navigator = ControlNavigator();
    final reader = await openReader(navigator);
    await pumpEventQueue();
    await reader.goTo(reader.bookMap!.targetAt(inTwo(.75)));
    expect(navigator.seeks.single.$1, 1);
    expect(navigator.seeks.single.$2, closeTo(.75, 1e-9));
  });

  test('a failed move to a scrub target keeps the place and says so', () async {
    final navigator = ControlNavigator()..failSeeks = true;
    final reader = await openReader(navigator);
    await pumpEventQueue();
    reader.acceptVisible(reader.token, inSectionTwo(.5));
    final kept = reader.position;
    await reader.goTo(reader.bookMap!.targetAt(.9));
    expect(reader.message, contains('Your saved place was kept'));
    expect(reader.position, kept);
  });

  testWidgets('the reader bar shows the open place in the whole book, with '
      'a tick at each chapter and a dot at each bookmark', (tester) async {
    final reader = await openReader(ControlNavigator());
    reader.acceptVisible(reader.token, inSectionTwo(.5));
    await reader.addBookmark();
    reader.acceptVisible(reader.token, inSectionTwo(.25));
    await show(tester, reader);
    expect(bar(tester).value, closeTo(inTwo(.25), 1e-9));
    expect(
      find.bySemanticsLabel('Two · ${percent(inTwo(.25))}'),
      findsOneWidget,
    );
    final marks = find.byKey(const ValueKey('position marks'));
    final width = tester.getSize(marks).width;
    // A tick is a rectangle and a bookmark is a circle, each centered at its
    // place along the bar.
    PaintPatternPredicate at(Symbol shape, double fraction) =>
        (method, arguments) =>
            method == shape &&
            ((shape == #drawRect
                                ? (arguments[0] as Rect).center
                                : arguments[0] as Offset)
                            .dx -
                        width * fraction)
                    .abs() <
                1e-6;
    expect(
      tester.renderObject(marks),
      paints
        ..something(at(#drawRect, inTwo(0)))
        ..something(at(#drawRect, inTwo(.5)))
        ..something(at(#drawRect, inTwo(1)))
        ..something(at(#drawCircle, inTwo(.5))),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a drag on the bar previews the target chapter and place '
      'without moving the book, and the release goes there', (tester) async {
    final navigator = ControlNavigator();
    final reader = await openReader(navigator);
    reader.acceptVisible(reader.token, inSectionTwo(.25));
    await show(tester, reader);
    final target = inTwo(.75);
    bar(tester).onChangeStart!(inTwo(.25));
    bar(tester).onChanged!(target);
    await tester.pump();
    expect(
      find.bySemanticsLabel('Half · ${(target * 100).round()}%'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Two · ${percent(inTwo(.25))}'), findsNothing);
    expect(navigator.seeks, isEmpty);
    expect(reader.visibleLocation!.progress, .25);

    bar(tester).onChangeEnd!(target);
    await tester.pumpAndSettle();
    expect(navigator.seeks.single.$1, 1);
    expect(navigator.seeks.single.$2, closeTo(.75, 1e-9));
    reader.acceptVisible(reader.token, inSectionTwo(.74, page: 7));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Two · ${percent(inTwo(.74))}'),
      findsOneWidget,
    );
    expect(bar(tester).value, closeTo(inTwo(.74), 1e-9));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a drag on the bar turns the page into a deck that draws the '
      'page under the thumb, and the release lands the reader there and '
      'closes the deck', (tester) async {
    final navigator = ControlNavigator();
    final reader = await openReader(navigator);
    reader.acceptVisible(reader.token, inSectionTwo(.25));
    await show(tester, reader);
    final front = find.byKey(const ValueKey('deck front card'));
    expect(front, findsNothing);
    bar(tester).onChangeStart!(inTwo(.25));
    await tester.pump();
    expect(front, findsOneWidget);
    expect(navigator.previews.single.$1, 1);
    expect(navigator.previews.single.$2, closeTo(.25, 1e-9));
    expect(navigator.previews.single.$3, greaterThan(0));
    bar(tester).onChanged!(inTwo(.75));
    await tester.pump();
    expect(navigator.seeks, isEmpty, reason: 'The book stays during the drag.');
    bar(tester).onChangeEnd!(inTwo(.75));
    await tester.pumpAndSettle();
    expect(navigator.seeks.single.$1, 1);
    expect(navigator.seeks.single.$2, closeTo(.75, 1e-9));
    expect(front, findsNothing);
    expect(reader.previews.deck.value, isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  test('closing the book ends a scrub and frees its deck', () async {
    final reader = await openReader(ControlNavigator());
    await pumpEventQueue();
    reader.previews.start(reader.bookMap!.targetAt(inTwo(.5)), width: 300);
    expect(reader.previews.deck.value, isNotNull);
    reader.closeView(reader.token);
    expect(reader.previews.deck.value, isNull);
  });

  testWidgets('the reader bar reports where a drag starts, each target and '
      'where it ends, as places in the book', (tester) async {
    final reader = await openReader(ControlNavigator());
    reader.acceptVisible(reader.token, inSectionTwo(.25));
    await tester.pump();
    final reports = <(String, BookTarget)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderScrubBar(
            reader: reader,
            previous: const SizedBox(),
            next: const SizedBox(),
            onScrubStart: (target) => reports.add(('start', target)),
            onScrubTarget: (target) => reports.add(('target', target)),
            onScrubEnd: (target) async => reports.add(('end', target)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final map = reader.bookMap!;
    bar(tester).onChangeStart!(inTwo(.25));
    bar(tester).onChanged!(inTwo(.75));
    bar(tester).onChangeEnd!(inTwo(.75));
    await tester.pumpAndSettle();
    expect(reports, [
      ('start', map.targetAt(inTwo(.25))),
      ('target', map.targetAt(inTwo(.75))),
      ('end', map.targetAt(inTwo(.75))),
    ]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a place saved before places had a progress sits at the start '
      'of its section', (tester) async {
    final reader = await openReader(ControlNavigator());
    reader.acceptVisible(
      reader.token,
      const ReadingLocation('epubcfi(/6/4!/4/2/1:0)', 'OPS/two.xhtml', ''),
    );
    await show(tester, reader);
    expect(bar(tester).value, closeTo(inTwo(0), 1e-9));
    expect(
      find.bySemanticsLabel('Two · ${percent(inTwo(0))}'),
      findsOneWidget,
      reason: 'The book map names the chapter of a place without a title.',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('the thumb at the start or the end of the book stays clear '
      'of the screen edges, where Android takes a drag as Back', (
    tester,
  ) async {
    // The emulator's gesture zone is 78 pixels at 2.625 pixels a point.
    tester.view.systemGestureInsets = FakeViewPadding(
      left: 30 * tester.view.devicePixelRatio,
      right: 30 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetSystemGestureInsets);
    final reader = await openReader(ControlNavigator());
    reader.acceptVisible(reader.token, inSectionTwo(0));
    await show(tester, reader);
    final track = tester.getRect(find.byType(Slider));
    final screen = tester.getSize(find.byType(ReaderScreen));
    // The thumb is 8 points wide on each side of its place.
    expect(track.left, greaterThanOrEqualTo(30 + 8));
    expect(screen.width - track.right, greaterThanOrEqualTo(30 + 8));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a long chapter title keeps the bar one height, so a drag does '
      'not resize the page above it', (tester) async {
    final reader = await openReader(ControlNavigator());
    reader.acceptVisible(reader.token, inSectionTwo(.25));
    await show(tester, reader);
    final height = tester.getSize(find.byType(ReaderScrubBar)).height;
    final long = 'A chapter title much too long for one line ' * 3;
    reader.acceptVisible(
      reader.token,
      ReadingLocation.fromJson({
        ...inSectionTwo(.25).toJson(),
        'chapter': long,
        'page': 3,
        'pages': 8,
      }),
    );
    await tester.pump();
    expect(tester.getSize(find.byType(ReaderScrubBar)).height, height);
    // A long title is cut short, but the separator and the place show whole.
    expect(find.textContaining('· ${percent(inTwo(.25))}'), findsOneWidget);
    bar(tester).onChangeStart!(inTwo(.25));
    bar(tester).onChanged!(inTwo(.25));
    await tester.pump();
    expect(tester.getSize(find.byType(ReaderScrubBar)).height, height);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  group('the scrub bar of a native book', () {
    setUpAll(loadReaderFont);

    /// The bar's place label as assistive technology reads it.
    String placeLabel(WidgetTester tester) => tester
        .widgetList<Semantics>(
          find.descendant(
            of: find.byType(ReaderScrubBar),
            matching: find.byType(Semantics),
          ),
        )
        .map((semantics) => semantics.properties.label)
        .nonNulls
        .firstWhere((label) => label.contains(' · '));

    List<double> ticks(WidgetTester tester) =>
        tester.widget<ScrubBar>(find.byType(ScrubBar)).chapters;

    testWidgets('the thumb does not move under the finger while a section is '
        'laid out', (tester) async {
      // Long titles give the last chapter many bytes and few pages, so its
      // estimate is far off until it is laid out, last.
      final reader = await openNative(
        tester,
        publication: Publication.admit(
          navBook(
            [
              '<h1 id="one">One</h1>${paragraphs(20)}',
              '<h1 id="two">Two</h1>${paragraphs(60, sentences: 10)}',
              '<h1 id="three">Three</h1>${paragraphs(60, sentences: 10)}',
              '<h1 id="four">Four</h1>'
                  '${'<p title="${'x' * 4000}">A short line.</p>' * 40}',
            ],
            [
              ('One', 'text/s0.xhtml#one'),
              ('Two', 'text/s1.xhtml#two'),
              ('Three', 'text/s2.xhtml#three'),
              ('Four', 'text/s3.xhtml#four'),
            ],
          ),
        ),
      );
      expect(reader.pager!.bookPages.value.complete, isFalse);
      final held = reader.bookMap!;
      final finger = held.fractionAt((part: 2, progress: .05));
      bar(tester).onChangeStart!(bar(tester).value);
      bar(tester).onChanged!(finger);
      await tester.pump();
      final label = placeLabel(tester);
      final marks = ticks(tester);

      await settleReader(
        tester,
        () => reader.pager!.bookPages.value.complete,
        reason: 'the book was not laid out during the drag',
      );
      expect(
        reader.bookMap!.targetAt(finger).chapter,
        isNot(held.targetAt(finger).chapter),
        reason: 'The laid-out book has another chapter under the finger.',
      );
      await tester.pump();

      expect(bar(tester).value, finger);
      expect(placeLabel(tester), label);
      expect(ticks(tester), marks);
      final target = held.targetAt(finger);
      bar(tester).onChangeEnd!(finger);
      await settleReader(
        tester,
        () => reader.pager!.shown.value!.page.section == target.part,
        reason: 'the reader did not land where the bar showed',
      );
      await settleReader(tester, () => reader.previews.deck.value == null);
      await tester.pump();
      expect(
        ticks(tester),
        isNot(marks),
        reason: 'After the drag the bar shows what is laid out.',
      );
      await closeNative(tester, reader);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('when every section is laid out, a drag names the page under '
        'the finger, and the release lands on that page', (tester) async {
      final reader = await openNative(tester);
      await settleReader(
        tester,
        () => reader.bookMap?.pages != null,
        reason: 'the book was never laid out',
      );
      final map = reader.bookMap!;
      final total = map.pages!;
      expect(total, greaterThan(3));
      final far = total - 1;
      final finger = (far - .5) / total;
      final chapter = map.targetAt(finger).chapter;
      expect(
        find.bySemanticsLabel('One · Page 1 of $total'),
        findsOneWidget,
        reason: 'The label names the shown page among the book\'s pages.',
      );

      bar(tester).onChangeStart!(bar(tester).value);
      bar(tester).onChanged!(finger);
      await tester.pump();
      expect(placeLabel(tester), '$chapter · Page $far of $total');
      expect(
        bar(tester).semanticFormatterCallback!(finger),
        '$chapter · Page $far of $total',
      );

      bar(tester).onChangeEnd!(finger);
      await settleReader(
        tester,
        () => reader.pager!.pageNumber.value?.number == far,
        reason: 'the reader did not land on the page that the bar named',
      );
      await settleReader(tester, () => reader.previews.deck.value == null);
      await tester.pump();
      expect(placeLabel(tester), endsWith('Page $far of $total'));
      expect(
        bar(tester).semanticFormatterCallback!(bar(tester).value),
        endsWith('Page $far of $total'),
        reason: 'The thumb names the shown page.',
      );
      await closeNative(tester, reader);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
