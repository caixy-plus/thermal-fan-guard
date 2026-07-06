import Foundation

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
  public let timestamp: Date
  public let temperature: Double?
  public let mode: String

  public var id: TimeInterval { timestamp.timeIntervalSince1970 }

  public init(timestamp: Date, temperature: Double?, mode: String) {
    self.timestamp = timestamp
    self.temperature = temperature
    self.mode = mode
  }
}

public struct TemperatureHistory: Codable, Sendable {
  public static let fileURL = URL(fileURLWithPath: "/Users/Shared/com.caixinyun.thermal-fan-guard.history.json")

  public let entries: [HistoryEntry]

  public init(entries: [HistoryEntry]) {
    self.entries = entries
  }

  public static func load() -> TemperatureHistory? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    if let value = try? decoder.decode(Self.self, from: data) { return value }
    decoder.dateDecodingStrategy = .secondsSince1970
    return try? decoder.decode(Self.self, from: data)
  }
}

public final class HistoryStore: @unchecked Sendable {
  private var entries: [HistoryEntry] = []
  private var capacity: Int
  private var samplesSinceFlush = 0
  private let lock = NSLock()

  public init(sampleInterval: TimeInterval) {
    capacity = max(1, Int(3600.0 / sampleInterval))
  }

  public func reconfigure(sampleInterval: TimeInterval) {
    lock.lock()
    defer { lock.unlock() }
    capacity = max(1, Int(3600.0 / sampleInterval))
    if entries.count > capacity {
      entries.removeFirst(entries.count - capacity)
    }
  }

  public func append(temperature: Double?, mode: String, at timestamp: Date = Date()) {
    lock.lock()
    entries.append(HistoryEntry(timestamp: timestamp, temperature: temperature, mode: mode))
    if entries.count > capacity {
      entries.removeFirst(entries.count - capacity)
    }
    samplesSinceFlush += 1
    lock.unlock()
  }

  public func flushIfNeeded(force: Bool = false) {
    lock.lock()
    let shouldFlush = force || samplesSinceFlush >= 6
    guard shouldFlush else {
      lock.unlock()
      return
    }
    let snapshot = entries
    samplesSinceFlush = 0
    lock.unlock()

    let history = TemperatureHistory(entries: snapshot)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(history) else { return }
    try? data.write(to: TemperatureHistory.fileURL, options: .atomic)
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: TemperatureHistory.fileURL.path
    )
  }
}
