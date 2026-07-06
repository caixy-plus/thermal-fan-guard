# UPDATE.md — 升级为完整界面的 macOS 状态栏应用

## 1. 目标与现状

**目标**：把 Thermal Fan Guard 从「纯文本菜单 + 简陋设置窗口」升级为一个有完整
图形界面的 macOS 状态栏（menu bar）应用：点击状态栏图标弹出富信息面板（大字温度、
风扇转速、温度历史曲线、手动控制按钮），并提供原生 SwiftUI 设置界面。

**现状盘点**（升级的基线）：

| 组件 | 现状 | 处置 |
|---|---|---|
| root 守护进程（launchd Daemon） | 每 5s 采样 SMC、按规则控风扇 | **保留**，小幅扩展（参数集 + 历史记录 + 手动指令） |
| 温控状态机 `ThermalGuardState` | 纯逻辑、有测试 | **复用**为单条规则引擎，外层新增多规则仲裁（§4.0） |
| 菜单栏进程 `--menu-bar` | NSMenu 纯文本菜单，5s 轮询 | **重写**为 SwiftUI 界面 |
| 设置窗口 `SettingsWindowController` | AppKit 手搭表单 | **替换**为 SwiftUI Settings |
| 进程间通信 | `/Users/Shared` 下 config.json + status.json | **保留并扩展**（新增 history / command 两个文件） |
| 安装方式 | install.sh + LaunchDaemon + LaunchAgent | Daemon 保留；LaunchAgent 改为 `SMAppService` 登录项开关 |

架构不变的核心原因：写 SMC 风扇键必须 root，GUI 应用无法直接做，所以
「root 守护进程干活 + 用户态状态栏应用做界面」的分离必须维持。

**系统要求**：macOS 14+（M3 Max 机器，无兼容包袱；可用 `MenuBarExtra`、
Swift Charts、`SMAppService`）。

---

## 2. 总体架构

```
┌─────────────────────────────┐        ┌──────────────────────────────┐
│ thermal-fan-guard (root)     │        │ Thermal Fan Guard.app (用户)  │
│ launchd Daemon，5s 循环      │        │ SwiftUI MenuBarExtra          │
│                              │  写→   │                              │
│ · 读 SMC 温度/风扇           │ status │ · 状态栏图标 + 温度文字        │
│ · 状态机决策、控制风扇        │ history│ · 弹出面板（温度/风扇/曲线）   │
│ · 写 status.json（当前快照）  │        │ · 手动 Boost / 恢复自动        │
│ · 追加 history.json（环形）   │  ←读   │ · SwiftUI 设置窗口            │
│ · 读 command.json（手动指令） │ config │ · 触发/恢复时本地通知          │
│ · 读 config.json（规则）      │ command│ · SMAppService 登录自启        │
└─────────────────────────────┘        └──────────────────────────────┘
```

进程间仍用 `/Users/Shared` 文件协议（简单、可靠、无需 XPC/entitlement）：

| 文件 | 方向 | 内容 |
|---|---|---|
| `com.caixinyun.thermal-fan-guard.json` | UI → daemon | 规则配置（现有，不变） |
| `….status.json` | daemon → UI | 当前快照（现有，字段扩展见 §4.2） |
| `….history.json` | daemon → UI | 最近 1 小时采样环形数组（新增） |
| `….command.json` | UI → daemon | 手动覆盖指令（新增） |

---

## 3. 状态栏应用 UI 设计

### 3.1 状态栏图标（NSStatusItem 区域）

- 图标：SF Symbol `fan`（守护中）/ `fan.fill`（MAX 模式，`.pulse` symbol effect
  动效）/ `fan.badge.slash`（daemon 离线或采样报错）。
- 文字：图标右侧显示当前温度 `62°`；MAX 模式渲染为橙色，离线时不显示温度。
- 设置里可关闭温度文字（只留图标，省菜单栏空间）。
- 实现：`MenuBarExtra(style: .window)`，label 用自定义 SwiftUI 视图。

### 3.2 弹出面板（点击图标，宽约 320pt）

```
┌────────────────────────────────────┐
│  76.4 °C           [ 加速 80% 🔴 ] │   ← 大字温度 + 生效档位徽章
│  最热传感器: GPU cluster (14 个有效) │
├────────────────────────────────────┤
│  📈 温度历史（最近 60 分钟）          │
│  ╭─────────────────────────────╮   │   ← Swift Charts 折线
│  │      ／＼   ＿＿85 ──────── │   │     每条规则触发温度一条虚线
│  │  ＿／    ＼／＿＿75 ──────── │   │     加速区间按档位铺橙色底
│  │          ＿＿60 ──────────  │   │
│  ╰─────────────────────────────╯   │
├────────────────────────────────────┤
│  风扇 0   4 812 rpm ▓▓▓▓▓▓░░ /5920 │   ← 实际转速 / 最大转速条
│  风扇 1   4 790 rpm ▓▓▓▓▓▓░░ /5872 │
├────────────────────────────────────┤
│  分级规则                           │
│  ① ≥60° 30s → 60%   (≤55° 解除)    │   ← 生效中的档行高亮
│  ② ≥75° 15s → 80%   (≤70° 解除) 🔴 │
│  ③ ≥85° 10s → 100%  (≤78° 解除)    │
├────────────────────────────────────┤
│  [ 🚀 立即全速 ]   [ ↩︎ 恢复自动 ]   │   ← 手动覆盖，见 §4.3
│  设置…  ⌘,              退出   ⌘Q  │
└────────────────────────────────────┘
```

细节：

- 温度大字用 `contentTransition(.numericText())` 平滑滚动。
- 徽章文案 = 生效规则的档位（「加速 80%」）；无规则触发时显示「自动」。
- 曲线：X 轴时间、Y 轴温度，每条规则的触发温度各画一条 `RuleMark` 虚线
  （标注档位百分比），`RectangleMark` 给加速区间铺半透明橙色底（颜色
  深浅随档位）。数据源为 history.json。
- 分级规则列表：直接读 config.json 渲染，`activeRuleIndex` 对应行高亮
  加 🔴；点击任意行跳转设置窗口。
- 风扇行：`ProgressView(value: actual/max)`，加速中 tint 橙色。
- daemon 离线（status.json 超过 20s 未更新）：面板顶部显示黄色横幅
  「守护进程未运行」+「查看安装说明」按钮；手动按钮置灰。
- 刷新机制：`DispatchSource.makeFileSystemObjectSource` 监听 status.json
  写入事件即时刷新，另加 5s 兜底定时器（比现在纯轮询更跟手）。

### 3.3 设置窗口（SwiftUI `Settings` scene，⌘,）

Tab 1「分级规则」——替代现有 SettingsWindowController，核心是多规则编辑器：

```
┌──────────────────────────────────────────────────────────┐
│ 分级规则（按触发温度自动排序，1–8 条）                       │
│ ┌──────────────────────────────────────────────────────┐ │
│ │ ① ≥ [60 ]°C 持续 [30 ]s → 风扇 [ 60%▾]                │ │
│ │    解除: ≤ [55 ]°C 持续 [30 ]s                    [－] │ │
│ │ ② ≥ [75 ]°C 持续 [15 ]s → 风扇 [ 80%▾]                │ │
│ │    解除: ≤ [70 ]°C 持续 [30 ]s                    [－] │ │
│ │ ③ ≥ [85 ]°C 持续 [10 ]s → 风扇 [100%▾] ≈5920rpm       │ │
│ │    解除: ≤ [78 ]°C 持续 [30 ]s                    [－] │ │
│ └──────────────────────────────────────────────────────┘ │
│ [＋ 添加规则]                          [恢复默认值]        │
│ ⚠️ 第②条与第③条触发温度需至少相差 2°C          [保存]      │
└──────────────────────────────────────────────────────────┘
```

- 每行一条规则：温度/时长用数字框 + Stepper，档位用 30–100%（步进 5%）
  Picker，100% 档旁实时换算「≈ 5 920 rpm」（取 status.json 各风扇 max 的
  最小值）。
- 「＋ 添加规则」预填合理值：触发温度 = 现有最高档 +10°C、档位 +20%
  （各自钳制在上限内）；最后一条规则不可删（至少保留一条）。
- 失焦或改动即跑 `isValid`，违规项红框 + 底部红字说明具体哪条冲突，
  保存按钮禁用；最高档 < 100% 时黄字软警告但可保存。
- 保存时按触发温度排序写入 config.json，footer 说明「守护进程一个采样
  周期内生效」。

Tab 1 底部「全局」分组：

- 采样间隔 Stepper（2–30s，默认 5s）。
- 手动加速超时 Picker（10 分钟 / 30 分钟 / 1 小时 / 不限时）。
- 监控传感器 Picker（CPU + GPU / 仅 CPU / 仅 GPU）。

Tab 2「通用」：

- 「登录时启动」Toggle → `SMAppService.mainApp.register()/unregister()`
  （取代 LaunchAgent plist，见 §5）。
- 「菜单栏显示温度数字」Toggle。
- 「触发/恢复时发送通知」Toggle。
- 「打开日志」按钮（`open /var/log/thermal-fan-guard.log`）。

### 3.4 本地通知

UI 进程监测 status.json 的 `activeRuleIndex` 变化：

- 升档：「🌡 76°C 触发第 ② 档规则，风扇加速至 80%」。
- 降档：「↘️ 温度回落，降至第 ① 档（60%）」（可在设置里关闭，只留升档/恢复）。
- 完全恢复：「✅ 温度回落，已恢复自动控制」。
- 用 `UNUserNotificationCenter`，首次开启开关时申请权限。放在 UI 进程
  （而非 daemon）是因为 root daemon 无法向用户会话发通知。

---

## 4. 守护进程改动（最小化）

### 4.0 可自定义参数：多条分级规则（重写 `GuardConfiguration`）

规则模型从「单条触发/恢复」升级为**有序的多条分级规则**——每条规则完整
表达「温度到 X°C 持续 T 秒 → 风扇调到 P%，直到 ≤ Y°C 持续 R 秒解除」，
整体构成一条带迟滞的阶梯式风扇曲线。新 config.json schema：

```json
{
  "rules": [
    { "triggerTemperature": 60, "triggerDuration": 30, "fanSpeedPercent": 60,
      "recoveryTemperature": 55, "recoveryDuration": 30 },
    { "triggerTemperature": 75, "triggerDuration": 15, "fanSpeedPercent": 80,
      "recoveryTemperature": 70, "recoveryDuration": 30 },
    { "triggerTemperature": 85, "triggerDuration": 10, "fanSpeedPercent": 100,
      "recoveryTemperature": 78, "recoveryDuration": 30 }
  ],
  "sampleInterval": 5,
  "overrideTimeout": 1800,
  "sensorGroups": ["cpu", "gpu"]
}
```

**每条规则的字段**：

| 字段 | 范围 | 说明 |
|---|---|---|
| `triggerTemperature` | 30–120 °C | 到多少度 |
| `triggerDuration` | 5–600 s | 持续多少时间才触发 |
| `fanSpeedPercent` | 30–100 % | 调高到多少：目标转速 = 风扇 max × 百分比 |
| `recoveryTemperature` | 20 °C–本条触发温度−1 | 直到降回多少度 |
| `recoveryDuration` | 5–600 s | 持续多少时间才解除本档 |

**全局字段**：

| 字段 | 范围 | 默认 | 说明 |
|---|---|---|---|
| `sampleInterval` | 2–30 s | 5 | daemon 循环周期；「持续时间」判断按真实时钟算，不受间隔影响 |
| `overrideTimeout` | 600–3600 s 或 0（不限时） | 1800 | §4.3 手动加速的自动失效时间 |
| `sensorGroups` | `["cpu","gpu"]` 非空子集 | 两者 | 取所选组内最热传感器 |

**多规则仲裁语义**（新增 `MultiRuleGuardState`，放 Core target）：

- 每条规则独立运行一个现有的 `ThermalGuardState` 状态机——各自的触发
  计时、恢复计时、迟滞带互不干扰，现有状态机逻辑和测试原样复用。
- **生效档位 = 所有「已触发」规则中 `fanSpeedPercent` 最高的一条**；
  无任何规则触发 → 恢复 macOS 自动控制。
- 升档即时生效：温度冲高时高温档规则触发，直接覆盖低档。
- 降档是阶梯式的：某条规则自身的恢复条件满足后退出，档位回落到剩余
  已触发规则中的最高档；全部退出才回到自动。每档独立迟滞带天然防抖，
  不会在档位边界震荡。
- 档位每次变化都写日志（`ESCALATED` / `DEESCALATED` / `RECOVERED`，
  带规则序号和百分比），便于事后核对曲线是否合理。

**校验规则**（`isValid`，daemon 与 UI 共用）：

- 规则 1–8 条，保存时按触发温度排序存储。
- 触发温度严格递增，相邻两条至少相差 2°C（避免档位重叠无意义）。
- `fanSpeedPercent` 随触发温度非严格递增（温度更高的档转速不能更低）。
- 每条规则自身：恢复温度 < 触发温度；各持续时间在范围内。
- UI 软警告（不阻止保存）：最高温档 < 100% 时提示「建议最高档设为
  100% 以保证过热兜底」。

**默认值与向后兼容**：

- 默认配置 = 单条规则 `[≥60°C/30s → 100%，≤55°C/30s]`，与当前行为等价。
- 解码时兼容旧扁平格式（顶层 4 个字段的现存 config.json），自动转换为
  单条 100% 规则；全局新字段用 `decodeIfPresent` + 默认值。daemon 读到
  非法配置时回退 defaults 并打日志（现有行为）。

**硬件层配套**：`setFansToMaximum()` 改为 `setFans(toPercent:)`，
target = round(max × percent)。`sampleInterval` 同时决定 status.json 的
离线判定阈值（固定 20s 改为 `4 × sampleInterval`）与 history 写盘节流。

### 4.1 历史记录（新增 `HistoryStore`）

- 每次采样后把 `(timestamp, temperature, mode)` 追加进内存环形缓冲，
  容量 = `3600 / sampleInterval` 条（即固定覆盖最近 1 小时）。
- 每 6 个采样整体原子写一次 `….history.json`（0644），避免每次采样都写盘。
  单条约 60B，全量文件 < 120KB（最密 2s 间隔时），无性能问题。

### 4.2 status.json 字段扩展

在 `GuardRuntimeStatus` 上加结构化风扇数据（现有 `fanStatus` 字符串
保留以兼容日志格式）：

```json
{ "fans": [ { "actual": 4812, "target": 5920, "maximum": 5920 } ],
  "activeRuleIndex": 1, "fanSpeedPercent": 80,
  "override": "none | max | auto" }
```

`activeRuleIndex` 为当前生效规则在排序后数组中的下标（null = 自动控制），
`fanSpeedPercent` 为当前生效档位；`mode` 字段保留（automatic/boosted）。

### 4.3 手动覆盖 command.json

UI 写入指令，daemon 每循环读取：

```json
{ "action": "max" | "auto" | "clear", "issuedAt": "…", "expiresAfter": 1800 }
```

语义与安全约束：

- `max`：立即 100% 全速（无视分级档位），**忽略所有规则的恢复条件**，
  直到用户 clear 或超时（时长取配置 `overrideTimeout`，默认 30 分钟，
  防止忘关导致风扇长鸣；配置为 0 则不限时）。
- `auto`：立即恢复自动，**但分级规则仍然生效**——若温度再次满足某档
  触发条件，daemon 会重新按该档加速。这是安全底线：手动操作永远不能
  关闭过热保护。
- `clear` / 超时 / 文件不存在：回到正常状态机。
- `issuedAt` 早于 daemon 启动时间或已超时的指令直接忽略，防旧文件生效。
- 实现方式：不动 `ThermalGuardState` / `MultiRuleGuardState`（保持纯逻辑
  可测），在 main.swift 循环里包一层 override 判断。

---

## 5. 打包与安装调整

- **App 结构**：新增 `Sources/ThermalFanGuardApp`（SwiftUI）作为第二个
  executable target `ThermalFanGuardApp`，与 daemon 二进制分离；main.swift
  删除 `--menu-bar` 分支。共享代码（GuardConfiguration/GuardState 等）抽到
  library target `ThermalFanGuardCore`，两个可执行目标都依赖它，测试目标
  改为依赖 Core。
- **图标**：新增 `AppIcon.icns`（风扇 + 温度计主题），install.sh 拷入
  `Contents/Resources`，Info.plist 加 `CFBundleIconFile`。
- **Info.plist**：确认 `LSUIElement = true`（无 Dock 图标）、补
  `NSSupportsAutomaticTermination = false`。
- **登录自启**：删除 `com.caixinyun.thermal-fan-guard-menubar.plist`
  LaunchAgent，改由 App 内 `SMAppService.mainApp`（用户可在设置里开关，
  也会出现在系统设置的登录项列表里，更符合 macOS 规范）。install.sh 里
  bootout 旧 agent 做迁移清理；uninstall.sh 同步更新。
- LaunchDaemon（root 守护）安装流程不变。

---

## 6. 实施计划

| 阶段 | 内容 | 验证 |
|---|---|---|
| P1 目标拆分 | Package.swift 拆 Core library + 两个 executable；迁移共享代码 | `swift build` + `swift test` 全绿 |
| P2 daemon 扩展 | 多条分级规则模型 + `MultiRuleGuardState` 仲裁（§4.0）、HistoryStore、status 字段扩展、command.json override | 单测覆盖：升档即时/降档阶梯回落/迟滞防抖、规则排序与校验边界（递增、≥2°C 间距、档位单调）、旧 config.json 解码兼容、override 语义（超时、旧指令忽略、auto 后再触发）；`--status` 正常 |
| P3 状态栏面板 | MenuBarExtra + 弹出面板（温度/风扇/曲线/离线横幅），文件监听刷新 | 手动运行 App，对照 daemon 日志核对显示值 |
| P4 设置与手动控制 | SwiftUI Settings 两个 Tab、Boost/恢复按钮、通知 | 改规则 5s 内日志出现 `configuration updated`；Boost 后风扇实测拉满 |
| P5 打包收尾 | 图标、Info.plist、SMAppService、install/uninstall.sh、README | 干净安装→重启登录自启→卸载无残留 |

每阶段独立可交付；P2 完成前 P3 可先用现有 status.json 字段开发。

---

## 7. 风险与备忘

- **`MenuBarExtra(style: .window)` 的已知怪癖**：弹窗失焦不自动关闭、不能
  拖动等。若体验不可接受，退回「NSStatusItem + NSPopover 承载
  `NSHostingView`」方案，UI 代码（SwiftUI 视图）完全复用，只换外壳。
- **/Users/Shared 可被任意本地用户写**：command.json 最坏情况是别的本地
  用户把风扇拉满或恢复自动——守护规则兜底后无过热风险，可接受；不引入
  XPC 的复杂度。
- **SPM app bundle 无 Xcode 工程**：沿用现有 install.sh 手工拼 .app 的做法，
  ad-hoc codesign 不变；`SMAppService` 对 ad-hoc 签名的 app 可用，但重装后
  需重新注册登录项（设置里开关一次即可），README 注明。
- **Swift Charts 数据量**：720 点直接画即可，无需抽稀。
