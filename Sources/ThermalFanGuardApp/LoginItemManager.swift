import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
  @Published private(set) var isEnabled = false
  @Published var lastError: String?

  func refresh() {
    isEnabled = SMAppService.mainApp.status == .enabled
  }

  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      lastError = nil
      refresh()
    } catch {
      lastError = error.localizedDescription
      refresh()
    }
  }
}
