import Foundation

public struct GuardConfiguration: Codable, Equatable, Sendable {
  public static let fileURL = URL(fileURLWithPath: "/Users/Shared/com.caixinyun.thermal-fan-guard.json")

  public static let defaults = GuardConfiguration(
    rules: [
      GuardRule(
        triggerTemperature: 60,
        triggerDuration: 30,
        fanSpeedPercent: 100,
        recoveryTemperature: 55,
        recoveryDuration: 30
      ),
    ],
    sampleInterval: 5,
    overrideTimeout: 1800,
    sensorGroups: ["cpu", "gpu"]
  )

  public var rules: [GuardRule]
  public var sampleInterval: TimeInterval
  public var overrideTimeout: TimeInterval
  public var sensorGroups: [String]

  public init(
    rules: [GuardRule],
    sampleInterval: TimeInterval = 5,
    overrideTimeout: TimeInterval = 1800,
    sensorGroups: [String] = ["cpu", "gpu"]
  ) {
    self.rules = rules
    self.sampleInterval = sampleInterval
    self.overrideTimeout = overrideTimeout
    self.sensorGroups = sensorGroups
  }

  private enum CodingKeys: String, CodingKey {
    case rules
    case sampleInterval
    case overrideTimeout
    case sensorGroups
    case triggerTemperature
    case triggerDuration
    case recoveryTemperature
    case recoveryDuration
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let rules = try container.decodeIfPresent([GuardRule].self, forKey: .rules) {
      self.rules = rules
      self.sampleInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .sampleInterval) ?? 5
      self.overrideTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .overrideTimeout) ?? 1800
      self.sensorGroups = try container.decodeIfPresent([String].self, forKey: .sensorGroups) ?? ["cpu", "gpu"]
    } else {
      let trigger = try container.decode(Double.self, forKey: .triggerTemperature)
      let triggerDur = try container.decode(TimeInterval.self, forKey: .triggerDuration)
      let recovery = try container.decode(Double.self, forKey: .recoveryTemperature)
      let recoveryDur = try container.decode(TimeInterval.self, forKey: .recoveryDuration)
      self.rules = [
        GuardRule(
          triggerTemperature: trigger,
          triggerDuration: triggerDur,
          fanSpeedPercent: 100,
          recoveryTemperature: recovery,
          recoveryDuration: recoveryDur
        ),
      ]
      self.sampleInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .sampleInterval) ?? 5
      self.overrideTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .overrideTimeout) ?? 1800
      self.sensorGroups = try container.decodeIfPresent([String].self, forKey: .sensorGroups) ?? ["cpu", "gpu"]
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(sortedRules, forKey: .rules)
    try container.encode(sampleInterval, forKey: .sampleInterval)
    try container.encode(overrideTimeout, forKey: .overrideTimeout)
    try container.encode(sensorGroups, forKey: .sensorGroups)
  }

  public var sortedRules: [GuardRule] {
    rules.sorted { $0.triggerTemperature < $1.triggerTemperature }
  }

  public var isValid: Bool { validation.isValid }

  public var validation: ConfigurationValidation {
    var errors: [String] = []
    var warnings: [String] = []

    guard (1...8).contains(rules.count) else {
      errors.append("Configure between 1 and 8 rules.")
      return ConfigurationValidation(errors: errors, warnings: warnings)
    }

    if !(2...30).contains(sampleInterval) {
      errors.append("Sample interval must be between 2 and 30 seconds.")
    }

    let allowedTimeouts: Set<TimeInterval> = [600, 1800, 3600, 0]
    if !allowedTimeouts.contains(overrideTimeout) {
      errors.append("Override timeout must be 10 min, 30 min, 1 hour, or unlimited.")
    }

    let groups = Set(sensorGroups)
    if groups.isEmpty || !groups.isSubset(of: ["cpu", "gpu"]) {
      errors.append("Sensor groups must be a non-empty subset of CPU and GPU.")
    }

    for (index, rule) in rules.enumerated() {
      if !rule.isValid {
        errors.append("Rule \(index + 1) has invalid temperature, duration, or fan speed values.")
      }
    }

    let sorted = sortedRules
    for index in 1..<sorted.count {
      let gap = sorted[index].triggerTemperature - sorted[index - 1].triggerTemperature
      if gap < 2 {
        errors.append("Rules \(index) and \(index + 1) must differ by at least 2°C in trigger temperature.")
      }
      if sorted[index].fanSpeedPercent < sorted[index - 1].fanSpeedPercent {
        errors.append("Rule \(index + 1) fan speed cannot be lower than rule \(index).")
      }
    }

    if let highest = sorted.last, highest.fanSpeedPercent < 100 {
      warnings.append("Consider setting the highest rule to 100% for overheating protection.")
    }

    return ConfigurationValidation(errors: errors, warnings: warnings)
  }

  public var offlineThreshold: TimeInterval { 4 * sampleInterval }

  public static func load() -> GuardConfiguration {
    guard let data = try? Data(contentsOf: fileURL),
          let value = try? JSONDecoder().decode(Self.self, from: data),
          value.isValid else { return .defaults }
    return value
  }

  public func save() throws {
    guard isValid else { throw ConfigurationError.invalidRules(validation.errors.joined(separator: " ")) }
    var copy = self
    copy.rules = sortedRules
    let data = try JSONEncoder.pretty.encode(copy)
    try data.write(to: Self.fileURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: Self.fileURL.path)
  }
}

public struct ConfigurationValidation: Equatable, Sendable {
  public let errors: [String]
  public let warnings: [String]

  public var isValid: Bool { errors.isEmpty }
}

public enum ConfigurationError: LocalizedError {
  case invalidRules(String)

  public var errorDescription: String? {
    switch self {
    case .invalidRules(let message): message
    }
  }
}

private extension JSONEncoder {
  static var pretty: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}
