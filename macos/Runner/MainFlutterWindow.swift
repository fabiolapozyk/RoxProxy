import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Channel used by the native "File" menu to forward commands to Dart.
  private static var menuChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Set minimum and default window size matching the original SwiftUI app
    self.minSize = NSSize(width: 800, height: 500)
    self.setContentSize(NSSize(width: 1280, height: 760))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "com.roxproxy/menu",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    MainFlutterWindow.menuChannel = channel

    // The menu bar from MainMenu.xib only exists once the application has
    // finished launching, so install the File menu from that notification.
    NotificationCenter.default.addObserver(
      forName: NSApplication.didFinishLaunchingNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.installFileMenu()
    }

    super.awakeFromNib()
  }

  /// Adds a "File" menu (Open/Save session, Export HAR) right after the
  /// application menu, leaving every existing menu untouched.
  private func installFileMenu() {
    guard let mainMenu = NSApp.mainMenu else { return }
    // Guard against installing it twice (e.g. window recreated).
    guard !mainMenu.items.contains(where: { $0.title == "File" }) else { return }

    let fileMenu = NSMenu(title: "File")

    let openItem = fileMenu.addItem(
      withTitle: "Open Capture…",
      action: #selector(openCapture(_:)),
      keyEquivalent: "o"
    )
    openItem.target = self

    fileMenu.addItem(.separator())

    let exportItem = fileMenu.addItem(
      withTitle: "Export HAR…",
      action: #selector(exportHar(_:)),
      keyEquivalent: "e"
    )
    exportItem.keyEquivalentModifierMask = [.command, .shift]
    exportItem.target = self

    let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    fileMenuItem.submenu = fileMenu
    // Index 0 is the application menu; insert right after it.
    mainMenu.insertItem(fileMenuItem, at: min(1, mainMenu.items.count))
  }

  // MARK: - Menu actions

  @objc private func openCapture(_ sender: Any?) {
    sendMenuAction("openCapture")
  }

  @objc private func exportHar(_ sender: Any?) {
    sendMenuAction("exportHar")
  }

  private func sendMenuAction(_ action: String) {
    MainFlutterWindow.menuChannel?.invokeMethod("menuAction", arguments: action)
  }
}
