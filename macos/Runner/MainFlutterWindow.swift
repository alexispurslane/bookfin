import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var media: MediaChannel?
  private var device: DeviceChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Bookfin's layout is a phone's. The window opens phone-shaped and
    // never gets narrower or shorter than a small phone.
    self.contentMinSize = NSSize(width: 360, height: 600)
    self.setContentSize(NSSize(width: 430, height: 820))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    let messenger = flutterViewController.engine.binaryMessenger
    media = MediaChannel(messenger: messenger)
    device = DeviceChannel(messenger: messenger)

    super.awakeFromNib()
  }
}
