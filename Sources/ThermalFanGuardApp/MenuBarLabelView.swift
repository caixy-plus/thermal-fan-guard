import SwiftUI
import ThermalFanGuardCore

struct MenuBarLabelView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    HStack(spacing: 2) {
      Image(systemName: iconName)
        .symbolRenderingMode(.hierarchical)
        .symbolEffect(.pulse, isActive: model.isMaxMode)
      if !model.menuBarTemperatureText.isEmpty {
        Text(model.menuBarTemperatureText.trimmingCharacters(in: .whitespaces))
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(model.isMaxMode ? .orange : .primary)
          .contentTransition(.numericText())
      }
    }
  }

  private var iconName: String {
    if !model.isDaemonOnline { return "fan.badge.slash" }
    if model.isMaxMode { return "fan.fill" }
    return "fan"
  }
}
