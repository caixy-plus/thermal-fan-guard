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

  public func normalizedForEditing() -> GuardConfiguration {
    var normalizedRules = Array(rules.prefix(8))
    if normalizedRules.isEmpty {
      normalizedRules = Self.defaults.rules
    }

    normalizedRules = normalizedRules.map { rule in
      var copy = rule
      copy.triggerTemperature = copy.triggerTemperature.clamped(to: 30...120)
      copy.triggerDuration = copy.triggerDuration.clamped(to: 5...600)
      copy.fanSpeedPercent = copy.fanSpeedPercent.clamped(to: 30...100)
      copy.recoveryTemperature = copy.recoveryTemperature.clamped(to: 20...(copy.triggerTemperature - 1))
      copy.recoveryDuration = copy.recoveryDuration.clamped(to: 5...600)
      return copy
    }
    .sorted { $0.triggerTemperature < $1.triggerTemperature }

    for index in normalizedRules.indices.dropFirst() {
      let previousTrigger = normalizedRules[index - 1].triggerTemperature
      normalizedRules[index].triggerTemperature = max(normalizedRules[index].triggerTemperature, previousTrigger + 2)
    }

    if let lastTrigger = normalizedRules.last?.triggerTemperature, lastTrigger > 120 {
      let overflow = lastTrigger - 120
      for index in normalizedRules.indices {
        normalizedRules[index].triggerTemperature -= overflow
      }
    }

    for index in normalizedRules.indices {
      if index > normalizedRules.startIndex {
        normalizedRules[index].fanSpeedPercent = max(
          normalizedRules[index].fanSpeedPercent,
          normalizedRules[index - 1].fanSpeedPercent
        )
      }
      normalizedRules[index].recoveryTemperature = normalizedRules[index].recoveryTemperature.clamped(
        to: 20...(normalizedRules[index].triggerTemperature - 1)
      )
    }

    let allowedTimeouts: Set<TimeInterval> = [600, 1800, 3600, 0]
    let filteredGroups = sensorGroups.filter { ["cpu", "gpu"].contains($0) }
    let safeGroups = filteredGroups.isEmpty ? Self.defaults.sensorGroups : Array(Set(filteredGroups)).sorted()

    return GuardConfiguration(
      rules: normalizedRules,
      sampleInterval: sampleInterval.clamped(to: 2...30),
      overrideTimeout: allowedTimeouts.contains(overrideTimeout) ? overrideTimeout : Self.defaults.overrideTimeout,
      sensorGroups: safeGroups
    )
  }

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

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(range.upperBound, max(range.lowerBound, self))
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
