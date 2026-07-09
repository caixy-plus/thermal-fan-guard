import AppKit
import Dispatch
import Foundation
import ThermalFanGuardCore

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var status: GuardRuntimeStatus?
  @Published private(set) var configuration = GuardConfiguration.load()
  @Published private(set) var history: [HistoryEntry] = []
  @Published private(set) var pendingManualOverride: GuardCommand.Action?
  @Published private(set) var manualOverrideError: String?
  @Published var showMenuBarTemperature = AppPreferences.showMenuBarTemperature
  @Published var notifyOnChange = AppPreferences.notifyOnChange
  @Published var notifyOnDeescalation = AppPreferences.notifyOnDeescalation
  @Published private(set) var isUninstalling = false
  @Published private(set) var uninstallError: String?

  let loginItems = LoginItemManager()
  let notifications = NotificationManager()

  private var statusSource: DispatchSourceFileSystemObject?
  private var historySource: DispatchSourceFileSystemObject?
  private var configSource: DispatchSourceFileSystemObject?
  private var fallbackTimer: Timer?
  private var overrideTimeoutTask: Task<Void, Never>?
  private var lastManualControlIssuedAt: Date?

  /// Minimum gap between manual fan commands (daemon applies on next sample tick).
  private var manualControlCooldown: TimeInterval {
    configuration.sampleInterval + 2
  }

  var isDaemonOnline: Bool {
    guard let status else { return false }
    return status.isOnline(configuration: configuration)
  }

  var hasSamplingError: Bool {
    guard let status, isDaemonOnline else { return false }
    return status.error != nil || status.temperature == nil
  }

  var menuBarTemperatureText: String {
    guard showMenuBarTemperature, isDaemonOnline, let temperature = status?.temperature else { return "" }
    return String(format: " %.0f°", temperature)
  }

  var isMaxMode: Bool {
    if pendingManualOverride == .max { return true }
    return status?.override == "max" || (status?.fanSpeedPercent == 100 && status?.mode != "automatic")
  }

  var isManualOverridePending: Bool {
    pendingManualOverride != nil
  }

  /// True while a command is in flight or within the post-issue cooldown window.
  var isManualControlBusy: Bool {
    if pendingManualOverride != nil { return true }
    guard let lastManualControlIssuedAt else { return false }
    return Date().timeIntervalSince(lastManualControlIssuedAt) < manualControlCooldown
  }

  var canIssueBoostToMax: Bool {
    canControlFans && !isManualControlBusy && status?.override != "max"
  }

  var canIssueRestoreAutomatic: Bool {
    canControlFans && !isManualControlBusy && isFanControlActive
  }

  private var isFanControlActive: Bool {
    status?.override == "max" || status?.mode == "boosted" || status?.fanSpeedPercent != nil
  }

  var canControlFans: Bool {
    isDaemonOnline
  }

  init() {
    reloadAll()
    startWatching()
    loginItems.refresh()
    applyInstallerHandoffIfNeeded()
    fallbackTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.reloadAll() }
    }
    Task { await notifications.requestAuthorizationIfNeeded() }
  }

  func reloadAll() {
    configuration = GuardConfiguration.load()
    status = GuardRuntimeStatus.load()
    history = TemperatureHistory.load()?.entries ?? []
    if let status {
      reconcilePendingOverride(with: status)
      notifications.handleStatusChange(status: status, configuration: configuration)
    }
  }

  func setShowMenuBarTemperature(_ value: Bool) {
    showMenuBarTemperature = value
    AppPreferences.showMenuBarTemperature = value
  }

  func setNotifyOnChange(_ value: Bool) {
    notifyOnChange = value
    AppPreferences.notifyOnChange = value
    if value {
      Task { await notifications.requestAuthorizationIfNeeded() }
    }
  }

  func setNotifyOnDeescalation(_ value: Bool) {
    notifyOnDeescalation = value
    AppPreferences.notifyOnDeescalation = value
  }

  func boostToMax() {
    guard canIssueBoostToMax else { return }
    issueManualOverride(expected: .max) {
      let timeout = configuration.overrideTimeout > 0 ? configuration.overrideTimeout : nil
      try GuardCommand.issueMax(expiresAfter: timeout)
    }
  }

  func restoreAutomatic() {
    guard canIssueRestoreAutomatic else { return }
    issueManualOverride(expected: .auto) {
      try GuardCommand.issueAuto()
    }
  }

  private func issueManualOverride(expected: GuardCommand.Action, write: () throws -> Void) {
    guard canControlFans, !isManualControlBusy else { return }
    do {
      try write()
      pendingManualOverride = expected
      manualOverrideError = nil
      lastManualControlIssuedAt = Date()
      reloadAll()
      scheduleOverrideTimeout(expected: expected)
      scheduleCooldownRefresh()
    } catch {
      pendingManualOverride = nil
      manualOverrideError = error.localizedDescription
    }
  }

  private func scheduleCooldownRefresh() {
    let delay = manualControlCooldown
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      await MainActor.run { self?.objectWillChange.send() }
    }
  }

  private func scheduleOverrideTimeout(expected: GuardCommand.Action) {
    overrideTimeoutTask?.cancel()
    let timeout = manualControlCooldown + 3
    overrideTimeoutTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(timeout))
      await MainActor.run {
        guard let self, !Task.isCancelled, self.pendingManualOverride == expected else { return }
        switch expected {
        case .max where self.status?.override != "max":
          self.manualOverrideError = "守护进程未响应，请查看日志。"
          self.pendingManualOverride = nil
        case .auto where self.status?.override == "max" || self.status?.mode == "boosted":
          self.manualOverrideError = "守护进程未响应，请查看日志。"
          self.pendingManualOverride = nil
        default:
          break
        }
      }
    }
  }

  private func reconcilePendingOverride(with status: GuardRuntimeStatus) {
    switch pendingManualOverride {
    case .max where status.override == "max":
      pendingManualOverride = nil
      manualOverrideError = nil
      overrideTimeoutTask?.cancel()
    case .auto where status.override != "max" && status.mode != "boosted":
      pendingManualOverride = nil
      manualOverrideError = nil
      overrideTimeoutTask?.cancel()
    default:
      break
    }
  }

  func openLog() {
    NSWorkspace.shared.open(URL(fileURLWithPath: "/var/log/thermal-fan-guard.log"))
  }

  func openInstallInstructions() {
    if let readme = Bundle.main.url(forResource: "README", withExtension: "md") {
      NSWorkspace.shared.open(readme)
    } else {
      openLog()
    }
  }

  func uninstall() {
    guard !isUninstalling else { return }
    isUninstalling = true
    uninstallError = nil
    loginItems.setEnabled(false)

    Task {
      let result = await runPrivilegedUninstall()
      await MainActor.run {
        self.isUninstalling = false
        switch result {
        case .success:
          NSApplication.shared.terminate(nil)
        case .failure(let error):
          self.uninstallError = error.localizedDescription
        }
      }
    }
  }

  private nonisolated func runPrivilegedUninstall() async -> Result<Void, Error> {
    await Task.detached {
      do {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
          "-e",
          "do shell script \(appleScriptQuote(UninstallScript.shellScript())) with administrator privileges",
        ]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
          return .success(())
        }
        return .failure(UninstallError.cancelledOrFailed)
      } catch {
        return .failure(error)
      }
    }.value
  }

  private func startWatching() {
    watch(GuardRuntimeStatus.fileURL) { [weak self] in
      Task { @MainActor in self?.reloadStatus() }
    }
    watch(TemperatureHistory.fileURL) { [weak self] in
      Task { @MainActor in self?.reloadHistory() }
    }
    watch(GuardConfiguration.fileURL) { [weak self] in
      Task { @MainActor in self?.reloadConfiguration() }
    }
  }

  private func reloadStatus() {
    status = GuardRuntimeStatus.load()
    if let status {
      reconcilePendingOverride(with: status)
      notifications.handleStatusChange(status: status, configuration: configuration)
    }
  }

  private func reloadHistory() {
    history = TemperatureHistory.load()?.entries ?? []
  }

  private func reloadConfiguration() {
    configuration = GuardConfiguration.load()
  }

  private func watch(_ url: URL, onEvent: @escaping @Sendable () -> Void) {
    let directory = url.deletingLastPathComponent()
    let fileName = url.lastPathComponent
    let descriptor = open(directory.path, O_EVTONLY)
    guard descriptor >= 0 else { return }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .extend, .rename, .delete],
      queue: .main
    )
    source.setEventHandler {
      if FileManager.default.fileExists(atPath: url.path) {
        onEvent()
      }
    }
    source.setCancelHandler {
      close(descriptor)
    }
    source.resume()

    if fileName == GuardRuntimeStatus.fileURL.lastPathComponent {
      statusSource?.cancel()
      statusSource = source
    } else if fileName == TemperatureHistory.fileURL.lastPathComponent {
      historySource?.cancel()
      historySource = source
    } else {
      configSource?.cancel()
      configSource = source
    }
  }

  private func applyInstallerHandoffIfNeeded() {
    guard let handoff = InstallerHandoff.consume() else { return }
    if handoff.registerLoginItem {
      loginItems.setEnabled(true)
    }
  }
}

private enum UninstallError: LocalizedError {
  case cancelledOrFailed

  var errorDescription: String? {
    "卸载未完成，可能是授权被取消或系统命令失败。"
  }
}

private func appleScriptQuote(_ value: String) -> String {
  "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
}
