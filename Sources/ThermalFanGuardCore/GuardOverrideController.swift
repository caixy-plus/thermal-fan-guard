import Foundation

public struct GuardOverrideController: Sendable {
  private var latestCommandIssuedAt: Date?
  private var latestCommandAction: GuardCommand.Action?
  private var activeMaxCommand: GuardCommand?

  public init() {}

  public mutating func resolve(
    command: GuardCommand?,
    configuration: GuardConfiguration,
    daemonStart: Date,
    now: Date
  ) -> GuardOverrideResolution {
    guard let command else {
      return resolveActiveMax(
        configuration: configuration,
        daemonStart: daemonStart,
        now: now
      )
    }

    if shouldReject(command) || command.isStale(since: daemonStart, at: now) {
      return rejectedCommandResolution(
        configuration: configuration,
        daemonStart: daemonStart,
        now: now
      )
    }

    latestCommandIssuedAt = command.issuedAt
    latestCommandAction = command.action

    switch command.action {
    case .max:
      activeMaxCommand = command
      return resolveActiveMax(
        configuration: configuration,
        daemonStart: daemonStart,
        now: now
      )
    case .auto, .clear:
      activeMaxCommand = nil
      return GuardOverrideResolver.resolve(
        command: command,
        configuration: configuration,
        daemonStart: daemonStart,
        now: now
      )
    }
  }

  private func shouldReject(_ command: GuardCommand) -> Bool {
    guard let latestCommandIssuedAt else { return false }
    if command.issuedAt < latestCommandIssuedAt { return true }
    guard command.issuedAt == latestCommandIssuedAt,
          let latestCommandAction else { return false }
    switch (latestCommandAction, command.action) {
    case (.auto, .max), (.clear, .max):
      return true
    default:
      return false
    }
  }

  private mutating func rejectedCommandResolution(
    configuration: GuardConfiguration,
    daemonStart: Date,
    now: Date
  ) -> GuardOverrideResolution {
    let active = resolveActiveMax(
      configuration: configuration,
      daemonStart: daemonStart,
      now: now
    )
    return GuardOverrideResolution(
      maxOverrideActive: active.maxOverrideActive,
      maxOverrideExpiresAt: active.maxOverrideExpiresAt,
      shouldResetRuleState: false,
      shouldClearCommandFile: true
    )
  }

  private mutating func resolveActiveMax(
    configuration: GuardConfiguration,
    daemonStart: Date,
    now: Date
  ) -> GuardOverrideResolution {
    guard let activeMaxCommand else { return .none }
    let resolution = GuardOverrideResolver.resolve(
      command: activeMaxCommand,
      configuration: configuration,
      daemonStart: daemonStart,
      now: now
    )
    if !resolution.maxOverrideActive {
      self.activeMaxCommand = nil
    }
    return resolution
  }
}
