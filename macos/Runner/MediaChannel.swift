import Foundation
import Network

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

/// The Apple side of Bookfin's media host contract, which Android's
/// HostChannels.kt also implements. Dart's `createDownloads` and
/// `createCovers` are its only callers.
///
/// Method channel `bookfin/media`:
/// - `storage` returns `{"path": <directory>}`, the private directory that
///   holds downloads. Covers live in `bookfin-covers` beside it.
/// - `freeBytes` returns the bytes free for important use on the volume of
///   that directory.
/// - `network` returns the current network kind.
///
/// Event channel `bookfin/media-network` sends the network kind each time
/// that it changes. A kind is "wifi" for an unmetered connection, "mobile"
/// for an expensive or constrained one, "disconnected" without a usable
/// path, and "unknown" otherwise. Wired Ethernet counts as "wifi", because
/// Bookfin's rule only asks whether the connection is metered.
///
/// This file uses no AppKit, so the iOS runner can compile it as it is.
final class MediaChannel: NSObject, FlutterStreamHandler {
  private let monitor = NWPathMonitor()
  private let monitorQueue = DispatchQueue(label: "dev.bookfin.media-network")
  private var events: FlutterEventSink?
  private let methods: FlutterMethodChannel
  private let network: FlutterEventChannel

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(name: "bookfin/media", binaryMessenger: messenger)
    network = FlutterEventChannel(name: "bookfin/media-network", binaryMessenger: messenger)
    super.init()
    monitor.pathUpdateHandler = { [weak self] path in
      let kind = MediaChannel.kind(of: path)
      DispatchQueue.main.async { self?.events?(kind) }
    }
    monitor.start(queue: monitorQueue)
    methods.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    network.setStreamHandler(self)
  }

  deinit {
    monitor.cancel()
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "storage":
      do {
        result(["path": try MediaChannel.supportDirectory().appendingPathComponent("bookfin-media").path])
      } catch {
        result(FlutterError(code: "storage", message: error.localizedDescription, details: nil))
      }
    case "freeBytes":
      result(MediaChannel.freeBytes())
    case "network":
      result(MediaChannel.kind(of: monitor.currentPath))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The app's Application Support directory. Inside the App Sandbox it is
  /// already private to Bookfin.
  private static func supportDirectory() throws -> URL {
    try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
  }

  private static func freeBytes() -> Int64 {
    guard let directory = try? supportDirectory(),
      let values = try? directory.resourceValues(forKeys: [
        .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
      ])
    else { return 0 }
    if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
      return important
    }
    return Int64(values.volumeAvailableCapacity ?? 0)
  }

  private static func kind(of path: NWPath) -> String {
    guard path.status == .satisfied else { return "disconnected" }
    if path.isExpensive || path.isConstrained { return "mobile" }
    if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) { return "wifi" }
    return "unknown"
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    self.events = events
    events(MediaChannel.kind(of: monitor.currentPath))
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    events = nil
    return nil
  }
}
