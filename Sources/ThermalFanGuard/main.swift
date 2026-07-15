import Darwin
import Foundation
import ThermalFanGuardCore

func log(_ message: String) {
  print("\(ISO8601DateFormatter().string(from: Date())) \(message)")
  fflush(stdout)
}

func status() throws {
  let configuration = GuardConfiguration.load()
  let hardware = try ThermalHardware()
  let reading = try hardware.readMaximumTemperature(sensorGroups: Set(configuration.sensorGroups))
  print(
    String(
      format: "temperature=%.1fC hottest=%@ sensors=%d %@",
      reading.maximum,
      reading.sensor,
      reading.validSensorCount,
      try hardware.fanStatus()
    )
  )
}

private func escalationLog(_ escalation: GuardEscalation) -> String {
  switch escalation {
  case let .escalated(index, percent):
    "ESCALATED rule=\(index + 1) fan=\(percent)%"
  case let .deescalated(index, percent):
    if let index, let percent {
      "DEESCALATED rule=\(index + 1) fan=\(percent)%"
    } else {
      "DEESCALATED"
    }
  case .recovered:
    "RECOVERED automatic control restored"
  }
}

func daemon() throws -> Never {
  guard geteuid() == 0 else {
    fputs("thermal-fan-guard daemon must run as root\n", stderr)
    exit(77)
  }

  let hardware = try ThermalHardware()
  let daemonStart = Date()
  var configuration = GuardConfiguration.load()
  var state = MultiRuleGuardState(configuration: configuration)
  var overrideController = GuardOverrideController()
  let history = HistoryStore(sampleInterval: configuration.sampleInterval)
  var stop = false

  signal(SIGTERM, SIG_IGN)
  signal(SIGINT, SIG_IGN)
  let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
  let intr = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
  term.setEventHandler { stop = true }
  intr.setEventHandler { stop = true }
  term.resume()
  intr.resume()

  defer {
    try? hardware.restoreAutomaticControl()
    history.flushIfNeeded(force: true)
    log("stopped; restored automatic fan control")
  }

  switch state.hardwareAction {
  case .restoreAutomatic:
    try hardware.restoreAutomaticControl()
    log("startup restored automatic fan control")
  case let .setPercent(percent):
    try hardware.setFans(toPercent: percent)
  }
  log(
    "started rules=\(configuration.sortedRules.count) interval=\(Int(configuration.sampleInterval))s sensors=\(configuration.sensorGroups.joined(separator: ","))"
  )

  while !stop {
    let now = Date()
    do {
      let latestConfiguration = GuardConfiguration.load()
      if latestConfiguration != configuration {
        configuration = latestConfiguration
        if state.apply(configuration) {
          try hardware.restoreAutomaticControl()
          log("configuration reset active rule; restored automatic fan control")
        }
        history.reconfigure(sampleInterval: configuration.sampleInterval)
        log("configuration updated rules=\(configuration.sortedRules.count)")
      }

      let command = GuardCommand.load()
      var override = overrideController.resolve(
        command: command,
        configuration: configuration,
        daemonStart: daemonStart,
        now: now
      )
      if override.shouldClearCommandFile {
        GuardCommand.clear()
      }
      if override.shouldResetRuleState {
        try hardware.restoreAutomaticControl()
        state = MultiRuleGuardState(configuration: configuration)
        log("MANUAL auto restore; rule state reset")
      }

      let reading = try hardware.readMaximumTemperature(sensorGroups: Set(configuration.sensorGroups))
      let decision = state.observe(temperature: reading.maximum, at: now)

      var mode = "automatic"
      var overrideLabel = "none"
      var appliedPercent: Int?

      if override.maxOverrideActive {
        if let expiresAt = override.maxOverrideExpiresAt, now >= expiresAt {
          override = .none
          GuardCommand.clear()
        } else {
          try hardware.setFans(toPercent: 100)
          mode = "boosted"
          overrideLabel = "max"
          appliedPercent = 100
        }
      }

      if !override.maxOverrideActive {
        if decision.changed {
          if let percent = decision.fanSpeedPercent {
            try hardware.setFans(toPercent: percent)
            mode = "maximum"
            appliedPercent = percent
            if let escalation = decision.escalation {
              log(escalationLog(escalation))
            }
          } else {
            try hardware.restoreAutomaticControl()
            if let escalation = decision.escalation {
              log(escalationLog(escalation))
            }
          }
        } else if let percent = decision.fanSpeedPercent {
          try hardware.setFans(toPercent: percent)
          mode = "maximum"
          appliedPercent = percent
        }
      }

      let fans = try hardware.readFans()
      let fanText = try hardware.fanStatus()
      history.append(temperature: reading.maximum, mode: mode, at: now)
      history.flushIfNeeded()

      GuardRuntimeStatus(
        timestamp: now,
        temperature: reading.maximum,
        sensor: reading.sensor,
        validSensorCount: reading.validSensorCount,
        mode: mode,
        fanStatus: fanText,
        error: nil,
        fans: fans,
        activeRuleIndex: override.maxOverrideActive ? nil : state.activeRuleIndex,
        fanSpeedPercent: override.maxOverrideActive ? 100 : appliedPercent,
        override: overrideLabel
      ).save()

      log(
        String(
          format: "sample temperature=%.1fC sensor=%@ sensors=%d mode=%@ %@",
          reading.maximum,
          reading.sensor,
          reading.validSensorCount,
          mode,
          fanText
        )
      )
    } catch {
      let fans = try? hardware.readFans()
      let fanText = try? hardware.fanStatus()
      history.append(temperature: nil, mode: "error", at: now)
      history.flushIfNeeded()
      GuardRuntimeStatus(
        timestamp: now,
        temperature: nil,
        sensor: nil,
        validSensorCount: nil,
        mode: state.fanSpeedPercent == nil ? "automatic" : "maximum",
        fanStatus: fanText,
        error: error.localizedDescription,
        fans: fans,
        activeRuleIndex: state.activeRuleIndex,
        fanSpeedPercent: state.fanSpeedPercent,
        override: "none"
      ).save()
      log("ERROR sample/control failed: \(error)")
    }

    let until = now.addingTimeInterval(configuration.sampleInterval)
    while !stop && RunLoop.current.run(mode: .default, before: until) && Date() < until {}
    if Date() < until { Thread.sleep(until: until) }
  }
  exit(0)
}

do {
  if CommandLine.arguments.contains("--status") {
    try status()
  } else {
    try daemon()
  }
} catch {
  fputs("thermal-fan-guard: \(error.localizedDescription)\n", stderr)
  exit(1)
}
