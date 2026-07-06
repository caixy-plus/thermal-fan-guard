# Thermal Fan Guard

M3 Max CPU/GPU temperature guard with a macOS menu bar app. A root daemon samples SMC
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
- menu bar app: `/Applications/Thermal Fan Guard.app`

After install, open the app and enable **登录时启动** in Settings to register the login
item via `SMAppService`. Reinstalling the app requires toggling that switch once.

Configuration persists in `/Users/Shared/com.caixinyun.thermal-fan-guard.json`.
Status, history, and manual commands use sibling `.status.json`, `.history.json`, and
`.command.json` files in the same directory.

Log: `tail -f /var/log/thermal-fan-guard.log`

Remove with `./uninstall.sh`.

The SMC implementation lives in the adjacent MIT-licensed `thermal-fan-guard-vendor`
checkout from https://github.com/agoodkind/macos-smc-fan.
