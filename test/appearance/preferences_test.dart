import 'dart:async';

import 'package:bookfin/appearance/appearance.dart';
import 'package:bookfin/appearance/preferences.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryAppearanceStore implements AppearanceStore {
  String? value;
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String next) async {
    await gate?.future;
    if (fail) throw StateError('Storage unavailable');
    value = next;
  }
}

void main() {
  test(
    'manual appearance and selected location survive a new controller',
    () async {
      final store = MemoryAppearanceStore();
      final controller = AppearanceController(store);
      await controller.selectLocation(
        SelectedLocation('Tromsø', 69.6492, 18.9553),
      );
      await controller.selectMode(AppearanceMode.night);
      final reopened = AppearanceController(store);
      await reopened.restore();
      expect(reopened.settings.mode, AppearanceMode.night);
      expect(reopened.settings.location?.name, 'Tromsø');
      expect(reopened.settings.location?.latitude, 69.6492);
      expect(reopened.settings.location?.longitude, 18.9553);
    },
  );

  test('returning to automatic uses the retained location', () async {
    final controller = AppearanceController(MemoryAppearanceStore());
    await controller.selectLocation(
      SelectedLocation('Tokyo', 35.6762, 139.6503),
    );
    await controller.selectMode(AppearanceMode.day);
    await controller.selectMode(AppearanceMode.automatic);
    expect(controller.settings.location?.name, 'Tokyo');
    expect(controller.settings.mode, AppearanceMode.automatic);
  });

  test('removing the location persists the system fallback', () async {
    final store = MemoryAppearanceStore();
    final controller = AppearanceController(store);
    await controller.selectLocation(
      SelectedLocation('Tokyo', 35.6762, 139.6503),
    );
    await controller.selectLocation(null);
    final reopened = AppearanceController(store);
    await reopened.restore();
    expect(reopened.settings.location, isNull);
    expect(reopened.warning, isNull);
  });

  test(
    'rapid selections save in order and keep the newest choice visible',
    () async {
      final store = MemoryAppearanceStore()..gate = Completer<void>();
      final controller = AppearanceController(store);
      final first = controller.selectMode(AppearanceMode.day);
      final second = controller.selectMode(AppearanceMode.night);
      expect(controller.settings.mode, AppearanceMode.night);
      expect(controller.saveState, PreferenceSaveState.saving);
      store.gate!.complete();
      await Future.wait([first, second]);
      final reopened = AppearanceController(store);
      await reopened.restore();
      expect(reopened.settings.mode, AppearanceMode.night);
      expect(controller.saveState, PreferenceSaveState.saved);
    },
  );

  test(
    'failed writes expose an unsaved choice and a later choice retries',
    () async {
      final store = MemoryAppearanceStore()..fail = true;
      final controller = AppearanceController(store);
      await controller.selectMode(AppearanceMode.night);
      expect(controller.settings.mode, AppearanceMode.night);
      expect(controller.saveState, PreferenceSaveState.failed);
      expect(controller.warning, contains('not saved'));
      store.fail = false;
      await controller.selectMode(AppearanceMode.day);
      expect(controller.saveState, PreferenceSaveState.saved);
      expect(controller.warning, isNull);
      final reopened = AppearanceController(store);
      await reopened.restore();
      expect(reopened.settings.mode, AppearanceMode.day);
    },
  );

  test(
    'damaged and unknown saved choices use an explicit safe fallback',
    () async {
      for (final raw in [
        'not json',
        '{"version":2}',
        '{"version":1,"mode":"future"}',
        '{"version":1,"mode":"automatic","location":{"name":"Bad","latitude":99,"longitude":0}}',
      ]) {
        final store = MemoryAppearanceStore()..value = raw;
        final controller = AppearanceController(store);
        await controller.restore();
        expect(controller.settings.mode, AppearanceMode.automatic);
        expect(controller.settings.location, isNull);
        expect(controller.warning, contains('could not be read'));
        expect(store.value, raw);
      }
    },
  );
}
