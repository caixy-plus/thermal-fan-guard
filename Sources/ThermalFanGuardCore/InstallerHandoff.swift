import Foundation

/// Written by the installer; consumed on first MyFans launch after install.
public struct InstallerHandoff: Codable, Sendable {
  public var registerLoginItem: Bool
  public var openAfterInstall: Bool

  public init(registerLoginItem: Bool, openAfterInstall: Bool) {
    self.registerLoginItem = registerLoginItem
    self.openAfterInstall = openAfterInstall
  }

  public static let fileURL = URL(
    fileURLWithPath: "/Users/Shared/com.caixinyun.thermal-fan-guard.installer-handoff.json"
  )

  public func write() throws {
    let data = try JSONEncoder().encode(self)
    try data.write(to: Self.fileURL, options: .atomic)
  }

  public static func load() -> InstallerHandoff? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? JSONDecoder().decode(InstallerHandoff.self, from: data)
  }

  public static func consume() -> InstallerHandoff? {
    guard let handoff = load() else { return nil }
    try? FileManager.default.removeItem(at: fileURL)
    return handoff
  }
}
