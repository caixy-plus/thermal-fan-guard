# MyFans

M3 Max CPU/GPU temperature guard with a macOS menu bar app (**MyFans**). A root daemon samples SMC
every few seconds, applies multi-tier fan rules, and writes shared status files. The
SwiftUI menu bar app shows live temperature, fan speed, history charts, and settings.

## Requirements

- macOS 14+
- Apple Silicon Mac with SMC fan control

## Development

```sh
cd /Users/caixinyun/Workspace/thermal-fan-guard
swift test
swift run thermal-fan-guard --status
swift run ThermalFanGuardApp
```

## Install

```sh
./install.sh
```

This installs:

- root daemon: `/usr/local/libexec/thermal-fan-guard` (LaunchDaemon)
- menu bar app: `/Applications/MyFans.app`

After install, open the app and enable **登录时启动** in Settings to register the login
item via `SMAppService`. Reinstalling the app requires toggling that switch once.

Configuration persists in `/Users/Shared/com.caixinyun.thermal-fan-guard.json`.
Status, history, and manual commands use sibling `.status.json`, `.history.json`, and
`.command.json` files in the same directory.

Log: `tail -f /var/log/thermal-fan-guard.log`

Remove with `./uninstall.sh`.

## Release (官网分发)

官网直分发使用 **macOS 原生 flat distribution pkg**。用户双击 `.pkg`，系统 Installer.app 提供介绍、组件说明、许可、进度与完成页。

```sh
./scripts/package-pkg.sh
```

产物：`dist/pkg-build/MyFans-<version>.pkg`

### 组件

| 组件 | 路径 | 安装类型 |
|------|------|----------|
| MyFans 菜单栏应用 | `/Applications/MyFans.app` | 必装（灰选） |
| 后台守护进程 | `/usr/local/libexec/thermal-fan-guard` | 必装（灰选） |
| LaunchDaemon | `/Library/LaunchDaemons/…` | 随守护进程安装 |

「登录时启动」在应用设置里用 `SMAppService` 开关，不放进安装器。

### 签名与公证（可选）

```sh
export INSTALLER_SIGN_IDENTITY="Developer ID Installer: Your Name (TEAMID)"
export NOTARY_KEYCHAIN_PROFILE="notary-profile"
./scripts/package-pkg.sh
```

### GitHub Actions

- **CI** (`ci.yml`): `swift test` on push/PR to `main`
- **Release** (`release.yml`): push tag `v*` → 构建 `MyFans-<version>.pkg` → GitHub Release

**版本规则：tag 即版本号** — `v2.0` → 产物 `MyFans-2.0.pkg`，并写入 app/installer plist。

```sh
git tag v2.0
git push origin v2.0
```

本地按 tag 打包：`VERSION=2.0 ./scripts/package-pkg.sh`（或在 exact tag 检出时自动读取 tag）

### 其他打包方式

- 开发机本地安装：`./install.sh`
- SwiftUI 安装器 zip（可选）：`./scripts/package-installer.sh`
- DMG 外壳（可选）：`./scripts/make-dmg.sh`

The SMC implementation lives in the adjacent MIT-licensed `thermal-fan-guard-vendor`
checkout from https://github.com/agoodkind/macos-smc-fan.
