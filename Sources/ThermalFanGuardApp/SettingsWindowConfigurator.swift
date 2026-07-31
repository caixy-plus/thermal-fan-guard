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
    private var mouseMonitor: MouseMonitorToken?

    func apply(to window: NSWindow?, width: CGFloat, height: CGFloat) {
      guard let window else { return }
      let size = NSSize(width: width, height: height)
      window.minSize = NSSize(width: width, height: height * 0.75)
      guard configuredWindow !== window else { return }
      configuredWindow = window
      window.setContentSize(size)
      window.center()
      window.initialFirstResponder = nil
      window.makeFirstResponder(nil)
      installMouseMonitor(for: window)
      Task { @MainActor [weak self, weak window] in
        await Task.yield()
        guard self?.configuredWindow === window else { return }
        window?.makeFirstResponder(nil)
      }
    }

    private func installMouseMonitor(for window: NSWindow) {
      mouseMonitor = nil
      let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak window] event in
        guard let window, event.window === window else { return event }
        let clickedView = window.contentView?.hitTest(event.locationInWindow)
        if !Self.isTextInput(clickedView) {
          window.makeFirstResponder(nil)
        }
        return event
      }
      if let monitor {
        mouseMonitor = MouseMonitorToken(monitor)
      }
    }

    private static func isTextInput(_ view: NSView?) -> Bool {
      var candidate = view
      while let current = candidate {
        if current is NSTextField || current is NSTextView {
          return true
        }
        candidate = current.superview
      }
      return false
    }
  }

  private final class MouseMonitorToken: @unchecked Sendable {
    private let monitor: Any

    init(_ monitor: Any) {
      self.monitor = monitor
    }

    deinit {
      NSEvent.removeMonitor(monitor)
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
