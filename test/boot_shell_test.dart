import 'package:bookfin/main.dart';
import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'appearance/preferences_test.dart' show MemoryAppearanceStore;
import 'catalog/controller_test.dart'
    show MemoryCatalogStore, MemoryCredentials;

import 'package:bookfin/catalog/controller.dart';

void main() {
  testWidgets('Bookfin identifies itself before a library is connected', (
    tester,
  ) async {
    await tester.pumpWidget(
      BookfinApp(
        appearance: AppearanceController(MemoryAppearanceStore()),
        catalog: CatalogController(
          credentials: MemoryCredentials(),
          store: MemoryCatalogStore(),
        ),
      ),
    );

    expect(find.text('Bookfin'), findsOneWidget);
    expect(find.text('Your library starts here.'), findsOneWidget);
  });

  testWidgets('the setup shell does not pretend that books are available', (
    tester,
  ) async {
    await tester.pumpWidget(
      BookfinApp(
        appearance: AppearanceController(MemoryAppearanceStore()),
        catalog: CatalogController(
          credentials: MemoryCredentials(),
          store: MemoryCatalogStore(),
        ),
      ),
    );

    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets(
    'the app tries the kept copies of damaged records again only after its first frame',
    (tester) async {
      final sync = _RecoverySpy();
      await tester.pumpWidget(
        BookfinApp(
          appearance: AppearanceController(MemoryAppearanceStore()),
          catalog: CatalogController(
            credentials: MemoryCredentials(),
            store: MemoryCatalogStore(),
          ),
          sync: sync,
        ),
      );

      expect(sync.phases, [SchedulerPhase.postFrameCallbacks]);
      await tester.pump();
      expect(sync.phases, hasLength(1));
    },
  );
}

/// A record sync that notes the frame phase at each retry of kept copies.
class _RecoverySpy extends RecordSync {
  _RecoverySpy() : super(records: LocalResumeStore());
  final phases = <SchedulerPhase>[];

  @override
  Future<void> recoverKept() async =>
      phases.add(SchedulerBinding.instance.schedulerPhase);
}
