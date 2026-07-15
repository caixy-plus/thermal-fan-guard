public struct FanControlAvailability: Equatable, Sendable {
  public let canBoostToMax: Bool
  public let canRestoreAutomatic: Bool

  public init(
    status: GuardRuntimeStatus?,
    canControlFans: Bool,
    isBusy: Bool
  ) {
    let isFullSpeed = status?.override == "max"
      || (status?.fanSpeedPercent == 100 && status?.mode != "automatic")
    let isFanControlActive = status?.override == "max"
      || status?.mode == "boosted"
      || status?.fanSpeedPercent != nil

    canBoostToMax = canControlFans && !isBusy && !isFullSpeed
    canRestoreAutomatic = canControlFans && !isBusy && isFanControlActive
  }
}
