import Foundation

public struct GuardRule: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var triggerTemperature: Double
  public var triggerDuration: TimeInterval
  public var fanSpeedPercent: Int
  public var recoveryTemperature: Double
  public var recoveryDuration: TimeInterval

  public init(
    id: UUID = UUID(),
    triggerTemperature: Double,
    triggerDuration: TimeInterval,
    fanSpeedPercent: Int,
    recoveryTemperature: Double,
    recoveryDuration: TimeInterval
  ) {
    self.id = id
    self.triggerTemperature = triggerTemperature
    self.triggerDuration = triggerDuration
    self.fanSpeedPercent = fanSpeedPercent
    self.recoveryTemperature = recoveryTemperature
    self.recoveryDuration = recoveryDuration
  }

  public var isValid: Bool {
    (30...120).contains(triggerTemperature)
      && (20..<triggerTemperature).contains(recoveryTemperature)
      && (5...600).contains(triggerDuration)
      && (5...600).contains(recoveryDuration)
      && (30...100).contains(fanSpeedPercent)
  }
}
