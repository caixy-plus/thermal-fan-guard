public struct StatusNotificationIdentifier: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case manualMaximumEnabled
    case manualMaximumEnded
    case recovered
    case escalated(ruleIndex: Int, percent: Int)
    case deescalated(ruleIndex: Int, percent: Int)
  }

  public let value: String

  public init(kind: Kind) {
    let suffix = switch kind {
    case .manualMaximumEnabled:
      "manual-maximum-enabled"
    case .manualMaximumEnded:
      "manual-maximum-ended"
    case .recovered:
      "recovered"
    case let .escalated(ruleIndex, percent):
      "escalated-\(ruleIndex)-\(percent)"
    case let .deescalated(ruleIndex, percent):
      "deescalated-\(ruleIndex)-\(percent)"
    }
    value = "com.caixinyun.thermal-fan-guard.\(suffix)"
  }
}

public struct StatusNotificationTracker: Sendable {
  private var previousFanSpeedPercent: Int?
  private var previousOverride = "none"
  private var hasBaseline = false

  public init() {}

  public mutating func seed(
    activeRuleIndex _: Int?,
    fanSpeedPercent: Int?,
    override: String
  ) {
    previousFanSpeedPercent = fanSpeedPercent
    previousOverride = override
    hasBaseline = true
  }

  public mutating func transition(
    activeRuleIndex: Int?,
    fanSpeedPercent: Int?,
    override: String
  ) -> StatusNotificationIdentifier.Kind? {
    guard hasBaseline else {
      seed(
        activeRuleIndex: activeRuleIndex,
        fanSpeedPercent: fanSpeedPercent,
        override: override
      )
      return nil
    }

    let oldPercent = previousFanSpeedPercent
    let oldOverride = previousOverride
    defer {
      previousFanSpeedPercent = fanSpeedPercent
      previousOverride = override
    }

    if override == "max" {
      return oldOverride == "max" ? nil : .manualMaximumEnabled
    }
    if oldOverride == "max" {
      return .manualMaximumEnded
    }

    guard let activeRuleIndex, let fanSpeedPercent else {
      return oldPercent != nil && fanSpeedPercent == nil ? .recovered : nil
    }

    guard let oldPercent else {
      return .escalated(ruleIndex: activeRuleIndex, percent: fanSpeedPercent)
    }
    if fanSpeedPercent > oldPercent {
      return .escalated(ruleIndex: activeRuleIndex, percent: fanSpeedPercent)
    }
    if fanSpeedPercent < oldPercent {
      return .deescalated(ruleIndex: activeRuleIndex, percent: fanSpeedPercent)
    }
    return nil
  }
}
