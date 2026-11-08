import 'package:bookfin/reader/book_map.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'book_map_test.dart' show contents, threeSections;
import 'screen_test.dart' show ControlPort;
import 'session_test.dart' show source, edition, book;

void main() {
  final publication = threeSections();
  int size(String resource) => publication.resources[resource]!.length;
  final whole =
      size('OPS/one.xhtml') + size('OPS/two.xhtml') + size('OPS/three.xhtml');

  /// Where a place [progress] of the way through "two" sits in the book.
  double inTwo(double progress) =>
      (size('OPS/one.xhtml') + size('OPS/two.xhtml') * progress) / whole;

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
  /// [port].
  Future<ReaderSession> openReader(ControlPort port) async {
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
    reader.attach(reader.token, port, contents);
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
    final reader = await openReader(ControlPort());
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
    final port = ControlPort();
    final reader = await openReader(port);
    await pumpEventQueue();
    await reader.goTo(reader.bookMap!.targetAt(inTwo(.75)));
    expect(port.seeks.single.$1, 1);
    expect(port.seeks.single.$2, closeTo(.75, 1e-9));
  });

  test('a failed move to a scrub target keeps the place and says so', () async {
    final port = ControlPort()..failSeeks = true;
    final reader = await openReader(port);
    await pumpEventQueue();
    reader.acceptVisible(reader.token, inSectionTwo(.5));
    final kept = reader.position;
    await reader.goTo(reader.bookMap!.targetAt(.9));
    expect(reader.message, contains('Your saved place was kept'));
    expect(reader.position, kept);
  });

  testWidgets('the reader bar shows the open place in the whole book, with '
      'a tick at each chapter and a dot at each bookmark', (tester) async {
    final reader = await openReader(ControlPort());
    reader.acceptVisible(reader.token, inSectionTwo(.5));
    await reader.addBookmark();
    reader.acceptVisible(reader.token, inSectionTwo(.25));
    await show(tester, reader);
    expect(bar(tester).value, closeTo(inTwo(.25), 1e-9));
    expect(find.text('Two · Page 3 of 8'), findsOneWidget);
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
    final port = ControlPort();
    final reader = await openReader(port);
    reader.acceptVisible(reader.token, inSectionTwo(.25));
    await show(tester, reader);
    final target = inTwo(.75);
    bar(tester).onChangeStart!(inTwo(.25));
    bar(tester).onChanged!(target);
    await tester.pump();
    expect(find.text('Half · ${(target * 100).round()}%'), findsOneWidget);
    expect(find.text('Two · Page 3 of 8'), findsNothing);
    expect(port.seeks, isEmpty);
    expect(reader.visibleLocation!.progress, .25);

    bar(tester).onChangeEnd!(target);
    await tester.pumpAndSettle();
    expect(port.seeks.single.$1, 1);
    expect(port.seeks.single.$2, closeTo(.75, 1e-9));
    reader.acceptVisible(reader.token, inSectionTwo(.74, page: 7));
    await tester.pumpAndSettle();
    expect(find.text('Two · Page 7 of 8'), findsOneWidget);
    expect(bar(tester).value, closeTo(inTwo(.74), 1e-9));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('the reader bar reports where a drag starts, each target and '
      'where it ends, as places in the book', (tester) async {
    final reader = await openReader(ControlPort());
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
    final reader = await openReader(ControlPort());
    reader.acceptVisible(
      reader.token,
      const ReadingLocation('epubcfi(/6/4!/4/2/1:0)', 'OPS/two.xhtml', ''),
    );
    await show(tester, reader);
    expect(bar(tester).value, closeTo(inTwo(0), 1e-9));
    expect(find.textContaining('Page progress unavailable'), findsOneWidget);
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
    final reader = await openReader(ControlPort());
    reader.acceptVisible(reader.token, inSectionTwo(0));
    await show(tester, reader);
    final track = tester.getRect(find.byType(Slider));
    final screen = tester.getSize(find.byType(ReaderScreen));
    // The thumb is 8 points wide on each side of its place.
    expect(track.left, greaterThanOrEqualTo(30 + 8));
    expect(screen.width - track.right, greaterThanOrEqualTo(30 + 8));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
