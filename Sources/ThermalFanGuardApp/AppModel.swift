import AppKit
import Dispatch
import Foundation
import ThermalFanGuardCore

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var status: GuardRuntimeStatus?
  @Published private(set) var configuration = GuardConfiguration.load()
  @Published private(set) var history: [HistoryEntry] = []
  @Published var showMenuBarTemperature = AppPreferences.showMenuBarTemperature
  @Published var notifyOnChange = AppPreferences.notifyOnChange
  @Published var notifyOnDeescalation = AppPreferences.notifyOnDeescalation

  let loginItems = LoginItemManager()
  let notifications = NotificationManager()

  private var statusSource: DispatchSourceFileSystemObject?
  private var historySource: DispatchSourceFileSystemObject?
  private var configSource: DispatchSourceFileSystemObject?
  private var fallbackTimer: Timer?

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
    status?.override == "max" || (status?.fanSpeedPercent == 100 && status?.mode != "automatic")
  }

  init() {
    reloadAll()
    startWatching()
    loginItems.refresh()
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
    do {
      let timeout = configuration.overrideTimeout > 0 ? configuration.overrideTimeout : nil
      try GuardCommand.issueMax(expiresAfter: timeout)
      reloadAll()
    } catch {
      NSLog("boost failed: \(error.localizedDescription)")
    }
  }

  func restoreAutomatic() {
    do {
      try GuardCommand.issueAuto()
      reloadAll()
    } catch {
      NSLog("restore automatic failed: \(error.localizedDescription)")
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
}
