import Foundation

public enum FanMode: Equatable, Sendable { case automatic, maximum }

public struct GuardDecision: Equatable, Sendable {
  public let mode: FanMode
  public let changed: Bool
  public let reason: String?

  public init(mode: FanMode, changed: Bool, reason: String?) {
    self.mode = mode
    self.changed = changed
    self.reason = reason
  }
}

public enum GuardEscalation: Equatable, Sendable {
  case escalated(ruleIndex: Int, percent: Int)
  case deescalated(ruleIndex: Int?, percent: Int?)
  case recovered
}

public enum FanControlHardwareAction: Equatable, Sendable {
  case restoreAutomatic
  case setPercent(Int)
}

public struct MultiRuleDecision: Equatable, Sendable {
  public let fanSpeedPercent: Int?
  public let activeRuleIndex: Int?
  public let changed: Bool
  public let escalation: GuardEscalation?

  public init(
    fanSpeedPercent: Int?,
    activeRuleIndex: Int?,
    changed: Bool,
    escalation: GuardEscalation?
  ) {
    self.fanSpeedPercent = fanSpeedPercent
    self.activeRuleIndex = activeRuleIndex
    self.changed = changed
    self.escalation = escalation
  }

  public var isAutomatic: Bool { fanSpeedPercent == nil }
}

public struct ThermalGuardState: Sendable {
  private(set) public var threshold: Double
  private(set) public var recoveryThreshold: Double
  private(set) public var triggerDuration: TimeInterval
  private(set) public var recoveryDuration: TimeInterval
  private(set) public var mode: FanMode = .automatic
  private var triggerSince: Date?
  private var recoverySince: Date?

  public init(
    threshold: Double = 60,
    recoveryThreshold: Double = 55,
    triggerDuration: TimeInterval = 30,
    recoveryDuration: TimeInterval = 30
  ) {
    self.threshold = threshold
    self.recoveryThreshold = recoveryThreshold
    self.triggerDuration = triggerDuration
    self.recoveryDuration = recoveryDuration
  }

  public init(rule: GuardRule) {
    self.init(
      threshold: rule.triggerTemperature,
      recoveryThreshold: rule.recoveryTemperature,
      triggerDuration: rule.triggerDuration,
      recoveryDuration: rule.recoveryDuration
    )
  }

  public mutating func apply(_ rule: GuardRule) {
    threshold = rule.triggerTemperature
    recoveryThreshold = rule.recoveryTemperature
    triggerDuration = rule.triggerDuration
    recoveryDuration = rule.recoveryDuration
    triggerSince = nil
    recoverySince = nil
  }

  public mutating func observe(temperature: Double, at now: Date) -> GuardDecision {
    if mode == .automatic {
      recoverySince = nil
      triggerSince = temperature >= threshold ? (triggerSince ?? now) : nil
      if let since = triggerSince, now.timeIntervalSince(since) >= triggerDuration {
        mode = .maximum
        return .init(mode: mode, changed: true, reason: "at-or-above-threshold")
      }
      return .init(mode: mode, changed: false, reason: nil)
    }
    triggerSince = nil
    recoverySince = temperature <= recoveryThreshold ? (recoverySince ?? now) : nil
    if let since = recoverySince, now.timeIntervalSince(since) >= recoveryDuration {
      mode = .automatic
      recoverySince = nil
      return .init(mode: mode, changed: true, reason: "recovered")
    }
    return .init(mode: mode, changed: false, reason: nil)
  }

  public var isTriggered: Bool { mode == .maximum }
}

public struct MultiRuleGuardState: Sendable {
  private var ruleStates: [ThermalGuardState]
  private var ruleConfigs: [GuardRule]
  private(set) public var activeRuleIndex: Int?
  private(set) public var fanSpeedPercent: Int?

  public init(configuration: GuardConfiguration) {
    ruleConfigs = configuration.sortedRules
    ruleStates = ruleConfigs.map(ThermalGuardState.init(rule:))
    activeRuleIndex = nil
    fanSpeedPercent = nil
  }

  public var hardwareAction: FanControlHardwareAction {
    fanSpeedPercent.map(FanControlHardwareAction.setPercent) ?? .restoreAutomatic
  }

  @discardableResult
  public mutating func apply(_ configuration: GuardConfiguration) -> Bool {
    let wasControllingFans = fanSpeedPercent != nil
    let sorted = configuration.sortedRules
    var nextStates: [ThermalGuardState] = []
    nextStates.reserveCapacity(sorted.count)
    for (index, rule) in sorted.enumerated() {
      if index < ruleStates.count, index < ruleConfigs.count,
         ruleConfigs[index].triggerTemperature == rule.triggerTemperature,
         ruleConfigs[index].fanSpeedPercent == rule.fanSpeedPercent {
        var state = ruleStates[index]
        state.apply(rule)
        nextStates.append(state)
      } else {
        nextStates.append(ThermalGuardState(rule: rule))
      }
    }
    ruleConfigs = sorted
    ruleStates = nextStates
    recomputeActiveRule()
    return wasControllingFans && fanSpeedPercent == nil
  }

  public mutating func observe(temperature: Double, at now: Date) -> MultiRuleDecision {
    for index in ruleStates.indices {
      _ = ruleStates[index].observe(temperature: temperature, at: now)
    }
    let previousPercent = fanSpeedPercent
    let previousIndex = activeRuleIndex
    recomputeActiveRule()

    let changed = fanSpeedPercent != previousPercent
    let escalation = escalationKind(
      previousPercent: previousPercent,
      previousIndex: previousIndex,
      newPercent: fanSpeedPercent,
      newIndex: activeRuleIndex
    )
    return MultiRuleDecision(
      fanSpeedPercent: fanSpeedPercent,
      activeRuleIndex: activeRuleIndex,
      changed: changed,
      escalation: changed ? escalation : nil
    )
  }

  private mutating func recomputeActiveRule() {
    var bestIndex: Int?
    var bestPercent = Int.min
    for (index, state) in ruleStates.enumerated() where state.isTriggered {
      let percent = ruleConfigs[index].fanSpeedPercent
      if percent > bestPercent {
        bestPercent = percent
        bestIndex = index
      }
    }
    if let bestIndex {
      activeRuleIndex = bestIndex
      fanSpeedPercent = ruleConfigs[bestIndex].fanSpeedPercent
    } else {
      activeRuleIndex = nil
      fanSpeedPercent = nil
    }
  }

  private func escalationKind(
    previousPercent: Int?,
    previousIndex: Int?,
    newPercent: Int?,
    newIndex: Int?
  ) -> GuardEscalation? {
    switch (previousPercent, newPercent) {
    case (nil, nil):
      return nil
    case (nil, .some(let percent)):
      return .escalated(ruleIndex: newIndex ?? 0, percent: percent)
    case (.some, nil):
      return .recovered
    case let (.some(old), .some(new)) where new > old:
      return .escalated(ruleIndex: newIndex ?? 0, percent: new)
    case let (.some(old), .some(new)) where new < old:
      return .deescalated(ruleIndex: newIndex, percent: new)
    default:
      if previousIndex != newIndex, let newIndex, let newPercent = newPercent {
        return .deescalated(ruleIndex: newIndex, percent: newPercent)
      }
      return nil
    }
  }
}
