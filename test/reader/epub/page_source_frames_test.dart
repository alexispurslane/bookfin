// The page source's default scheduler runs layout steps as Flutter tasks
// between frames. While an animation runs, urgent steps go on, and idle
// steps wait without keeping the event loop busy. Idle steps go on after
// the animation ends. An idle step also gives way to any frame that is
// scheduled, so that a frame never waits for a row of idle steps. While the
// app is in the background, idle steps wait for the app to come back.
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

/// Observes real idle layout callbacks without changing their scheduling.
class LayoutSteps {
  int idle = 0;
  int idleWhileHeld = 0;

  void schedule(void Function() step, {required bool urgent}) {
    PageSource.scheduleBetweenFrames(() {
      if (!urgent) {
        idle++;
        final binding = SchedulerBinding.instance;
        if (binding.hasScheduledFrame || !binding.framesEnabled) {
          idleWhileHeld++;
        }
      }
      step();
    }, urgent: urgent);
  }
}

/// A widget that animates for as long as it is shown.
const animation = Center(child: CircularProgressIndicator());

/// A widget that asks for a new frame at the end of each frame, without an
/// animation, as a screen that changes at every frame does.
class Redraws extends StatefulWidget {
  const Redraws({super.key});

  @override
  State<Redraws> createState() => _RedrawsState();
}

class _RedrawsState extends State<Redraws> {
  int frames = 0;

  @override
  Widget build(BuildContext context) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => frames++);
    });
    return Text('$frames', textDirection: TextDirection.ltr);
  }
}

const frame = Duration(milliseconds: 16);

void main() {
  setUpAll(loadReaderFont);

  late PageSource source;
  late LayoutSteps steps;

  /// A page source with the default scheduler over one long section, and
  /// that section prepared.
  Future<PreparedSection> open(WidgetTester tester) async {
    steps = LayoutSteps();
    source = PageSource(book([paragraphs(200)]), schedule: steps.schedule)
      ..settings = readerPage;
    addTearDown(source.dispose);
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
    expect(steps.idle, 0);
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
    expect(steps.idleWhileHeld, 0);
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
    expect(steps.idle, 0);

    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 10 && !far(); i++) {
      await tester.pump(frame);
    }

    expect(far(), isTrue);
    await close(tester);
  });

  testWidgets('idle layout waits while the app is in the background, and '
      'goes on when the app comes back', (tester) async {
    final section = await open(tester);
    TaskPolls();
    final far = completes(source.pageAt(placeIn(section, .9), anchored: false));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(frame);
    }
    expect(far(), isFalse, reason: 'idle layout ran in the background');
    expect(steps.idle, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 10 && !far(); i++) {
      await tester.pump(frame);
    }

    expect(far(), isTrue);
    await close(tester);
  });

  testWidgets('idle layout gives way to each frame that is scheduled, and '
      'goes on once no frame is scheduled', (tester) async {
    final section = await open(tester);
    final polls = TaskPolls();
    final far = completes(source.pageAt(placeIn(section, .9), anchored: false));
    await tester.pumpWidget(const Redraws());
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(steps.idle, 0);
    final before = polls.count;
    const frames = 10;
    for (var i = 0; i < frames; i++) {
      final beforeStep = steps.idle;
      await tester.pump(frame);
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(steps.idle - beforeStep, lessThanOrEqualTo(1));
    }

    expect(polls.count - before, lessThanOrEqualTo(frames + 1));
    // A waiting idle callback can precede Redraws' next post-frame callback.
    // It may run then: the next frame has not been requested yet. Enough
    // such legal steps can finish this page, depending on layout speed.
    expect(steps.idle, greaterThan(0));
    expect(steps.idleWhileHeld, 0);

    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 10 && !far(); i++) {
      await tester.pump(frame);
    }
    expect(far(), isTrue);
    await close(tester);
  });

  testWidgets('idle work waits when each frame requests the next before '
      'its idle callback, then resumes when the requests stop', (tester) async {
    final steps = LayoutSteps();
    final polls = TaskPolls();
    var redraw = true;
    void afterFrame(Duration _) {
      if (!redraw) return;
      tester.binding.scheduleFrame();
      tester.binding.addPostFrameCallback(afterFrame);
    }

    // Register first so every held callback sees the next frame pending.
    tester.binding.addPostFrameCallback(afterFrame);
    addTearDown(() => redraw = false);
    var done = false;
    steps.schedule(() => done = true, urgent: false);
    await tester.pumpWidget(const SizedBox());
    final before = polls.count;
    for (var i = 0; i < 10; i++) {
      await tester.pump(frame);
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(steps.idle, 0);
      expect(done, isFalse);
    }
    expect(polls.count - before, lessThanOrEqualTo(11));

    redraw = false;
    await tester.pump(frame);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(steps.idle, 1);
    expect(steps.idleWhileHeld, 0);
    expect(done, isTrue);
  });

  testWidgets('idle work can finish before late redraw callbacks request '
      'another frame', (tester) async {
    final steps = LayoutSteps();
    var remaining = 3;
    void step() {
      remaining--;
      if (remaining > 0) steps.schedule(step, urgent: false);
    }

    steps.schedule(step, urgent: false);
    await tester.pumpWidget(const Redraws());
    expect(steps.idle, 0);
    for (var i = 0; i < 3; i++) {
      await tester.pump(frame);
      expect(steps.idle, i + 1);
      expect(steps.idleWhileHeld, 0);
      expect(tester.binding.hasScheduledFrame, isTrue);
    }
    expect(remaining, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
