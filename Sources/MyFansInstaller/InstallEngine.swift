import AppKit
import Foundation

enum InstallStep: Int, CaseIterable, Identifiable {
  case copyApplication
  case installDaemon
  case startService

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .copyApplication: "复制菜单栏应用"
    case .installDaemon: "安装后台守护进程"
    case .startService: "注册并启动系统服务"
    }
  }

  var systemImage: String {
    switch self {
    case .copyApplication: "app.fill"
    case .installDaemon: "gearshape.2.fill"
    case .startService: "power"
    }
  }
}

enum InstallEngineError: LocalizedError {
  case missingPayload(String)
  case privilegedCommandFailed(String)

  var errorDescription: String? {
    switch self {
    case .missingPayload(let name):
      "安装包缺少资源：\(name)"
    case .privilegedCommandFailed(let detail):
      detail
    }
  }
}

struct InstallEngine {
  private let label = "com.caixinyun.thermal-fan-guard"
  private let appDestination = "/Applications/MyFans.app"
  private let oldApp = "/Applications/Thermal Fan Guard.app"
  private let daemonDestination = "/usr/local/libexec/thermal-fan-guard"
  private let plistDestination = "/Library/LaunchDaemons/com.caixinyun.thermal-fan-guard.plist"

  func copyApplication() async throws {
    let payload = try payloadDirectory()
    let appSource = payload.appendingPathComponent("MyFans.app").path
    try await privilegedShell(
      """
      /bin/rm -rf '\(shellQuote(appDestination))' '\(shellQuote(oldApp))'
      /usr/bin/ditto '\(shellQuote(appSource))' '\(shellQuote(appDestination))'
      /usr/sbin/chown -R root:wheel '\(shellQuote(appDestination))'
      """
    )
  }

  func installDaemonAndStartService() async throws {
    let payload = try payloadDirectory()
    let daemonSource = payload.appendingPathComponent("thermal-fan-guard").path
    let plistSource = payload.appendingPathComponent("\(label).plist").path
    try await privilegedShell(
      """
      /bin/mkdir -p /usr/local/libexec
      /bin/launchctl bootout system '\(shellQuote(plistDestination))' 2>/dev/null || true
      /usr/bin/install -o root -g wheel -m 0755 '\(shellQuote(daemonSource))' '\(shellQuote(daemonDestination))'
      /usr/bin/install -o root -g wheel -m 0644 '\(shellQuote(plistSource))' '\(shellQuote(plistDestination))'
      /bin/launchctl bootstrap system '\(shellQuote(plistDestination))'
      /bin/launchctl enable system/\(label)
      """
    )
  }

  private func payloadDirectory() throws -> URL {
    guard let resources = Bundle.main.resourceURL else {
      throw InstallEngineError.missingPayload("Resources")
    }
    let payload = resources.appendingPathComponent("Payload", isDirectory: true)
    guard FileManager.default.fileExists(atPath: payload.path) else {
      throw InstallEngineError.missingPayload("Payload")
    }
    return payload
  }

  private func privilegedShell(_ script: String) async throws {
    let escaped = script
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    let source = "do shell script \"\(escaped)\" with administrator privileges"

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      DispatchQueue.global(qos: .userInitiated).async {
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: source) else {
          continuation.resume(throwing: InstallEngineError.privilegedCommandFailed("无法创建安装脚本"))
          return
        }
        _ = appleScript.executeAndReturnError(&error)
        if let error {
          let message = (error[NSAppleScript.errorMessage] as? String) ?? "安装失败"
          if message.localizedCaseInsensitiveContains("canceled") || message.contains("-128") {
            continuation.resume(throwing: InstallEngineError.privilegedCommandFailed("已取消安装"))
          } else {
            continuation.resume(throwing: InstallEngineError.privilegedCommandFailed(message))
          }
        } else {
          continuation.resume()
        }
      }
    }
  }

  private func shellQuote(_ value: String) -> String {
    value.replacingOccurrences(of: "'", with: "'\\''")
  }
}
