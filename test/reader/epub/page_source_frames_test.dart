// The page source's default scheduler runs layout steps as Flutter tasks
// between frames. While an animation runs, urgent steps go on, and idle
// steps wait without keeping the event loop busy. Idle steps go on after
// the animation ends.
import 'dart:async';

import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'page_source_test.dart' show book, paragraphs, placeIn;

/// The number of times that Flutter's task queue asked whether its first
/// task could run.
///
/// Each ask is one wakeup of the event loop for the queue. After [limit]
/// asks, every task may run, so that a busy loop under the test clock ends
/// and the test fails on the count instead of hanging.
class TaskPolls {
  TaskPolls({this.limit = 1000}) {
    final binding = SchedulerBinding.instance;
    final previous = binding.schedulingStrategy;
    binding.schedulingStrategy =
        ({required int priority, required SchedulerBinding scheduler}) {
          count++;
          return count > limit ||
              defaultSchedulingStrategy(
                priority: priority,
                scheduler: scheduler,
              );
        };
    addTearDown(() => binding.schedulingStrategy = previous);
  }

  final int limit;
  int count = 0;
}

/// A widget that animates for as long as it is shown.
const animation = Center(child: CircularProgressIndicator());

const frame = Duration(milliseconds: 16);

void main() {
  setUpAll(loadReaderFont);

  late PageSource source;

  /// A page source with the default scheduler over one long section, and
  /// that section prepared.
  Future<PreparedSection> open(WidgetTester tester) async {
    source = PageSource(book([paragraphs(200)]))..settings = readerPage;
    return (await tester.runAsync(() => source.section(0)))!;
  }

  /// Ends the animation, disposes the source and lets its last steps run,
  /// which then do nothing.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    source.dispose();
    for (var i = 0; i < 3; i++) {
      await tester.pump(frame);
    }
  }

  /// Whether [future] completed.
  bool Function() completes(Future<Object?> future) {
    var done = false;
    unawaited(future.then((_) => done = true, onError: (_) => done = true));
    return () => done;
  }

  testWidgets('while an animation runs, idle layout wakes the event loop at '
      'most once a frame', (tester) async {
    final section = await open(tester);
    final polls = TaskPolls();
    // The true page deep in the section needs many idle main-run steps.
    final far = completes(source.pageAt(placeIn(section, .9), anchored: false));

    await tester.pumpWidget(animation);
    final before = polls.count;
    const frames = 10;
    for (var i = 0; i < frames; i++) {
      await tester.pump(frame);
    }

    expect(polls.count - before, lessThanOrEqualTo(frames + 1));
    expect(far(), isFalse, reason: 'idle layout ran during the animation');
    await close(tester);
  });

  testWidgets('urgent layout goes on while an animation runs', (tester) async {
    final section = await open(tester);
    TaskPolls();
    await tester.pumpWidget(animation);
    await tester.pump(frame);

    final shown = completes(
      source.pageAt(placeIn(section, .8), anchored: true, urgent: true),
    );
    for (var i = 0; i < 10 && !shown(); i++) {
      await tester.pump(frame);
    }

    expect(shown(), isTrue);
    await close(tester);
  });

  testWidgets('idle layout that waited during an animation goes on after '
      'the animation ends', (tester) async {
    final section = await open(tester);
    TaskPolls();
    final far = completes(source.pageAt(placeIn(section, .9), anchored: false));
    await tester.pumpWidget(animation);
    for (var i = 0; i < 5; i++) {
      await tester.pump(frame);
    }
    expect(far(), isFalse, reason: 'idle layout ran during the animation');

    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 10 && !far(); i++) {
      await tester.pump(frame);
    }

    expect(far(), isTrue);
    await close(tester);
  });
}
