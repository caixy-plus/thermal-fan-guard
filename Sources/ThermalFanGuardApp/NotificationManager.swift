import Foundation
import ThermalFanGuardCore
@preconcurrency import UserNotifications

@MainActor
final class NotificationManager {
  private var tracker = StatusNotificationTracker()

  func requestAuthorizationIfNeeded() async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .notDetermined else { return }
    _ = try? await center.requestAuthorization(options: [.alert, .sound])
  }

  func seedBaseline(from status: GuardRuntimeStatus) {
    tracker.seed(
      activeRuleIndex: status.activeRuleIndex,
      fanSpeedPercent: status.fanSpeedPercent,
      override: status.override ?? "none"
    )
  }

  func handleStatusChange(status: GuardRuntimeStatus, configuration _: GuardConfiguration) {
    let override = status.override ?? "none"
    guard let event = tracker.transition(
      activeRuleIndex: status.activeRuleIndex,
      fanSpeedPercent: status.fanSpeedPercent,
      override: override
    ), AppPreferences.notifyOnChange else { return }

    switch event {
    case .manualMaximumEnabled:
      post(
        identifier: StatusNotificationIdentifier(kind: event),
        title: "手动全速已启用",
        body: "风扇已加速至 100%，过热保护规则仍然有效。"
      )
    case .manualMaximumEnded:
      post(
        identifier: StatusNotificationIdentifier(kind: event),
        title: "手动全速已结束",
        body: "已恢复自动控制。"
      )
    case .recovered:
      post(
        identifier: StatusNotificationIdentifier(kind: event),
        title: "温度回落，已恢复自动控制",
        body: "风扇已交还给 macOS 自动管理。"
      )
    case let .deescalated(activeIndex, percent):
      guard AppPreferences.notifyOnDeescalation else { return }
      post(
        identifier: StatusNotificationIdentifier(kind: event),
        title: "温度回落",
        body: "降至第 \(activeIndex + 1) 档（\(percent)%）。"
      )
    case let .escalated(activeIndex, percent):
      guard let temperature = status.temperature else { return }
      post(
        identifier: StatusNotificationIdentifier(kind: event),
        title: "\(Int(temperature.rounded()))°C 触发第 \(roman(activeIndex + 1)) 档规则",
        body: "风扇加速至 \(percent)%。"
      )
    }
  }

  private func post(identifier: StatusNotificationIdentifier, title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    let request = UNNotificationRequest(
      identifier: identifier.value,
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
