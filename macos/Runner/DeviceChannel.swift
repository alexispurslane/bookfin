import Foundation

#if os(iOS)
  import Flutter
  import UIKit
#else
  import FlutterMacOS
  import SystemConfiguration
#endif

/// The Apple side of the `bookfin/device` channel, which Android's
/// HostChannels.kt also implements. Its method `name` returns the name that the
/// owner gave this device: the computer name of the Sharing settings on
/// macOS, and the device name on iOS. Dart's `deviceName` is its only caller.
/// Its method `build` returns the facts behind Dart's
/// `textEngineFingerprint`: the modification time of the app bundle's
/// executable, which changes with every build, and the system's version with
/// its build number. Neither method needs a permission or entitlement.
final class DeviceChannel {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "bookfin/device", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "name":
        result(DeviceChannel.name())
      case "build":
        result(DeviceChannel.installedBuild())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func name() -> String? {
    #if os(iOS)
      return UIDevice.current.name
    #else
      return SCDynamicStoreCopyComputerName(nil, nil) as String?
    #endif
  }

  private static func installedBuild() -> [String: Any]? {
    guard
      let executable = Bundle.main.executableURL,
      let modified = try? executable.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
    else { return nil }
    return [
      "installTime": Int64(modified.timeIntervalSince1970 * 1000),
      "system": ProcessInfo.processInfo.operatingSystemVersionString,
    ]
  }
}
