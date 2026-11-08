import 'package:bookfin/sync/device.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bookfin/device');
  void answer(Object? Function(MethodCall call) reply) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => reply(call));
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

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
}
