import Foundation

public struct GuardOverrideResolution: Equatable, Sendable {
  public let maxOverrideActive: Bool
  public let maxOverrideExpiresAt: Date?
  public let shouldResetRuleState: Bool
  public let shouldClearCommandFile: Bool

  public init(
    maxOverrideActive: Bool,
    maxOverrideExpiresAt: Date? = nil,
    shouldResetRuleState: Bool,
    shouldClearCommandFile: Bool
  ) {
    self.maxOverrideActive = maxOverrideActive
    self.maxOverrideExpiresAt = maxOverrideExpiresAt
    self.shouldResetRuleState = shouldResetRuleState
    self.shouldClearCommandFile = shouldClearCommandFile
  }

  public static let none = GuardOverrideResolution(
    maxOverrideActive: false,
    shouldResetRuleState: false,
    shouldClearCommandFile: false
  )
}

public enum GuardOverrideResolver {
  public static func resolve(
    command: GuardCommand?,
    configuration: GuardConfiguration,
    daemonStart: Date,
    now: Date
  ) -> GuardOverrideResolution {
    guard let command, !command.isStale(since: daemonStart, at: now) else {
      return GuardOverrideResolution(
        maxOverrideActive: false,
        shouldResetRuleState: false,
        shouldClearCommandFile: command != nil
      )
    }

    switch command.action {
    case .max:
      let duration = command.expiresAfter ?? configuration.overrideTimeout
      let expiresAt = duration > 0
        ? command.issuedAt.addingTimeInterval(duration)
        : nil
      if let expiresAt, now >= expiresAt {
        return GuardOverrideResolution(
          maxOverrideActive: false,
          shouldResetRuleState: false,
          shouldClearCommandFile: true
        )
      }
      return GuardOverrideResolution(
        maxOverrideActive: true,
        maxOverrideExpiresAt: expiresAt,
        shouldResetRuleState: false,
        shouldClearCommandFile: false
      )
    case .auto:
      return GuardOverrideResolution(
        maxOverrideActive: false,
        shouldResetRuleState: true,
        shouldClearCommandFile: true
      )
    case .clear:
      return GuardOverrideResolution(
        maxOverrideActive: false,
        shouldResetRuleState: false,
        shouldClearCommandFile: true
      )
    }
  }
}
