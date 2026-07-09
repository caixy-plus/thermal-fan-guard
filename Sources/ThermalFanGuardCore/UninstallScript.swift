import Foundation

public enum UninstallScript {
  public static func shellScript() -> String {
    let label = "com.caixinyun.thermal-fan-guard"
    let plist = "/Library/LaunchDaemons/\(label).plist"
    let app = "/Applications/MyFans.app"
    let oldApp = "/Applications/Thermal Fan Guard.app"
    let daemon = "/usr/local/libexec/thermal-fan-guard"
    let sharedPrefix = "/Users/Shared/com.caixinyun.thermal-fan-guard"
    let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    return """
    set -euo pipefail
    launchctl bootout system \(shellQuote(plist)) 2>/dev/null || true
    \(shellQuote(lsregister)) -u \(shellQuote(app)) 2>/dev/null || true
    rm -rf \(shellQuote(app)) \(shellQuote(oldApp))
    rm -f \(shellQuote(plist)) \(shellQuote(daemon)) \\
      \(shellQuote("\(sharedPrefix).status.json")) \\
      \(shellQuote("\(sharedPrefix).history.json")) \\
      \(shellQuote("\(sharedPrefix).command.json"))
    """
  }

  private static func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
  }
}
