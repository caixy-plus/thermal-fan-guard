import AppKit
import SwiftUI

/// Sizes and centers the SwiftUI Settings window when it is shown.
struct SettingsWindowConfigurator: NSViewRepresentable {
  let width: CGFloat
  let height: CGFloat

  func makeNSView(context: Context) -> ConfiguratorView {
    let view = ConfiguratorView()
    view.onAttachToWindow = { window in
      Task { @MainActor in
        context.coordinator.apply(to: window, width: width, height: height)
      }
    }
    return view
  }

  func updateNSView(_ nsView: ConfiguratorView, context: Context) {
    nsView.onAttachToWindow = { window in
      Task { @MainActor in
        context.coordinator.apply(to: window, width: width, height: height)
      }
    }
    if let window = nsView.window {
      Task { @MainActor in
        context.coordinator.apply(to: window, width: width, height: height)
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  @MainActor
  final class Coordinator {
    private weak var configuredWindow: NSWindow?

    func apply(to window: NSWindow?, width: CGFloat, height: CGFloat) {
      guard let window else { return }
      let size = NSSize(width: width, height: height)
      window.minSize = NSSize(width: width, height: height * 0.75)
      guard configuredWindow !== window else { return }
      configuredWindow = window
      window.setContentSize(size)
      window.center()
    }
  }

  final class ConfiguratorView: NSView {
    var onAttachToWindow: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      onAttachToWindow?(window)
    }
  }
}
