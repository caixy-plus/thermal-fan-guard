import Foundation
import SMCFanKit
import SMCKit
import ThermalFanGuardCore

public struct TemperatureReading: Sendable {
  public let maximum: Double
  public let sensor: String
  public let validSensorCount: Int
}

public enum GuardError: LocalizedError {
  case noTemperatureSensors, noFans

  public var errorDescription: String? {
    self == .noFans ? "No controllable fans were found" : "No valid temperature sensors were found"
  }
}

public final class ThermalHardware {
  private let sensorConnection: SMCConnection
  private let fanConnection: SMCConnection
  private let controller: FanController
  private let catalog = SensorCatalog.keysForCurrentHardware().filter { $0.type == .temperature }

  public init() throws {
    sensorConnection = try SMCConnection()
    fanConnection = try SMCConnection()
    controller = FanController(connection: fanConnection)
  }

  public func readMaximumTemperature(sensorGroups: Set<String>) throws -> TemperatureReading {
    let allowed = Set(sensorGroups.map { $0.lowercased() })
    var values = readCatalogTemperatures(allowedGroups: allowed)
    if values.isEmpty {
      values = discoverTemperatures(allowedGroups: allowed)
    }
    guard let hottest = values.max(by: { $0.1 < $1.1 }) else { throw GuardError.noTemperatureSensors }
    return .init(maximum: hottest.1, sensor: hottest.0, validSensorCount: values.count)
  }

  public func readFans() throws -> [FanSnapshot] {
    try (0..<fanCount()).map { index in
      FanSnapshot(
        actual: Int(try read(index, SMCFanKey.actual)),
        target: Int(try read(index, SMCFanKey.target)),
        maximum: Int(try read(index, SMCFanKey.maximum))
      )
    }
  }

  public func fanStatus() throws -> String {
    try readFans().enumerated().map { index, fan in
      "fan\(index)=\(fan.actual)rpm target=\(fan.target) max=\(fan.maximum)"
    }.joined(separator: " ")
  }

  public func setFans(toPercent percent: Int) throws {
    let clamped = min(100, max(30, percent))
    let count = try fanCount()
    for index in 0..<count {
      let maximum = try read(index, SMCFanKey.maximum)
      let target = Float((Double(maximum) * Double(clamped) / 100.0).rounded())
      _ = try controller.enableManualMode(fanIndex: index)
      try write(index, SMCFanKey.target, target)
    }
  }

  public func setFansToMaximum() throws {
    try setFans(toPercent: 100)
  }

  public func restoreAutomaticControl() throws {
    let count = try fanCount()
    for index in 0..<count {
      try? fanConnection.writeKey(SMCFanKey.key(controller.config.modeKeyFormat, fan: index), bytes: [0])
      try? write(index, SMCFanKey.target, 0)
    }
    if controller.config.ftstAvailable,
       let (bytes, _) = try? fanConnection.readKey(SMCFanKey.forceTest), bytes.first == 1 {
      try controller.resetFanControl()
    }
  }

  private func readCatalogTemperatures(allowedGroups: Set<String>) -> [(String, Double)] {
    var values: [(String, Double)] = []
    for sensor in catalog where allowedGroups.contains(sensor.group.rawValue) {
      guard let value = readTemperature(key: sensor.key) else { continue }
      values.append((sensor.name, value))
    }
    return values
  }

  private func discoverTemperatures(allowedGroups: Set<String>) -> [(String, Double)] {
    let knownNames = Dictionary(uniqueKeysWithValues: catalog.map { ($0.key, $0.name) })
    let knownGroups = Dictionary(uniqueKeysWithValues: catalog.map { ($0.key, $0.group.rawValue) })
    var values: [(String, Double)] = []

    for key in sensorConnection.enumerateKeys() where isTemperatureKeyCandidate(key) {
      let group = knownGroups[key] ?? inferredGroup(for: key)
      guard allowedGroups.contains(group) else { continue }
      guard let value = readTemperature(key: key) else { continue }
      values.append((knownNames[key] ?? key, value))
    }

    if values.isEmpty {
      for key in sensorConnection.enumerateKeys() where isTemperatureKeyCandidate(key) {
        guard let value = readTemperature(key: key) else { continue }
        values.append((knownNames[key] ?? key, value))
      }
    }
    return values
  }

  private func readTemperature(key: String) -> Double? {
    guard let (bytes, size) = try? sensorConnection.readKey(key) else { return nil }
    if let value = SMCTemperatureDecoder.decode(bytes: bytes, size: size) {
      return value
    }
    guard let (_, info) = try? sensorConnection.fetchKeyInfo(key) else { return nil }
    let dataType = Self.dataTypeString(info.keyInfo.dataType)
    return SMCTemperatureDecoder.decode(bytes: bytes, size: size, dataType: dataType)
  }

  private func isTemperatureKeyCandidate(_ key: String) -> Bool {
    key.count == 4 && key.hasPrefix("T")
  }

  private func inferredGroup(for key: String) -> String {
    if key.hasPrefix("Tg") { return "gpu" }
    if key.hasPrefix("Te") || key.hasPrefix("Tp") || key.hasPrefix("Tf") || key.hasPrefix("TC") {
      return "cpu"
    }
    return "cpu"
  }

  private static func dataTypeString(_ raw: UInt32) -> String {
    let bytes: [UInt8] = [
      UInt8((raw >> 24) & 0xFF),
      UInt8((raw >> 16) & 0xFF),
      UInt8((raw >> 8) & 0xFF),
      UInt8(raw & 0xFF),
    ]
    return String(bytes: bytes, encoding: .ascii) ?? ""
  }

  private func fanCount() throws -> Int {
    let (bytes, _) = try fanConnection.readKey(SMCFanKey.count)
    guard let count = bytes.first, count > 0 else { throw GuardError.noFans }
    return Int(count)
  }

  private func read(_ index: Int, _ format: String) throws -> Float {
    let (bytes, size) = try fanConnection.readKey(SMCFanKey.key(format, fan: index))
    return SMCDataFormat.float(from: bytes, size: size)
  }

  private func write(_ index: Int, _ format: String, _ value: Float) throws {
    let key = SMCFanKey.key(format, fan: index)
    let (_, size) = try fanConnection.readKey(key)
    try fanConnection.writeKey(key, bytes: SMCDataFormat.bytes(from: value, size: size))
  }
}
