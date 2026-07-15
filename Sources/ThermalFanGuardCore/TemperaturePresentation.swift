import Foundation

public enum TemperaturePresentation {
  public static func menuBarText(_ temperature: Double) -> String {
    String(format: " %.1f°", temperature)
  }

  public static func ruleSummary(_ rule: GuardRule, marker: String) -> String {
    "\(marker) ≥\(Int(rule.triggerTemperature))° \(Int(rule.triggerDuration))s → \(rule.fanSpeedPercent)% (≤\(Int(rule.recoveryTemperature))° 持续\(Int(rule.recoveryDuration))s 解除)"
  }
}
