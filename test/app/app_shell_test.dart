import 'dart:async';

import 'package:bookfin/appearance/appearance.dart';
import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/catalog/covers.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/screen.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/main.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../appearance/preferences_test.dart' show MemoryAppearanceStore;
import '../foundation_test.dart' show disconnectedCatalog;
import '../playback/playback_test.dart' show MemoryResume, TestEngine;
import '../downloads/verified_reads.dart';

/// A clock that starts at [start] and moves with the test's fake time.
DateTime Function() fakeClock(WidgetTester tester, DateTime start) {
  final base = tester.binding.clock.now();
  return () => start.add(tester.binding.clock.now().difference(base));
}

/// How many times each widget type rebuilt while [during] ran.
Future<Map<Type, int>> rebuildsDuring(Future<void> Function() during) async {
  final counts = <Type, int>{};
  debugOnRebuildDirtyWidget = (element, _) => counts.update(
    element.widget.runtimeType,
    (count) => count + 1,
    ifAbsent: () => 1,
  );
  try {
    await during();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return counts;
}

/// Pumps one frame for each minute of [minutes], as a phone that shows the
/// app draws a frame whenever something changes.
Future<void> pumpMinutes(WidgetTester tester, int minutes) async {
  for (var minute = 0; minute < minutes; minute++) {
    await tester.pump(const Duration(minutes: 1));
  }
}

Brightness _brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first)).brightness;

final _newYork = SelectedLocation('New York', 40.7128, -74.0060);

class _Downloads extends Downloads with VerifiedReads {
  _Downloads() : super(MediaPolicy());
  @override
  bool get supported => true;
  @override
  Future<void> bind(JellyfinSession? session, List<Book> books) async {}
  @override
  EditionDownload status(Edition edition) => const EditionDownload();
  @override
  Future<void> request(Edition edition) async {}
  @override
  Future<void> cancel(Edition edition) async {}
  @override
  Future<void> remove(Edition edition) async {}
  @override
  Future<Uri?> localFile(SourceFile source) async => null;
  @override
  Future<void> get idle async {}
  @override
  void checkInvariants() {}
}

void main() {
  group('the theme', () {
    /// Shows the signed-out app with automatic appearance in New York, on a
    /// clock that starts at [start].
    Future<AppearanceController> show(
      WidgetTester tester,
      DateTime start,
    ) async {
      final appearance = AppearanceController(
        MemoryAppearanceStore(),
        clock: fakeClock(tester, start),
      );
      await appearance.selectLocation(_newYork);
      await tester.pumpWidget(
        BookfinApp(appearance: appearance, catalog: disconnectedCatalog()),
      );
      await tester.pumpAndSettle();
      return appearance;
    }

    testWidgets(
      'thirty minutes without a sunrise or sunset rebuild nothing above the tab pages',
      (tester) async {
        // New York, 12:00 local time on the March equinox.
        await show(tester, DateTime.utc(2026, 3, 20, 16));
        final rebuilds = await rebuildsDuring(() => pumpMinutes(tester, 30));
        expect(rebuilds[MaterialApp], isNull);
        expect(rebuilds[CatalogHome], isNull);
      },
    );

    testWidgets('a passed sunset rebuilds the theme once', (tester) async {
      // New York sets at about 23:10 UTC on the March equinox.
      await show(tester, DateTime.utc(2026, 3, 20, 22, 55));
      expect(_brightness(tester), Brightness.light);
      final rebuilds = await rebuildsDuring(() => pumpMinutes(tester, 30));
      await tester.pumpAndSettle();
      expect(rebuilds[MaterialApp], 1);
      expect(_brightness(tester), Brightness.dark);
    });

    testWidgets('an appearance save does not rebuild the app', (tester) async {
      final appearance = await show(tester, DateTime.utc(2026, 3, 20, 16));
      final rebuilds = await rebuildsDuring(() async {
        await appearance.selectLocation(_newYork);
        await tester.pump();
      });
      expect(appearance.saveState, PreferenceSaveState.saved);
      expect(rebuilds[MaterialApp], isNull);
    });

    testWidgets('a hidden app sets no timer for the next sunset', (
      tester,
    ) async {
      final appearance = await show(tester, DateTime.utc(2026, 3, 20, 16));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      final changes = <AppearanceDecision>[];
      void record() => changes.add(appearance.decision.value);
      appearance.decision.addListener(record);
      await tester.pump(const Duration(hours: 12));
      appearance.decision.removeListener(record);
      expect(changes, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      // 04:00 in New York is after sunset.
      expect(_brightness(tester), Brightness.dark);
    });
  });

  group('startup', () {
    test(
      'starts every independent restore before the first one completes',
      () async {
        final started = <String>[];
        final release = Completer<void>();
        Future<T> step<T>(String name, T value) async {
          started.add(name);
          await release.future;
          return value;
        }

        final downloads = _Downloads();
        final playback = Playback(
          downloads: downloads,
          engine: TestEngine(),
          store: MemoryResume(),
        );
        final opening = openSources(
          restoreAppearance: () => step('appearance', null),
          restoreLayout: () => step('layout', null),
          openDownloads: () => step<Downloads?>('downloads', downloads),
          openPlayback: (_) => step('playback', playback),
          openCovers: () => step<Covers?>('covers', null),
        );
        await pumpEventQueue();
        expect(
          started,
          unorderedEquals(['appearance', 'layout', 'downloads', 'covers']),
        );
        release.complete();
        final sources = await opening;
        expect(started.last, 'playback');
        expect(sources.downloads, same(downloads));
        expect(sources.playback, same(playback));
        await playback.close();
        downloads.dispose();
      },
    );

    test('Playback opens only after Downloads is ready', () async {
      final ready = Completer<Downloads?>();
      var playbackStarted = false;
      final downloads = _Downloads();
      final playback = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: MemoryResume(),
      );
      final opening = openSources(
        restoreAppearance: () async {},
        restoreLayout: () async {},
        openDownloads: () => ready.future,
        openPlayback: (given) async {
          expect(given, same(downloads));
          playbackStarted = true;
          return playback;
        },
        openCovers: () async => null,
      );
      await pumpEventQueue();
      expect(playbackStarted, isFalse);
      ready.complete(downloads);
      await opening;
      expect(playbackStarted, isTrue);
      await playback.close();
      downloads.dispose();
    });
  });
}
