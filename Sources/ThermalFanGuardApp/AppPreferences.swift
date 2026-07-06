import Foundation
import ThermalFanGuardCore

enum AppPreferences {
  static let showMenuBarTemperatureKey = "showMenuBarTemperature"
  static let notifyOnChangeKey = "notifyOnChange"
  static let notifyOnDeescalationKey = "notifyOnDeescalation"

  static var showMenuBarTemperature: Bool {
    get {
      if UserDefaults.standard.object(forKey: showMenuBarTemperatureKey) == nil { return true }
      return UserDefaults.standard.bool(forKey: showMenuBarTemperatureKey)
    }
    set { UserDefaults.standard.set(newValue, forKey: showMenuBarTemperatureKey) }
  }

  static var notifyOnChange: Bool {
    get {
      if UserDefaults.standard.object(forKey: notifyOnChangeKey) == nil { return true }
      return UserDefaults.standard.bool(forKey: notifyOnChangeKey)
    }
    set { UserDefaults.standard.set(newValue, forKey: notifyOnChangeKey) }
  }

  static var notifyOnDeescalation: Bool {
    get { UserDefaults.standard.bool(forKey: notifyOnDeescalationKey) }
    set { UserDefaults.standard.set(newValue, forKey: notifyOnDeescalationKey) }
  }
}
