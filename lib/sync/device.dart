import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _device = MethodChannel('bookfin/device');

/// The name of this device that its owner knows it by, for example
/// "Pixel 8", or null when the platform gives none. On Android it is the
/// device name of the system settings, or else the model name. Neither needs
/// a permission. On macOS it is the computer name of the Sharing settings.
/// A runner without the `bookfin/device` channel gives null.
Future<String?> deviceName() async {
  if (kIsWeb) return null;
  try {
    final name = (await _device.invokeMethod<String>('name'))?.trim();
    return name == null || name.isEmpty ? null : name;
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// One text naming everything outside a book that decides how Flutter's text
/// engine lays the book out, or null when this process cannot name it. A
/// cache of layout results keeps it beside each result and uses a result only
/// while the fingerprint is the same.
///
/// The fingerprint changes when one of these changes:
///
/// - the app's install: its code, its bundled fonts and Flutter's engine.
///   Android gives the time that the package was installed or updated. macOS
///   gives the modification time of the app bundle's executable.
/// - the system's build, which holds the fallback fonts for characters that
///   no bundled font has. Android gives `Build.FINGERPRINT`, and macOS gives
///   its version with the build number.
/// - [locales], which default to the platform's list of locales now.
///
/// A [debug] build gives null, because hot reload changes its code with no
/// install. So does the web, a runner without the `bookfin/device` channel,
/// and a channel call that fails. The process asks the channel once and keeps
/// the answer, because the install and the system do not change while it
/// runs. The locales can change, so each call reads them again.
Future<String?> textEngineFingerprint({
  bool debug = kDebugMode,
  List<Locale>? locales,
}) async {
  if (kIsWeb || debug) return null;
  final build = await (_installedBuild ??= _askInstalledBuild());
  if (build == null) return null;
  final tags = (locales ?? PlatformDispatcher.instance.locales)
      .map((locale) => locale.toLanguageTag())
      .join(',');
  return '${build.installTime}\n${build.system}\n$tags';
}

/// The install and system of this process, asked for on the first call of
/// [textEngineFingerprint].
Future<({int installTime, String system})?>? _installedBuild;

Future<({int installTime, String system})?> _askInstalledBuild() async {
  try {
    final answer = await _device.invokeMapMethod<String, Object?>('build');
    return switch (answer) {
      {'installTime': final int installTime, 'system': final String system} => (
        installTime: installTime,
        system: system,
      ),
      _ => null,
    };
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// Forgets the answer of the `build` call, as a new process would. Tests
/// call it to start the next test as a new launch.
@visibleForTesting
void forgetInstalledBuild() => _installedBuild = null;
