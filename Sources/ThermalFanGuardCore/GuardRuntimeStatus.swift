import Foundation

public struct FanSnapshot: Codable, Equatable, Sendable {
  public let actual: Int
  public let target: Int
  public let maximum: Int

  public init(actual: Int, target: Int, maximum: Int) {
    self.actual = actual
    self.target = target
    self.maximum = maximum
  }
}

public struct GuardRuntimeStatus: Codable, Sendable {
  public static let fileURL = URL(fileURLWithPath: "/Users/Shared/com.caixinyun.thermal-fan-guard.status.json")

  public let timestamp: Date
  public let temperature: Double?
  public let sensor: String?
  public let validSensorCount: Int?
  public let mode: String
  public let fanStatus: String?
  public let error: String?
  public let fans: [FanSnapshot]?
  public let activeRuleIndex: Int?
  public let fanSpeedPercent: Int?
  public let override: String?

  public init(
    timestamp: Date,
    temperature: Double?,
    sensor: String?,
    validSensorCount: Int?,
    mode: String,
    fanStatus: String?,
    error: String?,
    fans: [FanSnapshot]? = nil,
    activeRuleIndex: Int? = nil,
    fanSpeedPercent: Int? = nil,
    override: String? = "none"
  ) {
    self.timestamp = timestamp
    self.temperature = temperature
    self.sensor = sensor
    self.validSensorCount = validSensorCount
    self.mode = mode
    self.fanStatus = fanStatus
    self.error = error
    self.fans = fans
    self.activeRuleIndex = activeRuleIndex
    self.fanSpeedPercent = fanSpeedPercent
    self.override = override
  }

  public static func load() -> GuardRuntimeStatus? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    if let value = try? decoder.decode(Self.self, from: data) { return value }
    decoder.dateDecodingStrategy = .secondsSince1970
    return try? decoder.decode(Self.self, from: data)
  }

  public func save() {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(self) else { return }
    try? data.write(to: Self.fileURL, options: .atomic)
    try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: Self.fileURL.path)
  }

  public func isOnline(configuration: GuardConfiguration) -> Bool {
    Date().timeIntervalSince(timestamp) < configuration.offlineThreshold
  }
}
