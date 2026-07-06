import Foundation
import Testing
@testable import ThermalFanGuardCore

@Test func atOrAboveSixtyForThirtySecondsTriggers() {
  var state = ThermalGuardState()
  let now = Date(timeIntervalSince1970: 1000)
  _ = state.observe(temperature: 60, at: now)
  #expect(state.observe(temperature: 61, at: now.addingTimeInterval(30)).mode == .maximum)
}

@Test func exactlySixtyTriggersAfterThirtySeconds() {
  var state = ThermalGuardState()
  let now = Date(timeIntervalSince1970: 1000)
  _ = state.observe(temperature: 60, at: now)
  #expect(state.observe(temperature: 60, at: now.addingTimeInterval(29)).mode == .automatic)
  #expect(state.observe(temperature: 60, at: now.addingTimeInterval(30)).mode == .maximum)
}

@Test func dipResetsTimer() {
  var state = ThermalGuardState()
  let now = Date(timeIntervalSince1970: 1000)
  _ = state.observe(temperature: 62, at: now)
  _ = state.observe(temperature: 59, at: now.addingTimeInterval(20))
  #expect(state.observe(temperature: 62, at: now.addingTimeInterval(35)).mode == .automatic)
}

@Test func recoveryRequiresThirtySeconds() {
  var state = ThermalGuardState()
  let now = Date(timeIntervalSince1970: 1000)
  _ = state.observe(temperature: 62, at: now)
  _ = state.observe(temperature: 62, at: now.addingTimeInterval(30))
  _ = state.observe(temperature: 55, at: now.addingTimeInterval(31))
  #expect(state.observe(temperature: 54, at: now.addingTimeInterval(61)).mode == .automatic)
}

@Test func ruleMustHaveHysteresis() {
  var rule = GuardConfiguration.defaults.rules[0]
  #expect(rule.isValid)
  rule.recoveryTemperature = rule.triggerTemperature
  #expect(!rule.isValid)
}

@Test func applyingRuleResetsPendingTimer() {
  var state = ThermalGuardState()
  let now = Date(timeIntervalSince1970: 1000)
  _ = state.observe(temperature: 61, at: now)
  state.apply(GuardConfiguration.defaults.rules[0])
  #expect(state.observe(temperature: 61, at: now.addingTimeInterval(30)).mode == .automatic)
}

@Test func multiRuleEscalatesImmediately() {
  let configuration = GuardConfiguration(
    rules: [
      GuardRule(triggerTemperature: 60, triggerDuration: 5, fanSpeedPercent: 60, recoveryTemperature: 55, recoveryDuration: 30),
      GuardRule(triggerTemperature: 75, triggerDuration: 5, fanSpeedPercent: 80, recoveryTemperature: 70, recoveryDuration: 30),
    ]
  )
  var state = MultiRuleGuardState(configuration: configuration)
  let start = Date(timeIntervalSince1970: 0)
  _ = state.observe(temperature: 76, at: start)
  let decision = state.observe(temperature: 76, at: start.addingTimeInterval(5))
  #expect(decision.fanSpeedPercent == 80)
  #expect(decision.activeRuleIndex == 1)
}

@Test func multiRuleDeescalatesStepwise() {
  let configuration = GuardConfiguration(
    rules: [
      GuardRule(triggerTemperature: 60, triggerDuration: 5, fanSpeedPercent: 60, recoveryTemperature: 55, recoveryDuration: 5),
      GuardRule(triggerTemperature: 75, triggerDuration: 5, fanSpeedPercent: 80, recoveryTemperature: 70, recoveryDuration: 5),
    ]
  )
  var state = MultiRuleGuardState(configuration: configuration)
  let start = Date(timeIntervalSince1970: 0)
  _ = state.observe(temperature: 76, at: start)
  _ = state.observe(temperature: 76, at: start.addingTimeInterval(5))
  _ = state.observe(temperature: 69, at: start.addingTimeInterval(10))
  let decision = state.observe(temperature: 69, at: start.addingTimeInterval(15))
  #expect(decision.fanSpeedPercent == 60)
  #expect(decision.activeRuleIndex == 0)
}

@Test func multiRuleRecoversAfterAllRulesRelease() {
  let configuration = GuardConfiguration(
    rules: [
      GuardRule(triggerTemperature: 60, triggerDuration: 5, fanSpeedPercent: 60, recoveryTemperature: 55, recoveryDuration: 5),
    ]
  )
  var state = MultiRuleGuardState(configuration: configuration)
  let start = Date(timeIntervalSince1970: 0)
  _ = state.observe(temperature: 62, at: start)
  _ = state.observe(temperature: 62, at: start.addingTimeInterval(5))
  _ = state.observe(temperature: 54, at: start.addingTimeInterval(10))
  let decision = state.observe(temperature: 54, at: start.addingTimeInterval(15))
  #expect(decision.fanSpeedPercent == nil)
}

@Test func configurationRequiresTwoDegreeSpacing() {
  let configuration = GuardConfiguration(
    rules: [
      GuardRule(triggerTemperature: 60, triggerDuration: 30, fanSpeedPercent: 60, recoveryTemperature: 55, recoveryDuration: 30),
      GuardRule(triggerTemperature: 61, triggerDuration: 30, fanSpeedPercent: 80, recoveryTemperature: 58, recoveryDuration: 30),
    ]
  )
  #expect(!configuration.isValid)
}

@Test func configurationRequiresMonotonicFanSpeed() {
  let configuration = GuardConfiguration(
    rules: [
      GuardRule(triggerTemperature: 60, triggerDuration: 30, fanSpeedPercent: 80, recoveryTemperature: 55, recoveryDuration: 30),
      GuardRule(triggerTemperature: 75, triggerDuration: 30, fanSpeedPercent: 60, recoveryTemperature: 70, recoveryDuration: 30),
    ]
  )
  #expect(!configuration.isValid)
}

@Test func legacyConfigurationDecodesFlatFormat() throws {
  let json = """
  {
    "triggerTemperature": 65,
    "triggerDuration": 20,
    "recoveryTemperature": 58,
    "recoveryDuration": 25
  }
  """.data(using: .utf8)!
  let configuration = try JSONDecoder().decode(GuardConfiguration.self, from: json)
  #expect(configuration.rules.count == 1)
  #expect(configuration.rules[0].triggerTemperature == 65)
  #expect(configuration.rules[0].fanSpeedPercent == 100)
  #expect(configuration.rules[0].recoveryTemperature == 58)
}

@Test func commandExpiresAfterTimeout() {
  let command = GuardCommand(action: .max, issuedAt: Date(timeIntervalSince1970: 0), expiresAfter: 30)
  #expect(command.isExpired(at: Date(timeIntervalSince1970: 29)) == false)
  #expect(command.isExpired(at: Date(timeIntervalSince1970: 30)) == true)
}

@Test func staleCommandIgnored() {
  let daemonStart = Date(timeIntervalSince1970: 100)
  let command = GuardCommand(action: .max, issuedAt: Date(timeIntervalSince1970: 50), expiresAfter: 600)
  #expect(command.isStale(since: daemonStart))
}

@Test func decodesByExplicitDataType() {
  #expect(SMCTemperatureDecoder.decode(bytes: [0x2D, 0x80], size: 2, dataType: "sp78") == 45.5)
}

@Test func overrideTimeoutZeroDoesNotExpire() {
  let command = GuardCommand(action: .max, issuedAt: Date(timeIntervalSince1970: 0), expiresAfter: 0)
  #expect(command.isExpired(at: Date(timeIntervalSince1970: 99999)) == false)
}

@Test func autoOverrideRequestsRuleStateReset() {
  let configuration = GuardConfiguration.defaults
  let daemonStart = Date(timeIntervalSince1970: 100)
  let command = GuardCommand(action: .auto, issuedAt: Date(timeIntervalSince1970: 200), expiresAfter: nil)
  let resolution = GuardOverrideResolver.resolve(
    command: command,
    configuration: configuration,
    daemonStart: daemonStart,
    now: Date(timeIntervalSince1970: 200)
  )
  #expect(resolution.shouldResetRuleState)
  #expect(resolution.shouldClearCommandFile)
  #expect(!resolution.maxOverrideActive)
}

@Test func autoRestoreResetsRuleTimersBeforeReTrigger() {
  let configuration = GuardConfiguration(
    rules: [
      GuardRule(triggerTemperature: 60, triggerDuration: 5, fanSpeedPercent: 80, recoveryTemperature: 55, recoveryDuration: 30),
    ]
  )
  var state = MultiRuleGuardState(configuration: configuration)
  let start = Date(timeIntervalSince1970: 0)
  _ = state.observe(temperature: 65, at: start)
  let triggered = state.observe(temperature: 65, at: start.addingTimeInterval(5))
  #expect(triggered.fanSpeedPercent == 80)

  state = MultiRuleGuardState(configuration: configuration)
  let immediate = state.observe(temperature: 65, at: start.addingTimeInterval(6))
  #expect(immediate.fanSpeedPercent == nil)

  let retriggered = state.observe(temperature: 65, at: start.addingTimeInterval(11))
  #expect(retriggered.fanSpeedPercent == 80)
}

@Test func maxOverrideIgnoresRuleStateUntilCleared() {
  let configuration = GuardConfiguration.defaults
  let daemonStart = Date(timeIntervalSince1970: 0)
  let command = GuardCommand(action: .max, issuedAt: Date(timeIntervalSince1970: 10), expiresAfter: 600)
  let resolution = GuardOverrideResolver.resolve(
    command: command,
    configuration: configuration,
    daemonStart: daemonStart,
    now: Date(timeIntervalSince1970: 10)
  )
  #expect(resolution.maxOverrideActive)
  #expect(!resolution.shouldResetRuleState)
}
