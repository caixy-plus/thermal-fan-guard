import SwiftUI
import ThermalFanGuardCore

struct SettingsView: View {
  var body: some View {
    TabView {
      RulesSettingsTab()
        .tabItem { Label("分级规则", systemImage: "thermometer.variable.and.figure") }
      GeneralSettingsTab()
        .tabItem { Label("通用", systemImage: "gearshape") }
    }
    .frame(width: SettingsMetrics.panelWidth, height: SettingsMetrics.panelHeight)
    .fixedSize(horizontal: true, vertical: false)
    .onAppear {
      MenuBarPanelCloser.closePopoverIfVisible()
    }
    .background {
      SettingsWindowConfigurator(
        width: SettingsMetrics.panelWidth,
        height: SettingsMetrics.panelHeight
      )
    }
  }
}

private enum SettingsMetrics {
  static let labelWidth: CGFloat = 118
  static let columnGap: CGFloat = 8
  static let controlWidth: CGFloat = 112
  static let formWidth: CGFloat = labelWidth + columnGap + controlWidth
  static let horizontalPadding: CGFloat = 12
  static let verticalPadding: CGFloat = 10
  static let sectionSpacing: CGFloat = 8
  static let cardPadding: CGFloat = 8
  static let rowSpacing: CGFloat = 4
  /// Rules cards are the widest content; window hugs this width.
  static let rulesContentWidth: CGFloat = 360
  static let panelWidth: CGFloat = rulesContentWidth + horizontalPadding * 2
  /// Default height: one rule + global section, minimal bottom gap.
  static let panelHeight: CGFloat = 478
}

// MARK: - Rules Tab

struct RulesSettingsTab: View {
  @EnvironmentObject private var model: AppModel
  @State private var draft = GuardConfiguration.load()
  @State private var lastPersisted = GuardConfiguration.load()
  @State private var isSyncing = true
  @State private var saveError: String?

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
        rulesHeader
        rulesList
        ruleActions
        globalSettingsCard
        feedbackSection
        Text("更改会在下一个采样周期内由守护进程自动应用。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(width: SettingsMetrics.rulesContentWidth, alignment: .leading)
      .padding(.horizontal, SettingsMetrics.horizontalPadding)
      .padding(.vertical, SettingsMetrics.verticalPadding)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear {
      draft = model.configuration
      lastPersisted = model.configuration
      isSyncing = false
    }
    .onChange(of: draft) { _, newValue in
      persistIfNeeded(newValue)
    }
  }

  private var rulesHeader: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("分级规则")
        .font(.title3.weight(.semibold))
      Text("按触发温度自动排序，可配置 1–8 条。温度升高时取最高匹配档位。")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var rulesList: some View {
    VStack(spacing: 6) {
      ForEach(Array(draft.rules.enumerated()), id: \.element.id) { index, rule in
        if let binding = binding(for: rule.id) {
          RuleCardView(
            index: index,
            rule: binding,
            minimumFanRPM: minimumFanRPM,
            canDelete: draft.rules.count > 1
          ) {
            draft.rules.removeAll { $0.id == rule.id }
          }
        }
      }
    }
  }

  private var ruleActions: some View {
    HStack(spacing: 8) {
      Button {
        addRule()
      } label: {
        Label("添加规则", systemImage: "plus")
      }
      .disabled(draft.rules.count >= 8)

      Button("恢复默认值") {
        draft = .defaults
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.secondary)
    }
  }

  private var globalSettingsCard: some View {
    SettingsCard(title: "全局", icon: "slider.horizontal.3", width: SettingsMetrics.rulesContentWidth) {
      VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
        SettingsLabeledRow(label: "采样间隔") {
          HStack(spacing: 6) {
            Text("\(Int(draft.sampleInterval)) 秒")
              .monospacedDigit()
              .frame(width: 32, alignment: .trailing)
            Stepper("", value: $draft.sampleInterval, in: 2...30)
              .labelsHidden()
          }
        }

        SettingsLabeledRow(label: "手动加速超时") {
          Picker("", selection: $draft.overrideTimeout) {
            Text("10 分钟").tag(TimeInterval(600))
            Text("30 分钟").tag(TimeInterval(1800))
            Text("1 小时").tag(TimeInterval(3600))
            Text("不限时").tag(TimeInterval(0))
          }
          .labelsHidden()
          .frame(width: SettingsMetrics.controlWidth, alignment: .leading)
        }

        SettingsLabeledRow(label: "监控传感器") {
          Picker("", selection: sensorSelection) {
            Text("CPU + GPU").tag("cpu,gpu")
            Text("仅 CPU").tag("cpu")
            Text("仅 GPU").tag("gpu")
          }
          .labelsHidden()
          .frame(width: SettingsMetrics.controlWidth, alignment: .leading)
        }
      }
    }
  }

  @ViewBuilder
  private var feedbackSection: some View {
    if !draft.validation.errors.isEmpty {
      FeedbackBanner(
        text: draft.validation.errors.joined(separator: "\n"),
        tint: .red,
        icon: "exclamationmark.circle.fill"
      )
    }
    if !draft.validation.warnings.isEmpty {
      FeedbackBanner(
        text: draft.validation.warnings.joined(separator: "\n"),
        tint: .orange,
        icon: "exclamationmark.triangle.fill"
      )
    }
    if let saveError {
      FeedbackBanner(
        text: saveError,
        tint: .red,
        icon: "xmark.circle.fill"
      )
    }
  }

  private func persistIfNeeded(_ config: GuardConfiguration) {
    guard !isSyncing else { return }
    guard config.isValid, config != lastPersisted else { return }
    do {
      try config.save()
      lastPersisted = config
      saveError = nil
      model.reloadAll()
    } catch {
      saveError = error.localizedDescription
    }
  }

  private func binding(for id: UUID) -> Binding<GuardRule>? {
    guard let index = draft.rules.firstIndex(where: { $0.id == id }) else { return nil }
    return $draft.rules[index]
  }

  private var sensorSelection: Binding<String> {
    Binding(
      get: { draft.sensorGroups.sorted().joined(separator: ",") },
      set: { draft.sensorGroups = $0.split(separator: ",").map(String.init) }
    )
  }

  private var minimumFanRPM: Int? {
    guard let fans = model.status?.fans, !fans.isEmpty else { return nil }
    return fans.map(\.maximum).min()
  }

  private func addRule() {
    guard draft.rules.count < 8 else { return }
    let sorted = draft.sortedRules
    let last = sorted.last ?? GuardConfiguration.defaults.rules[0]
    draft.rules.append(
      GuardRule(
        triggerTemperature: min(120, last.triggerTemperature + 10),
        triggerDuration: last.triggerDuration,
        fanSpeedPercent: min(100, last.fanSpeedPercent + 20),
        recoveryTemperature: max(20, min(120, last.triggerTemperature + 10) - 5),
        recoveryDuration: last.recoveryDuration
      )
    )
  }
}

// MARK: - Rule Card

struct RuleCardView: View {
  let index: Int
  @Binding var rule: GuardRule
  let minimumFanRPM: Int?
  let canDelete: Bool
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 6) {
        RuleIndexBadge(index: index)
        VStack(alignment: .leading, spacing: 0) {
          Text("规则 \(index + 1)")
            .font(.subheadline.weight(.semibold))
          Text("触发 → \(rule.fanSpeedPercent)%")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        FanSpeedBadge(percent: rule.fanSpeedPercent)
        if canDelete {
          Button(role: .destructive, action: onDelete) {
            Image(systemName: "trash")
          }
          .buttonStyle(.borderless)
          .help("删除此规则")
        }
      }

      Divider().opacity(0.4)

      ruleFields(title: "触发") {
        MetricField(label: "温度", unit: "°C", value: $rule.triggerTemperature, range: 30...120)
        MetricField(label: "持续", unit: "秒", value: $rule.triggerDuration, range: 5...600)
        fanSpeedPicker
      }

      ruleFields(title: "解除") {
        MetricField(
          label: "温度",
          unit: "°C",
          value: $rule.recoveryTemperature,
          range: 20...(rule.triggerTemperature - 1)
        )
        MetricField(label: "持续", unit: "秒", value: $rule.recoveryDuration, range: 5...600)
      }
    }
    .padding(SettingsMetrics.cardPadding)
    .frame(width: SettingsMetrics.rulesContentWidth, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.06))
    }
  }

  private func ruleFields(title: String, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
      HStack(alignment: .top, spacing: 10) {
        content()
      }
    }
  }

  private var fanSpeedPicker: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("风扇")
        .font(.caption2)
        .foregroundStyle(.secondary)
      HStack(spacing: 4) {
        Picker("", selection: $rule.fanSpeedPercent) {
          ForEach(Array(stride(from: 30, through: 100, by: 5)), id: \.self) { value in
            Text("\(value)%").tag(value)
          }
        }
        .labelsHidden()
        .frame(width: 76)

        if rule.fanSpeedPercent == 100, let minimumFanRPM {
          Text("≈\(minimumFanRPM.formatted())")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
      VStack(alignment: .leading, spacing: 2) {
        Text("通用")
          .font(.title3.weight(.semibold))
        Text("状态栏显示、通知与登录项。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      SettingsCard(title: "启动与显示", icon: "menubar.rectangle") {
        VStack(alignment: .leading, spacing: 0) {
          SettingsToggleRow("登录时启动", isOn: loginAtStartup)
          Divider().padding(.leading, SettingsMetrics.labelWidth + SettingsMetrics.columnGap)
          SettingsToggleRow("菜单栏显示温度数字", isOn: showTemperature)
        }
      }

      SettingsCard(title: "通知", icon: "bell") {
        VStack(alignment: .leading, spacing: 0) {
          SettingsToggleRow("触发/恢复时发送通知", isOn: notifyOnChange)
          Divider().padding(.leading, SettingsMetrics.labelWidth + SettingsMetrics.columnGap)
          SettingsToggleRow("降档时也发送通知", isOn: notifyOnDeescalation)
            .disabled(!model.notifyOnChange)
        }
      }

      if let error = model.loginItems.lastError {
        FeedbackBanner(text: error, tint: .red, icon: "exclamationmark.circle.fill")
      }

      SettingsCard(title: "诊断", icon: "doc.text") {
        SettingsLabeledRow(label: "日志") {
          Button {
            model.openLog()
          } label: {
            Label("打开日志", systemImage: "arrow.up.forward.app")
          }
          .buttonStyle(.link)
        }
      }
    }
    .frame(width: SettingsMetrics.formWidth, alignment: .leading)
    .padding(.horizontal, SettingsMetrics.horizontalPadding)
    .padding(.vertical, SettingsMetrics.verticalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear { model.loginItems.refresh() }
  }

  private var loginAtStartup: Binding<Bool> {
    Binding(
      get: { model.loginItems.isEnabled },
      set: { model.loginItems.setEnabled($0) }
    )
  }

  private var showTemperature: Binding<Bool> {
    Binding(
      get: { model.showMenuBarTemperature },
      set: { model.setShowMenuBarTemperature($0) }
    )
  }

  private var notifyOnChange: Binding<Bool> {
    Binding(
      get: { model.notifyOnChange },
      set: { model.setNotifyOnChange($0) }
    )
  }

  private var notifyOnDeescalation: Binding<Bool> {
    Binding(
      get: { model.notifyOnDeescalation },
      set: { model.setNotifyOnDeescalation($0) }
    )
  }
}

// MARK: - Shared Components

private struct SettingsCard<Content: View>: View {
  let title: String
  let icon: String
  var width: CGFloat = SettingsMetrics.formWidth
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(title, systemImage: icon)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      content
    }
    .padding(SettingsMetrics.cardPadding)
    .frame(width: width, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.06))
    }
  }
}

private struct SettingsLabeledRow<Content: View>: View {
  let label: String
  @ViewBuilder let content: Content

  var body: some View {
    HStack(alignment: .center, spacing: SettingsMetrics.columnGap) {
      Text(label)
        .font(.body)
        .frame(width: SettingsMetrics.labelWidth, alignment: .leading)
      content
        .frame(width: SettingsMetrics.controlWidth, alignment: .leading)
    }
  }
}

private struct SettingsToggleRow: View {
  let title: String
  @Binding var isOn: Bool

  init(_ title: String, isOn: Binding<Bool>) {
    self.title = title
    _isOn = isOn
  }

  var body: some View {
    HStack(alignment: .center, spacing: SettingsMetrics.columnGap) {
      Text(title)
        .font(.body)
        .frame(width: SettingsMetrics.labelWidth, alignment: .leading)
      Toggle("", isOn: $isOn)
        .labelsHidden()
        .frame(width: SettingsMetrics.controlWidth, alignment: .leading)
    }
    .padding(.vertical, 2)
  }
}

private struct MetricField: View {
  let label: String
  let unit: String
  @Binding var value: Double
  let range: ClosedRange<Double>

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
      HStack(spacing: 3) {
        TextField(label, value: $value, format: .number.precision(.fractionLength(0)))
          .textFieldStyle(.roundedBorder)
          .frame(width: 48)
          .multilineTextAlignment(.trailing)
          .onChange(of: value) { _, newValue in
            value = min(range.upperBound, max(range.lowerBound, newValue))
          }
        Text(unit)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct RuleIndexBadge: View {
  let index: Int

  var body: some View {
    Text(roman(index + 1))
      .font(.caption.weight(.semibold))
      .foregroundStyle(.white)
      .frame(width: 22, height: 22)
      .background(Circle().fill(.orange.gradient))
  }

  private func roman(_ value: Int) -> String {
    ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧"][safe: value - 1] ?? "\(value)"
  }
}

private struct FanSpeedBadge: View {
  let percent: Int

  var body: some View {
    Text("\(percent)%")
      .font(.caption2.weight(.semibold).monospacedDigit())
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(
        Capsule().fill(percent >= 80 ? Color.orange.opacity(0.18) : Color.accentColor.opacity(0.12))
      )
      .foregroundStyle(percent >= 80 ? .orange : .accentColor)
  }
}

private struct FeedbackBanner: View {
  let text: String
  let tint: Color
  let icon: String

  var body: some View {
    HStack(alignment: .top, spacing: 6) {
      Image(systemName: icon)
        .foregroundStyle(tint)
      Text(text)
        .font(.caption)
        .foregroundStyle(tint)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(6)
    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
