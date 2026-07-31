import AppKit
import XCTest
@testable import ThermalFanGuardApp

@MainActor
final class SettingsWindowConfiguratorTests: XCTestCase {
  func testOpeningSettingsDoesNotFocusTextField() {
    let (window, _) = makeWindow()

    SettingsWindowConfigurator.Coordinator().apply(to: window, width: 320, height: 200)

    XCTAssertFalse(window.firstResponder is NSTextView)
  }

  func testClickingTextFieldKeepsItsFocus() {
    let (window, textField) = makeWindow()
    let coordinator = SettingsWindowConfigurator.Coordinator()
    coordinator.apply(to: window, width: 320, height: 200)
    XCTAssertTrue(window.makeFirstResponder(textField))

    sendClick(at: NSPoint(x: 40, y: 150), to: window)

    XCTAssertTrue(window.firstResponder is NSTextView)
  }

  func testClickingBlankAreaClearsTextFieldFocus() {
    let (window, textField) = makeWindow()
    let coordinator = SettingsWindowConfigurator.Coordinator()
    coordinator.apply(to: window, width: 320, height: 200)
    XCTAssertTrue(window.makeFirstResponder(textField))

    sendClick(at: NSPoint(x: 250, y: 50), to: window)

    XCTAssertFalse(window.firstResponder is NSTextView)
  }

  private func makeWindow() -> (NSWindow, NSTextField) {
    let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
    let textField = NSTextField(frame: NSRect(x: 20, y: 140, width: 120, height: 24))
    contentView.addSubview(textField)
    let window = NSWindow(
      contentRect: contentView.bounds,
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = contentView
    return (window, textField)
  }

  private func sendClick(at point: NSPoint, to window: NSWindow) {
    let click = NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: point,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 1,
      clickCount: 1,
      pressure: 1
    )!
    NSApplication.shared.sendEvent(click)
  }
}
