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
    .frame(minWidth: 600, minHeight: 480)
  }
}

// MARK: - Rules Tab

struct RulesSettingsTab: View {
  @EnvironmentObject private var model: AppModel
  @State private var draft = GuardConfiguration.load()
  @State private var saveMessage: String?
  @State private var saveSucceeded = false

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          rulesHeader
          rulesList
          ruleActions
          globalSettingsCard
          feedbackSection
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
      }

      saveFooter
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear { draft = model.configuration }
  }

  private var rulesHeader: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("分级规则")
        .font(.title3.weight(.semibold))
      Text("按触发温度自动排序，可配置 1–8 条。温度升高时取最高匹配档位。")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var rulesList: some View {
    VStack(spacing: 10) {
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
    HStack(spacing: 10) {
      Button {
        addRule()
      } label: {
        Label("添加规则", systemImage: "plus")
      }
      .disabled(draft.rules.count >= 8)

      Button("恢复默认值") {
        draft = .defaults
        saveMessage = nil
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.secondary)
    }
  }

  private var globalSettingsCard: some View {
    SettingsCard(title: "全局", icon: "slider.horizontal.3") {
      VStack(spacing: 14) {
        SettingsLabeledRow(label: "采样间隔") {
          HStack(spacing: 10) {
            Text("\(Int(draft.sampleInterval)) 秒")
              .monospacedDigit()
              .frame(width: 40, alignment: .trailing)
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
          .frame(maxWidth: 160, alignment: .leading)
        }

        SettingsLabeledRow(label: "监控传感器") {
          Picker("", selection: sensorSelection) {
            Text("CPU + GPU").tag("cpu,gpu")
            Text("仅 CPU").tag("cpu")
            Text("仅 GPU").tag("gpu")
          }
          .labelsHidden()
          .frame(maxWidth: 160, alignment: .leading)
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
    if let saveMessage {
      FeedbackBanner(
        text: saveMessage,
        tint: saveSucceeded ? .green : .red,
        icon: saveSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill"
      )
    }
  }

  private var saveFooter: some View {
    VStack(spacing: 0) {
      Divider()
      HStack {
        Text("更改由守护进程在下一个采样周期内生效。")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("保存") { save() }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .tint(.orange)
          .disabled(!draft.validation.isValid)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .background(.bar)
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

  private func save() {
    do {
      try draft.save()
      model.reloadAll()
      saveMessage = "已保存，守护进程即将应用新规则。"
      saveSucceeded = true
    } catch {
      saveMessage = error.localizedDescription
      saveSucceeded = false
    }
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
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center) {
        RuleIndexBadge(index: index)
        VStack(alignment: .leading, spacing: 2) {
          Text("规则 \(index + 1)")
            .font(.subheadline.weight(.semibold))
          Text("触发后风扇调至 \(rule.fanSpeedPercent)%")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        FanSpeedBadge(percent: rule.fanSpeedPercent)
        if canDelete {
          Button(role: .destructive, action: onDelete) {
            Image(systemName: "trash")
          }
          .buttonStyle(.borderless)
          .help("删除此规则")
        }
      }

      Divider().opacity(0.5)

      VStack(alignment: .leading, spacing: 10) {
        Text("触发")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .textCase(.uppercase)

        HStack(spacing: 16) {
          MetricField(label: "温度", unit: "°C", value: $rule.triggerTemperature, range: 30...120)
          MetricField(label: "持续", unit: "秒", value: $rule.triggerDuration, range: 5...600)
          fanSpeedPicker
        }
      }

      VStack(alignment: .leading, spacing: 10) {
        Text("解除")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .textCase(.uppercase)

        HStack(spacing: 16) {
          MetricField(
            label: "温度",
            unit: "°C",
            value: $rule.recoveryTemperature,
            range: 20...(rule.triggerTemperature - 1)
          )
          MetricField(label: "持续", unit: "秒", value: $rule.recoveryDuration, range: 5...600)
          Spacer()
        }
      }
    }
    .padding(14)
    .background {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.06))
    }
  }

  private var fanSpeedPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("风扇")
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(spacing: 6) {
        Picker("", selection: $rule.fanSpeedPercent) {
          ForEach(Array(stride(from: 30, through: 100, by: 5)), id: \.self) { value in
            Text("\(value)%").tag(value)
          }
        }
        .labelsHidden()
        .frame(width: 88)

        if rule.fanSpeedPercent == 100, let minimumFanRPM {
          Text("≈ \(minimumFanRPM.formatted()) rpm")
            .font(.caption)
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
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
          Text("通用")
            .font(.title3.weight(.semibold))
          Text("状态栏显示、通知与登录项。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        SettingsCard(title: "启动与显示", icon: "menubar.rectangle") {
          VStack(spacing: 0) {
            SettingsToggleRow("登录时启动", isOn: loginAtStartup)
            Divider().padding(.leading, 4)
            SettingsToggleRow("菜单栏显示温度数字", isOn: showTemperature)
          }
        }

        SettingsCard(title: "通知", icon: "bell") {
          VStack(spacing: 0) {
            SettingsToggleRow("触发/恢复时发送通知", isOn: notifyOnChange)
            Divider().padding(.leading, 4)
            SettingsToggleRow("降档时也发送通知", isOn: notifyOnDeescalation)
              .disabled(!model.notifyOnChange)
          }
        }

        if let error = model.loginItems.lastError {
          FeedbackBanner(text: error, tint: .red, icon: "exclamationmark.circle.fill")
        }

        SettingsCard(title: "诊断", icon: "doc.text") {
          Button {
            model.openLog()
          } label: {
            Label("打开日志", systemImage: "arrow.up.forward.app")
          }
          .buttonStyle(.link)
        }
      }
      .padding(20)
    }
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
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: icon)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
      content
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.06))
    }
  }
}

private struct SettingsLabeledRow<Content: View>: View {
  let label: String
  @ViewBuilder let content: Content

  var body: some View {
    HStack(alignment: .center) {
      Text(label)
        .frame(width: 108, alignment: .leading)
      content
      Spacer(minLength: 0)
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
    Toggle(isOn: $isOn) {
      Text(title)
    }
    .toggleStyle(.switch)
    .padding(.vertical, 6)
  }
}

private struct MetricField: View {
  let label: String
  let unit: String
  @Binding var value: Double
  let range: ClosedRange<Double>

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(spacing: 4) {
        TextField(label, value: $value, format: .number.precision(.fractionLength(0)))
          .textFieldStyle(.roundedBorder)
          .frame(width: 52)
          .multilineTextAlignment(.trailing)
          .onChange(of: value) { _, newValue in
            value = min(range.upperBound, max(range.lowerBound, newValue))
          }
        Text(unit)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(width: unit == "°C" ? 18 : 14, alignment: .leading)
      }
    }
  }
}

private struct RuleIndexBadge: View {
  let index: Int

  var body: some View {
    Text(roman(index + 1))
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(.white)
      .frame(width: 28, height: 28)
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
      .font(.caption.weight(.semibold).monospacedDigit())
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
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
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: icon)
        .foregroundStyle(tint)
      Text(text)
        .font(.caption)
        .foregroundStyle(tint)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
