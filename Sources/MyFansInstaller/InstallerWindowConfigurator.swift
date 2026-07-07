import AppKit
import SwiftUI

struct InstallerWindowConfigurator: NSViewRepresentable {
  let width: CGFloat
  let height: CGFloat

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      guard let window = view.window else { return }
      window.title = "安装 MyFans"
      window.styleMask.remove(.resizable)
      window.isReleasedWhenClosed = false
      window.setContentSize(NSSize(width: width, height: height))
      window.center()
      window.makeKeyAndOrderFront(nil)
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}
