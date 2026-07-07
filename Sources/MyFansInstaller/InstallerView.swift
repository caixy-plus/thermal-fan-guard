import AppKit
import SwiftUI

private enum InstallerMetrics {
  static let width: CGFloat = 480
  static let height: CGFloat = 520
  static let padding: CGFloat = 24
  static let cardRadius: CGFloat = 8
  static let sectionSpacing: CGFloat = 14
}

struct InstallerView: View {
  @StateObject private var model = InstallerViewModel()

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: InstallerMetrics.sectionSpacing) {
          header
          componentsCard
          if !model.isInstalling {
            optionsCard
            requirementsNote
          }
          if model.showProgressSection {
            progressSection
          }
        }
        .padding(InstallerMetrics.padding)
      }

      Divider()
      buttonBar
    }
    .frame(width: InstallerMetrics.width, height: InstallerMetrics.height)
    .background(Color(nsColor: .windowBackgroundColor))
    .background {
      InstallerWindowConfigurator(
        width: InstallerMetrics.width,
        height: InstallerMetrics.height
      )
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 14) {
      appIcon
      VStack(alignment: .leading, spacing: 4) {
        Text(model.isComplete ? "安装完成" : "安装 MyFans")
          .font(.title2.weight(.semibold))
        Text(headerSubtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
  }

  private var headerSubtitle: String {
    if model.isComplete {
      return "MyFans 已就绪，可以开始使用。"
    }
    if model.isInstalling {
      return "正在安装，请勿关闭此窗口。"
    }
    return "Apple Silicon 风扇与温度守护"
  }

  private var appIcon: some View {
    Group {
      if let image = NSImage(named: "AppIcon") {
        Image(nsImage: image)
          .resizable()
      } else {
        Image(systemName: "fan.fill")
          .font(.system(size: 28))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(width: 56, height: 56)
  }

  private var componentsCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("将安装以下组件")
        .font(.subheadline.weight(.semibold))

      componentRow("MyFans", detail: "菜单栏应用 · /Applications", symbol: "menubar.rectangle")
      componentRow(
        "thermal-fan-guard",
        detail: "后台守护进程 · /usr/local/libexec",
        symbol: "gearshape.2"
      )
      componentRow("LaunchDaemon", detail: "开机自动启动守护进程", symbol: "power")
    }
    .installerCard()
  }

  private func componentRow(_ title: String, detail: String, symbol: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol)
        .font(.body)
        .foregroundStyle(.secondary)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.body)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var optionsCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("可选项")
        .font(.subheadline.weight(.semibold))

      Toggle("登录时启动 MyFans", isOn: $model.registerLoginAtStartup)
      Toggle("安装完成后打开 MyFans", isOn: $model.openAfterInstall)
    }
    .toggleStyle(.checkbox)
    .installerCard()
  }

  private var requirementsNote: some View {
    Text("需要 macOS 14 或更高版本、Apple Silicon，以及管理员密码。")
      .font(.caption)
      .foregroundStyle(.secondary)
  }

  private var progressSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      ProgressView(value: model.installProgress)
        .progressViewStyle(.linear)

      ForEach(InstallStep.allCases) { step in
        taskRow(step)
      }

      if let message = model.failureMessage {
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
      } else if model.isComplete {
        Label("全部组件已安装", systemImage: "checkmark.circle.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.green)
      }
    }
    .installerCard()
  }

  private func taskRow(_ step: InstallStep) -> some View {
    HStack(spacing: 10) {
      taskIcon(for: step)
      Text(step.title)
        .font(.body)
      Spacer()
      taskTrailing(for: step)
    }
  }

  @ViewBuilder
  private func taskIcon(for step: InstallStep) -> some View {
    switch model.taskStates[step] ?? .pending {
    case .completed:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .failed:
      Image(systemName: "xmark.circle.fill")
        .foregroundStyle(.red)
    case .running:
      ProgressView()
        .controlSize(.small)
        .frame(width: 16, height: 16)
    case .pending:
      Image(systemName: step.systemImage)
        .foregroundStyle(.tertiary)
    }
  }

  @ViewBuilder
  private func taskTrailing(for step: InstallStep) -> some View {
    switch model.taskStates[step] ?? .pending {
    case .running:
      Text("进行中")
        .font(.caption)
        .foregroundStyle(.secondary)
    case .completed:
      Text("完成")
        .font(.caption)
        .foregroundStyle(.secondary)
    case .failed(let message):
      Text(message)
        .font(.caption)
        .foregroundStyle(.red)
        .lineLimit(2)
        .multilineTextAlignment(.trailing)
    case .pending:
      EmptyView()
    }
  }

  private var buttonBar: some View {
    HStack {
      Spacer()
      if model.isComplete {
        Button("完成") { model.finish() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      } else if model.failureMessage != nil {
        Button("取消") { model.cancel() }
          .keyboardShortcut(.cancelAction)
        Button("重试") { model.retry() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      } else {
        Button("取消") { model.cancel() }
          .keyboardShortcut(.cancelAction)
          .disabled(model.isInstalling)
        Button("安装") { model.startInstall() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(model.isInstalling)
      }
    }
    .padding(.horizontal, InstallerMetrics.padding)
    .padding(.vertical, 14)
  }
}

private extension View {
  func installerCard() -> some View {
    padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Color(nsColor: .controlBackgroundColor),
        in: RoundedRectangle(cornerRadius: InstallerMetrics.cardRadius, style: .continuous)
      )
  }
}
