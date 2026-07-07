import AppKit

enum MenuBarPanelCloser {
  static let popoverWidth: CGFloat = 320

  @MainActor
  static func closePopoverIfVisible() {
    for window in NSApp.windows where window.isVisible {
      guard abs(window.frame.width - popoverWidth) < 4 else { continue }
      window.orderOut(nil)
    }
  }
}
