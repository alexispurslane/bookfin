import 'package:bookfin/gallery.dart' as gallery;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../catalog/file_store_test.dart' show LegacyPreferences;

void main() {
  testWidgets(
    'gallery startup restores only appearance and opens no services',
    (tester) async {
      final previous = SharedPreferencesAsyncPlatform.instance;
      final preferences = LegacyPreferences();
      SharedPreferencesAsyncPlatform.instance = preferences;
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
      await SharedPreferencesAsync().setString(
        'bookfin.appearance.v1',
        '{"version":1,"mode":"night","location":null}',
      );
      final serviceCalls = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      for (final channel in [
        'bookfin/media',
        'bookfin/media-network',
        'bookfin/power',
        'plugins.it_nomads.com/flutter_secure_storage',
        'com.tekartik.sqflite',
        'com.ryanheise.audio_service.client.methods',
        'com.ryanheise.just_audio.methods',
      ]) {
        messenger.setMockMethodCallHandler(MethodChannel(channel), (
          call,
        ) async {
          serviceCalls.add('$channel/${call.method}');
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(MethodChannel(channel), null),
        );
      }

      await gallery.main();
      await tester.pumpAndSettle();
      expect(find.textContaining('Development gallery'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        Brightness.dark,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(preferences.reads, ['bookfin.appearance.v1']);
      expect(preferences.keyRequests, 0);
      expect(serviceCalls, isEmpty);
    },
  );
}
