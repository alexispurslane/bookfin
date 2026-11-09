import 'dart:ui';

import 'package:bookfin/sync/device.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookfin/device');
  void answer(Object? Function(MethodCall call) reply) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => reply(call));
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    // Each test is a new process, which asks the channel again.
    forgetInstalledBuild();
  });

  test('the device name is the name that Android gives this device', () async {
    answer((call) => call.method == 'name' ? 'Pixel 8' : null);
    expect(await deviceName(), 'Pixel 8');
  });

  test('a device that gives no name, or a blank one, has none', () async {
    answer((_) => null);
    expect(await deviceName(), isNull);
    answer((_) => '   ');
    expect(await deviceName(), isNull);
  });

  test('a platform without the device channel has no device name', () async {
    expect(await deviceName(), isNull);
  });

  group('the text-engine fingerprint', () {
    const english = [Locale('en', 'US')];
    Map<String, Object?> build({
      int installTime = 1762700000000,
      String system = 'google/sdk_gphone64_arm64/emu64a:15/AE3A.240806.043',
    }) => {'installTime': installTime, 'system': system};
    Future<String?> release({List<Locale> locales = english}) =>
        textEngineFingerprint(debug: false, locales: locales);

    test(
      'a release build reports one fingerprint for one install and system',
      () async {
        answer((call) => call.method == 'build' ? build() : null);
        final first = await release();
        expect(first, isNotNull);
        expect(await release(), first);
        // The next launch of the same install is a new process.
        forgetInstalledBuild();
        expect(await release(), first);
      },
    );

    test('a new install gives a new fingerprint', () async {
      answer((call) => call.method == 'build' ? build() : null);
      final before = await release();
      forgetInstalledBuild();
      answer(
        (call) =>
            call.method == 'build' ? build(installTime: 1762800000000) : null,
      );
      expect(await release(), isNot(before));
    });

    test('a new system build gives a new fingerprint', () async {
      answer((call) => call.method == 'build' ? build() : null);
      final before = await release();
      forgetInstalledBuild();
      answer(
        (call) => call.method == 'build'
            ? build(
                system: 'google/sdk_gphone64_arm64/emu64a:16/BP22.250124.009',
              )
            : null,
      );
      expect(await release(), isNot(before));
    });

    test('another list of locales gives another fingerprint', () async {
      answer((call) => call.method == 'build' ? build() : null);
      final english = await release();
      expect(
        await release(locales: const [Locale('ja', 'JP')]),
        isNot(english),
      );
      expect(
        await release(locales: const [Locale('en', 'US'), Locale('ja', 'JP')]),
        isNot(english),
      );
    });

    test('a process asks the platform for its build only once', () async {
      var asked = 0;
      answer((call) {
        asked++;
        return build();
      });
      await Future.wait([release(), release()]);
      await release(locales: const [Locale('ja', 'JP')]);
      expect(asked, 1);
    });

    test('a debug build reports no fingerprint', () async {
      answer((call) => call.method == 'build' ? build() : null);
      // Tests run as a debug build.
      expect(await textEngineFingerprint(), isNull);
      expect(await textEngineFingerprint(debug: true), isNull);
    });

    test('a missing channel reports no fingerprint', () async {
      expect(await release(), isNull);
    });

    test('a failing call reports no fingerprint', () async {
      answer((_) => throw PlatformException(code: 'unavailable'));
      expect(await release(), isNull);
    });

    test('an answer without both facts reports no fingerprint', () async {
      answer((_) => {'installTime': 1762700000000});
      expect(await release(), isNull);
      forgetInstalledBuild();
      answer((_) => {'system': 'macOS 15.1'});
      expect(await release(), isNull);
    });
  });
}
