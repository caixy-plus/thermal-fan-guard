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

@Test func configurationResetRequestsHardwareAutomaticRestore() {
  let original = GuardConfiguration(
    rules: [
      GuardRule(triggerTemperature: 60, triggerDuration: 5, fanSpeedPercent: 100, recoveryTemperature: 55, recoveryDuration: 5),
    ]
  )
  var state = MultiRuleGuardState(configuration: original)
  let start = Date(timeIntervalSince1970: 0)
  _ = state.observe(temperature: 62, at: start)
  _ = state.observe(temperature: 62, at: start.addingTimeInterval(5))
  #expect(state.fanSpeedPercent == 100)

  let edited = GuardConfiguration(
    rules: [
      GuardRule(triggerTemperature: 70, triggerDuration: 30, fanSpeedPercent: 100, recoveryTemperature: 60, recoveryDuration: 10),
    ]
  )

  let requiresRestore = state.apply(edited)
  #expect(requiresRestore)
  #expect(state.fanSpeedPercent == nil)
}

@Test func freshDaemonStateRequestsHardwareAutomaticControl() {
  let state = MultiRuleGuardState(configuration: .defaults)

  #expect(state.hardwareAction == .restoreAutomatic)
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

@Test func editingNormalizationKeepsRecoveryBelowChangedTrigger() {
  let configuration = GuardConfiguration(
    rules: [
      GuardRule(triggerTemperature: 45, triggerDuration: 30, fanSpeedPercent: 100, recoveryTemperature: 55, recoveryDuration: 30),
    ]
  )

  let normalized = configuration.normalizedForEditing()

  #expect(normalized.isValid)
  #expect(normalized.rules[0].triggerTemperature == 45)
  #expect(normalized.rules[0].recoveryTemperature == 44)
}

@Test func editingNormalizationClampsGlobalAndRuleFields() {
  let configuration = GuardConfiguration(
    rules: [
      GuardRule(triggerTemperature: 140, triggerDuration: 1, fanSpeedPercent: 10, recoveryTemperature: 10, recoveryDuration: 900),
    ],
    sampleInterval: 1,
    overrideTimeout: 123,
    sensorGroups: []
  )

  let normalized = configuration.normalizedForEditing()

  #expect(normalized.isValid)
  #expect(normalized.rules[0].triggerTemperature == 120)
  #expect(normalized.rules[0].triggerDuration == 5)
  #expect(normalized.rules[0].fanSpeedPercent == 30)
  #expect(normalized.rules[0].recoveryTemperature == 20)
  #expect(normalized.rules[0].recoveryDuration == 600)
  #expect(normalized.sampleInterval == 2)
  #expect(normalized.overrideTimeout == 1800)
  #expect(normalized.sensorGroups == ["cpu", "gpu"])
}

@Test func uninstallScriptRemovesInstalledComponents() {
  let script = UninstallScript.shellScript()

  #expect(script.contains("/Applications/MyFans.app"))
  #expect(script.contains("/Library/LaunchDaemons/com.caixinyun.thermal-fan-guard.plist"))
  #expect(script.contains("/usr/local/libexec/thermal-fan-guard"))
  #expect(script.contains("/Users/Shared/com.caixinyun.thermal-fan-guard.status.json"))
  #expect(script.contains("lsregister"))
}

@Test func appVersionDisplaysBuildWhenDifferent() {
  #expect(AppVersion(shortVersion: "2.1", build: "21").displayText == "2.1 (21)")
  #expect(AppVersion(shortVersion: "2.1", build: "2.1").displayText == "2.1")
  #expect(AppVersion(shortVersion: "2.1", build: "").displayText == "2.1")
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

@Test func commandJSONRoundTrip() throws {
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  encoder.outputFormatting = [.sortedKeys]
  let original = GuardCommand(action: .max, issuedAt: Date(timeIntervalSince1970: 1_700_000_000), expiresAfter: 1800)
  let data = try encoder.encode(original)
  let decoded = try #require(GuardCommand.decodeForTesting(data))
  #expect(decoded.action == .max)
  #expect(decoded.expiresAfter == 1800)
}

@Test func commandDecodesWithoutFractionalSeconds() throws {
  let json = """
  {"action":"max","expiresAfter":1800,"issuedAt":"2026-07-06T12:42:21Z"}
  """.data(using: .utf8)!
  let decoded = try #require(GuardCommand.decodeForTesting(json))
  #expect(decoded.action == .max)
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

@Test func rejectsSp78MisdecodeBeforeTryingFpe2() {
  #expect(SMCTemperatureDecoder.decode(bytes: [0x00, 0xF0], size: 2) == 60.0)
}

@Test func rejectsImplausibleLowTemperature() {
  #expect(SMCTemperatureDecoder.decode(bytes: [0x00, 0x80], size: 2, dataType: "sp78") == nil)
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

@Test func temperaturePresentationDoesNotRoundAcrossRecoveryThreshold() {
  #expect(TemperaturePresentation.menuBarText(60.315) == " 60.3°")
}

@Test func rulePresentationIncludesRecoveryDuration() {
  let rule = GuardRule(
    triggerTemperature: 65,
    triggerDuration: 30,
    fanSpeedPercent: 100,
    recoveryTemperature: 60,
    recoveryDuration: 10
  )

  #expect(TemperaturePresentation.ruleSummary(rule, marker: "I") == "I ≥65° 30s → 100% (≤60° 持续10s 解除)")
}

@Test func fullSpeedDisablesBoostAndEnablesRestore() {
  let status = GuardRuntimeStatus(
    timestamp: Date(),
    temperature: 70,
    sensor: "test",
    validSensorCount: 1,
    mode: "maximum",
    fanStatus: nil,
    error: nil,
    fanSpeedPercent: 100,
    override: "none"
  )

  let availability = FanControlAvailability(
    status: status,
    canControlFans: true,
    isBusy: false
  )

  #expect(!availability.canBoostToMax)
  #expect(availability.canRestoreAutomatic)
}

@Test func identicalStatusEventsShareNotificationIdentifier() {
  let first = StatusNotificationIdentifier(kind: .recovered)
  let duplicate = StatusNotificationIdentifier(kind: .recovered)
  let escalation = StatusNotificationIdentifier(kind: .escalated(ruleIndex: 0, percent: 100))

  #expect(first.value == duplicate.value)
  #expect(first.value != escalation.value)
}

@Test func sustainedManualMaximumDoesNotEmitRepeatedRecovery() {
  var tracker = StatusNotificationTracker()
  tracker.seed(
    activeRuleIndex: nil,
    fanSpeedPercent: nil,
    override: "none"
  )

  #expect(tracker.transition(
    activeRuleIndex: nil,
    fanSpeedPercent: 100,
    override: "max"
  ) == .manualMaximumEnabled)
  #expect(tracker.transition(
    activeRuleIndex: nil,
    fanSpeedPercent: 100,
    override: "max"
  ) == nil)
}

@Test func unchangedFullSpeedDoesNotEmitAnotherEscalation() {
  var tracker = StatusNotificationTracker()
  tracker.seed(
    activeRuleIndex: 0,
    fanSpeedPercent: 100,
    override: "none"
  )

  #expect(tracker.transition(
    activeRuleIndex: 1,
    fanSpeedPercent: 100,
    override: "none"
  ) == nil)
}

@Test func oneAutoCancelsRepeatedMaxIncludingLateWrites() {
  let configuration = GuardConfiguration.defaults
  let daemonStart = Date(timeIntervalSince1970: 100)
  var controller = GuardOverrideController()

  let firstMax = GuardCommand(
    action: .max,
    issuedAt: Date(timeIntervalSince1970: 110),
    expiresAfter: 600
  )
  let secondMax = GuardCommand(
    action: .max,
    issuedAt: Date(timeIntervalSince1970: 120),
    expiresAfter: 600
  )
  let restore = GuardCommand(
    action: .auto,
    issuedAt: Date(timeIntervalSince1970: 130),
    expiresAfter: nil
  )

  #expect(controller.resolve(
    command: firstMax,
    configuration: configuration,
    daemonStart: daemonStart,
    now: Date(timeIntervalSince1970: 110)
  ).maxOverrideActive)
  #expect(controller.resolve(
    command: secondMax,
    configuration: configuration,
    daemonStart: daemonStart,
    now: Date(timeIntervalSince1970: 120)
  ).maxOverrideActive)

  let restored = controller.resolve(
    command: restore,
    configuration: configuration,
    daemonStart: daemonStart,
    now: Date(timeIntervalSince1970: 130)
  )
  #expect(!restored.maxOverrideActive)
  #expect(restored.shouldResetRuleState)

  let lateMax = controller.resolve(
    command: secondMax,
    configuration: configuration,
    daemonStart: daemonStart,
    now: Date(timeIntervalSince1970: 131)
  )
  #expect(!lateMax.maxOverrideActive)
  #expect(lateMax.shouldClearCommandFile)
}
