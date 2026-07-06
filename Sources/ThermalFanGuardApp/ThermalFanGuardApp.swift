import SwiftUI

@main
struct ThermalFanGuardApp: App {
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
