import AppKit
import SwiftUI

@main
struct ThermalFanGuardApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var model = AppModel()

  var body: some Scene {
    MenuBarExtra {
      PopoverPanelView()
        .environmentObject(model)
    } label: {
      MenuBarLabelView()
        .environmentObject(model)
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView()
        .environmentObject(model)
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
          let icon = NSImage(contentsOf: iconURL) else { return }
    NSApplication.shared.applicationIconImage = icon
  }
}
