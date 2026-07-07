import AppKit
import Foundation
import ThermalFanGuardCore

enum InstallTaskState: Equatable {
  case pending
  case running
  case completed
  case failed(String)
}

@MainActor
final class InstallerViewModel: ObservableObject {
  @Published var registerLoginAtStartup = true
  @Published var openAfterInstall = true
  @Published private(set) var isInstalling = false
  @Published private(set) var isComplete = false
  @Published private(set) var failureMessage: String?
  @Published private(set) var taskStates: [InstallStep: InstallTaskState] = [:]

  private let engine = InstallEngine()

  var showProgressSection: Bool {
    isInstalling || isComplete || failureMessage != nil
  }

  init() {
    resetTaskStates()
  }

  func cancel() {
    NSApplication.shared.terminate(nil)
  }

  func startInstall() {
    guard !isInstalling else { return }
    isInstalling = true
    isComplete = false
    failureMessage = nil
    resetTaskStates()
    Task { await performInstall() }
  }

  func retry() {
    failureMessage = nil
    startInstall()
  }

  func finish() {
    if openAfterInstall {
      NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/MyFans.app"))
    }
    NSApplication.shared.terminate(nil)
  }

  private func resetTaskStates() {
    taskStates = Dictionary(uniqueKeysWithValues: InstallStep.allCases.map { ($0, .pending) })
  }

  private func setTask(_ step: InstallStep, _ state: InstallTaskState) {
    taskStates[step] = state
  }

  private func performInstall() async {
    do {
      setTask(.copyApplication, .running)
      try await engine.copyApplication()
      setTask(.copyApplication, .completed)

      setTask(.installDaemon, .running)
      try await engine.installDaemonAndStartService()
      setTask(.installDaemon, .completed)

      setTask(.startService, .running)
      try await Task.sleep(for: .milliseconds(280))
      setTask(.startService, .completed)

      try InstallerHandoff(
        registerLoginItem: registerLoginAtStartup,
        openAfterInstall: false
      ).write()

      isInstalling = false
      isComplete = true
    } catch {
      if taskStates.contains(where: { $0.value == .running }) {
        for step in InstallStep.allCases where taskStates[step] == .running {
          setTask(step, .failed(error.localizedDescription))
        }
      }
      isInstalling = false
      failureMessage = error.localizedDescription
    }
  }

  var completedCount: Int {
    taskStates.values.filter { $0 == .completed }.count
  }

  var installProgress: Double {
    if isComplete { return 1 }
    guard isInstalling else { return 0 }
    let runningBonus = taskStates.contains { $0.value == .running } ? 0.15 : 0
    return min(1, Double(completedCount) / Double(InstallStep.allCases.count) + runningBonus)
  }
}
