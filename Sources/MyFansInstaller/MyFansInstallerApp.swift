import AppKit
import SwiftUI

@main
struct MyFansInstallerApp: App {
  @NSApplicationDelegateAdaptor(InstallerAppDelegate.self) private var appDelegate

  var body: some Scene {
    Window("安装 MyFans", id: "installer") {
      InstallerView()
    }
    .windowResizability(.contentSize)
    .defaultPosition(.center)
  }
}

@MainActor
final class InstallerAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}
