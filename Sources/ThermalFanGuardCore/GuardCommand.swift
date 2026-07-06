import Foundation

public struct GuardCommand: Codable, Sendable {
  public enum Action: String, Codable, Sendable {
    case max
    case auto
    case clear
  }

  public static let fileURL = URL(fileURLWithPath: "/Users/Shared/com.caixinyun.thermal-fan-guard.command.json")

  public let action: Action
  public let issuedAt: Date
  public let expiresAfter: TimeInterval?

  public init(action: Action, issuedAt: Date = Date(), expiresAfter: TimeInterval?) {
    self.action = action
    self.issuedAt = issuedAt
    self.expiresAfter = expiresAfter
  }

  public static func load() -> GuardCommand? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(Self.self, from: data)
  }

  public static func issueMax(expiresAfter: TimeInterval?) throws {
    try save(GuardCommand(action: .max, expiresAfter: expiresAfter))
  }

  public static func issueAuto() throws {
    try save(GuardCommand(action: .auto, expiresAfter: nil))
  }

  public static func clear() {
    try? FileManager.default.removeItem(at: fileURL)
  }

  public func isExpired(at now: Date = Date()) -> Bool {
    guard let expiresAfter, expiresAfter > 0 else { return false }
    return now.timeIntervalSince(issuedAt) >= expiresAfter
  }

  public func isStale(since daemonStart: Date, at now: Date = Date()) -> Bool {
    issuedAt < daemonStart || isExpired(at: now)
  }

  private static func save(_ command: GuardCommand) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(command)
    try data.write(to: fileURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
  }
}
