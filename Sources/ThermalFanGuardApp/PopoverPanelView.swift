import AppKit
import SwiftUI
import ThermalFanGuardCore

struct PopoverPanelView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if !model.isDaemonOnline {
        offlineBanner
      } else if model.hasSamplingError, let error = model.status?.error {
        samplingErrorBanner(error)
      }

      headerSection
      Divider()
      chartSection
      Divider()
      fanSection
      Divider()
      rulesSection
      Divider()
      actionSection
      footerSection
    }
    .padding(14)
    .frame(width: 320)
  }

  private var offlineBanner: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("守护进程未运行", systemImage: "exclamationmark.triangle.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.yellow)
      Button("查看安装说明") {
        model.openInstallInstructions()
      }
      .controlSize(.small)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
  }

  private func samplingErrorBanner(_ error: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label("采样异常", systemImage: "thermometer.medium.slash")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.orange)
      Text(error)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
  }

  private var headerSection: some View {
    HStack(alignment: .firstTextBaseline) {
      if let temperature = model.status?.temperature {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text(String(format: "%.1f", temperature))
            .font(.system(size: 34, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
          Text("°C")
            .font(.title3)
            .foregroundStyle(.secondary)
        }
      } else {
        Text("— °C")
          .font(.title)
          .foregroundStyle(.secondary)
      }
      Spacer()
      badge
    }
    .overlay(alignment: .bottomLeading) {
      if let sensor = model.status?.sensor, let count = model.status?.validSensorCount {
        Text("最热传感器: \(sensor) (\(count) 个有效)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .offset(y: 22)
      }
    }
    .padding(.bottom, 18)
  }

  private var badge: some View {
    let text: String
    if model.status?.override == "max" {
      text = "加速 100%"
    } else if let percent = model.status?.fanSpeedPercent {
      text = "加速 \(percent)%"
    } else {
      text = "自动"
    }
    return Text(text)
      .font(.caption.weight(.semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background((text == "自动" ? Color.secondary : Color.orange).opacity(0.18), in: Capsule())
      .foregroundStyle(text == "自动" ? Color.secondary : Color.orange)
  }

  private var chartSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label("温度历史（最近 60 分钟）", systemImage: "chart.xyaxis.line")
        .font(.subheadline.weight(.medium))
      if model.history.isEmpty {
        Text("暂无历史数据")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
      } else {
        TemperatureChartView(history: model.history, rules: model.configuration.sortedRules)
      }
    }
  }

  private var fanSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let fans = model.status?.fans, !fans.isEmpty {
        ForEach(Array(fans.enumerated()), id: \.offset) { index, fan in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text("风扇 \(index)")
                .font(.caption.weight(.medium))
              Spacer()
              Text("\(fan.actual.formatted()) rpm")
                .font(.caption.monospacedDigit())
              Text("/\(fan.maximum.formatted())")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(fan.actual), total: Double(max(fan.maximum, 1)))
              .tint(isFanBoosted ? .orange : .accentColor)
          }
        }
      } else {
        Text(model.status?.fanStatus ?? "风扇数据不可用")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var isFanBoosted: Bool {
    model.status?.fanSpeedPercent != nil || model.status?.override == "max"
  }

  private var rulesSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("分级规则")
        .font(.subheadline.weight(.medium))
      ForEach(Array(model.configuration.sortedRules.enumerated()), id: \.element.id) { index, rule in
        Button {
          openSettings()
          NSApp.activate(ignoringOtherApps: true)
        } label: {
          HStack {
            Text(ruleLine(index: index, rule: rule))
              .font(.caption)
              .multilineTextAlignment(.leading)
            Spacer()
            if model.status?.activeRuleIndex == index {
              Text("🔴")
            }
          }
          .padding(.vertical, 2)
          .padding(.horizontal, 6)
          .background(
            model.status?.activeRuleIndex == index ? Color.orange.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
          )
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func ruleLine(index: Int, rule: GuardRule) -> String {
    let marker = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧"][index]
    return "\(marker) ≥\(Int(rule.triggerTemperature))° \(Int(rule.triggerDuration))s → \(rule.fanSpeedPercent)% (≤\(Int(rule.recoveryTemperature))° 解除)"
  }

  private var actionSection: some View {
    HStack {
      Button("🚀 立即全速") {
        model.boostToMax()
      }
      .disabled(!model.isDaemonOnline || model.hasSamplingError)

      Button("↩︎ 恢复自动") {
        model.restoreAutomatic()
      }
      .disabled(!model.isDaemonOnline || model.hasSamplingError)
    }
  }

  private var footerSection: some View {
    HStack {
      Button("设置…") {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
      }
      .keyboardShortcut(",", modifiers: .command)
      Spacer()
      Button("退出") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q", modifiers: .command)
    }
    .font(.caption)
  }
}
