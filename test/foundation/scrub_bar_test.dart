import 'dart:async';

import 'package:bookfin/foundation/scrub_bar.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The scrub bar is drawn alone, with no book or edition behind it. It can
/// only show the places that it gets and report what the person did.
void main() {
  Future<void> show(WidgetTester tester, Widget bar) => tester.pumpWidget(
    MaterialApp(
      theme: bookfinTheme(Brightness.light),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: 400, child: bar),
        ),
      ),
    ),
  );

  Slider slider(WidgetTester tester) =>
      tester.widget<Slider>(find.byType(Slider));

  testWidgets('a drag reports where it starts, each place that it passes and '
      'where it ends, and shows the dragged place until the end lands', (
    tester,
  ) async {
    final reports = <String>[];
    final landed = Completer<void>();
    await show(
      tester,
      ScrubBar(
        value: .1,
        chapters: const [],
        bookmarks: const [],
        describe: (fraction) => '$fraction',
        onStart: (fraction) => reports.add('start $fraction'),
        onTarget: (fraction) => reports.add('target $fraction'),
        onEnd: (fraction) {
          reports.add('end $fraction');
          return landed.future;
        },
        below: (context, target) => Text('under ${target ?? 'open place'}'),
      ),
    );
    expect(find.text('under open place'), findsOneWidget);
    slider(tester).onChangeStart!(.2);
    slider(tester).onChanged!(.4);
    slider(tester).onChanged!(.6);
    await tester.pump();
    expect(reports, ['start 0.2', 'target 0.4', 'target 0.6']);
    expect(slider(tester).value, .6);
    expect(find.text('under 0.6'), findsOneWidget);

    slider(tester).onChangeEnd!(.6);
    await tester.pump();
    expect(reports.last, 'end 0.6');
    expect(slider(tester).value, .6, reason: 'The end has not landed yet.');

    landed.complete();
    await tester.pumpAndSettle();
    expect(slider(tester).value, .1);
    expect(find.text('under open place'), findsOneWidget);
  });

  testWidgets('the bar draws a tick at each chapter start and a dot at each '
      'bookmark, where they are along the whole', (tester) async {
    await show(
      tester,
      ScrubBar(
        value: 0,
        chapters: const [0, .5],
        bookmarks: const [.25],
        describe: (fraction) => '$fraction',
        onEnd: (_) async {},
      ),
    );
    final marks = find.byKey(const ValueKey('position marks'));
    final Size(:width, :height) = tester.getSize(marks);
    expect(width, tester.getSize(find.byType(Slider)).width);
    // A chapter at the very start has no tick, because the bar starts there.
    expect(
      tester.renderObject(marks),
      paints
        ..rect(rect: Rect.fromLTWH(width / 2 - .75, height / 2 - 5, 1.5, 10))
        ..circle(x: width / 4),
    );
    expect(
      tester.renderObject(marks),
      isNot(
        paints
          ..rect()
          ..rect(),
      ),
    );
  });

  testWidgets('chapter ticks closer together than the bar can show apart '
      'draw as one tick', (tester) async {
    await show(
      tester,
      ScrubBar(
        value: 0,
        chapters: [for (var index = 1; index < 400; index++) index / 400],
        bookmarks: const [],
        describe: (fraction) => '$fraction',
        onEnd: (_) async {},
      ),
    );
    final marks = find.byKey(const ValueKey('position marks'));
    final width = tester.getSize(marks).width;
    // Ticks one point apart would draw a solid band. At least four points
    // separate the ticks that the bar draws.
    var painted = 0;
    final canvas = tester.renderObject(marks);
    expect(
      canvas,
      paints..everything((method, arguments) {
        if (method == #drawRect) painted++;
        return true;
      }),
    );
    expect(painted, lessThanOrEqualTo(width ~/ 4 + 1));
    expect(painted, greaterThan(width ~/ 8));
  });

  testWidgets('the bar describes the dragged place to assistive technology', (
    tester,
  ) async {
    await show(
      tester,
      ScrubBar(
        value: .5,
        chapters: const [],
        bookmarks: const [],
        describe: (fraction) => '${(fraction * 100).round()} percent',
        onEnd: (_) async {},
      ),
    );
    expect(slider(tester).semanticFormatterCallback!(.5), '50 percent');
  });
}
