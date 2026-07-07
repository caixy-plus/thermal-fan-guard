# AGENTS.md

Generic project guidance for all coding agents (Claude Code, Cursor, Codex).
Agent-specific notes live in `CLAUDE.md` / `.cursor/rules/`.

**MyFans** is a macOS menu bar app + root daemon that guards CPU/GPU temperature
on Apple Silicon (targeted at M3 Max) by driving SMC fan speed through multi-tier
rules. Product name is **MyFans**; the internal/package name is `ThermalFanGuard`.

## Build, test, run

Requires macOS 14+, Swift 6 toolchain, and a sibling checkout of the vendored SMC
package at `../thermal-fan-guard-vendor` (from https://github.com/agoodkind/macos-smc-fan) —
`Package.swift` references it via `.package(path: "../thermal-fan-guard-vendor")`.
CI checks it out automatically; locally you must clone it next to this repo.

```sh
swift test                              # run all tests
swift test --filter GuardStateTests     # single test class
swift run thermal-fan-guard --status    # one-shot temp/fan readout (no root needed)
swift run ThermalFanGuardApp            # launch the menu bar app from source
sudo swift run thermal-fan-guard        # run the daemon in the foreground (needs root)
```

The daemon **must run as root** (it aborts with exit 77 otherwise) because SMC fan
writes require privilege. `--status` reads sensors only and runs unprivileged.

## Install / uninstall (dev machine)

```sh
./install.sh      # builds release, installs daemon + /Applications/MyFans.app, bootstraps LaunchDaemon
./uninstall.sh
tail -f /var/log/thermal-fan-guard.log
```

`install.sh` installs the daemon to `/usr/local/libexec/thermal-fan-guard`, the
LaunchDaemon plist to `/Library/LaunchDaemons/`, and the app bundle to
`/Applications/MyFans.app`. The **login item** is not installed — the user enables
it in-app (Settings → 登录时启动), which registers via `SMAppService`.

## Architecture

Three executables + one library share state through **JSON files in `/Users/Shared/`**
— there is no IPC socket or XPC. Each side polls / watches the files.

- **`ThermalFanGuardCore`** (library, no hardware deps) — all pure logic and the
  file-based data model. This is the only test target. Key types:
  - `GuardConfiguration` — rules + sample interval + override timeout + sensor
    groups; validates itself (`validation`), owns backward-compatible decoding of
    the old single-rule format, and persists to `…thermal-fan-guard.json`.
  - `GuardRule` — one tier: trigger temp/duration → fan %, plus recovery
    temp/duration (hysteresis).
  - `MultiRuleGuardState` / `ThermalGuardState` — the control state machine. Each
    rule is an independent hysteresis latch; the active fan speed is the **highest
    fan % among all currently-triggered rules** (`recomputeActiveRule`). Emits
    `GuardEscalation` events (escalated / deescalated / recovered).
  - `GuardCommand` — manual override request (`max` / `auto` / `clear`) written by
    the app to `…command.json`; carries `issuedAt` + `expiresAfter` and knows if
    it is stale/expired.
  - `GuardOverrideResolver` — pure function mapping a `GuardCommand` + config +
    daemon-start time → what the daemon should do (activate max, reset rules, clear
    the command file). Manual `max` overrides rule-based control.
  - `GuardRuntimeStatus` — daemon → app snapshot (`…status.json`): temp, sensor,
    mode, per-fan RPM, active rule, override label. `isOnline(configuration:)`
    uses `offlineThreshold` (4× sample interval).
  - `HistoryStore` / `TemperatureHistory` — rolling temperature history
    (`…history.json`) for the chart.
  - `InstallerHandoff` — one-shot file the installer writes and the app consumes on
    first launch (e.g. to auto-register the login item).

- **`ThermalFanGuard`** (`Sources/ThermalFanGuard/`, product `thermal-fan-guard`) —
  the **root daemon**. `main.swift` is the sample loop; `Hardware.swift`
  (`ThermalHardware`) is the only place that touches SMC (via `SMCKit`/`SMCFanKit`).
  Loop each tick: reload config if changed → resolve manual override → read hottest
  temp across enabled sensor groups → run the state machine → apply fan % or restore
  automatic control → write status + append history. On exit it always restores
  automatic fan control. Sensor reads try the hardware catalog first, then fall back
  to scanning `T***` SMC keys (`SENSOR_FALLBACK` log lines mark the fallback).

- **`ThermalFanGuardApp`** (`Sources/ThermalFanGuardApp/`, product `ThermalFanGuardApp`,
  bundle **MyFans.app**) — SwiftUI `MenuBarExtra` app. `AppModel` (`@MainActor`) is the
  hub: it watches the three shared files with `DispatchSource` file-system sources
  (plus a 5s fallback timer), exposes derived UI state, and issues manual overrides by
  writing `GuardCommand`. Because control is async through the daemon, `AppModel`
  tracks a `pendingManualOverride` with a cooldown (`sampleInterval + 2`) and a
  timeout, reconciling against incoming status. `LoginItemManager` wraps `SMAppService`;
  `NotificationManager` fires user notifications on escalation.

- **`MyFansInstaller`** (`Sources/MyFansInstaller/`) — optional standalone SwiftUI
  installer app (MVVM: `InstallEngine` does the work, `InstallerViewModel` drives the
  view). Used by the zip/DMG packaging path, not by the primary pkg.

### Shared file contract (`/Users/Shared/com.caixinyun.thermal-fan-guard*`)

| File | Writer | Reader | Purpose |
|---|---|---|---|
| `.json` (config) | app | daemon | rules & settings |
| `.status.json` | daemon | app | live status snapshot |
| `.history.json` | daemon | app | temperature history for chart |
| `.command.json` | app | daemon | manual override, cleared by daemon after handling |
| `.installer-handoff.json` | installer | app (first launch) | e.g. auto-enable login item |

All are world-readable JSON (0644); the daemon owns clearing `.command.json`.

## Release & versioning

**The git tag is the single source of truth for the version.** Push `vX.Y` (or `vX.Y.Z`)
→ `.github/workflows/release.yml` runs `swift test` → `./scripts/package-pkg.sh` →
publishes a GitHub Release with `MyFans-<version>.pkg`. Do **not** hardcode release
versions in plists — `scripts/set-version.sh` writes `VERSION` (from tag or env) into
`ThermalFanGuardApp-Info.plist` and `MyFansInstaller-Info.plist` before packaging.

```sh
git tag v2.0 && git push origin v2.0     # tag-driven release (CI)
VERSION=2.0 ./scripts/package-pkg.sh     # local pkg build (native flat distribution pkg)
```

Packaging scripts (`scripts/`): `package-pkg.sh` (primary, → `dist/pkg-build/`),
`build-pkg.sh`, `stage-app.sh`, `set-version.sh`; plus optional `package-installer.sh`
(zip) and `make-dmg.sh`. The pkg installs two required components (app + daemon);
signing/notarization are opt-in via `INSTALLER_SIGN_IDENTITY` / `NOTARY_KEYCHAIN_PROFILE`.

CI (`ci.yml`) runs `swift test` on push/PR to `main`, on `macos-15` runners (needed for
the Swift 6 toolchain).

## Conventions

- Two-space indentation in Swift; core logic stays pure and `Sendable` and lives in
  `ThermalFanGuardCore` so it is unit-testable without hardware/root.
- User-facing strings in the app are Simplified Chinese; code, logs, and identifiers
  are English.
- Config/rules validation lives in `GuardConfiguration.validation` — keep the app UI
  and daemon load path both going through `isValid` so invalid config falls back to
  `.defaults` rather than crashing.
