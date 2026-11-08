import Foundation

#if os(iOS)
  import Flutter
  import UIKit
#else
  import FlutterMacOS
  import SystemConfiguration
#endif

/// The Apple side of the `bookfin/device` channel, which Android's
/// MainActivity also implements. Its one method, `name`, returns the name
/// that the owner gave this device: the computer name of the Sharing
/// settings on macOS, and the device name on iOS. Dart's `deviceName` is its
/// only caller. Reading the name needs no permission or entitlement.
final class DeviceChannel {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "bookfin/device", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "name":
        result(DeviceChannel.name())
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
}
