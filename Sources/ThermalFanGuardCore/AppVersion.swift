import Foundation

public struct AppVersion: Equatable, Sendable {
  public let shortVersion: String
  public let build: String

  public init(shortVersion: String, build: String) {
    self.shortVersion = shortVersion
    self.build = build
  }

  public var displayText: String {
    guard !build.isEmpty, build != shortVersion else { return shortVersion }
    return "\(shortVersion) (\(build))"
  }
}
