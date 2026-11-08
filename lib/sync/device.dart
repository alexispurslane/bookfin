import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _device = MethodChannel('bookfin/device');

/// The name of this device that its owner knows it by, for example
/// "Pixel 8", or null when the platform gives none. On Android it is the
/// device name of the system settings, or else the model name. Neither needs
/// a permission.
Future<String?> deviceName() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    final name = (await _device.invokeMethod<String>('name'))?.trim();
    return name == null || name.isEmpty ? null : name;
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
