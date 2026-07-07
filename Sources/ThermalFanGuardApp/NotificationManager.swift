import Foundation
import ThermalFanGuardCore
@preconcurrency import UserNotifications

@MainActor
final class NotificationManager {
  private var previousActiveRuleIndex: Int?
  private var previousFanSpeedPercent: Int?
  private var previousOverride: String?
  private var hasBaseline = false

  func requestAuthorizationIfNeeded() async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .notDetermined else { return }
    _ = try? await center.requestAuthorization(options: [.alert, .sound])
  }

  func seedBaseline(from status: GuardRuntimeStatus) {
    previousActiveRuleIndex = status.activeRuleIndex
    previousFanSpeedPercent = status.fanSpeedPercent
    previousOverride = status.override ?? "none"
    hasBaseline = true
  }

  func handleStatusChange(status: GuardRuntimeStatus, configuration: GuardConfiguration) {
    guard AppPreferences.notifyOnChange else { return }

    let override = status.override ?? "none"
    let activeIndex = status.activeRuleIndex
    let percent = status.fanSpeedPercent

    if !hasBaseline {
      seedBaseline(from: status)
      return
    }

    defer {
      previousActiveRuleIndex = activeIndex
      previousFanSpeedPercent = percent
      previousOverride = override
    }

    if override == "max", previousOverride != "max" {
      post(
        title: "手动全速已启用",
        body: "风扇已加速至 100%，过热保护规则仍然有效。"
      )
      return
    }

    if previousOverride == "max", override != "max" {
      post(title: "手动全速已结束", body: "已恢复自动控制。")
    }

    guard let activeIndex, let percent else {
      if previousFanSpeedPercent != nil {
        post(title: "✅ 温度回落，已恢复自动控制", body: "风扇已交还给 macOS 自动管理。")
      }
      return
    }

    if activeIndex != previousActiveRuleIndex || percent != previousFanSpeedPercent {
      if let previousPercent = previousFanSpeedPercent, percent < previousPercent {
        guard AppPreferences.notifyOnDeescalation else { return }
        post(
          title: "↘️ 温度回落",
          body: "降至第 \(activeIndex + 1) 档（\(percent)%）。"
        )
      } else if let temperature = status.temperature {
        post(
          title: "🌡 \(Int(temperature.rounded()))°C 触发第 \(roman(activeIndex + 1)) 档规则",
          body: "风扇加速至 \(percent)%。"
        )
      }
    }
  }

  private func post(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
  }

  private func roman(_ value: Int) -> String {
    switch value {
    case 1: "①"
    case 2: "②"
    case 3: "③"
    case 4: "④"
    case 5: "⑤"
    case 6: "⑥"
    case 7: "⑦"
    case 8: "⑧"
    default: "\(value)"
    }
  }
}
