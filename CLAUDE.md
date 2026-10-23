# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Port Killer is a native macOS SwiftUI app that lists TCP listening ports (via `lsof`) and kills the owning processes. It runs as a menu bar agent (`LSUIElement = YES`, no Dock icon) with an optional main window. No third-party dependencies, no Swift packages.

## Build & run

- Open `Port Killer.xcodeproj` in Xcode (single target and scheme, both named `Port Killer`). Deployment target is macOS 14.0 (Sonoma); any recent full Xcode builds it.
- CLI builds need the full Xcode, not CommandLineTools. Either `sudo xcode-select -s /Applications/Xcode.app` or prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
  ```bash
  xcodebuild -project "Port Killer.xcodeproj" -scheme "Port Killer" -configuration Debug build
  ```
- Tests: XCTest target `Port KillerTests` (parsers, kill safety, pin logic; fixtures in `Port KillerTests/Fixtures`). Run `xcodebuild test -project "Port Killer.xcodeproj" -scheme "Port Killer" -derivedDataPath "$TMPDIR/pk-dd" CODE_SIGNING_ALLOWED=NO`. There is no linter config.
- The project uses `PBXFileSystemSynchronizedRootGroup`: any `.swift` file placed under `Port Killer/` is compiled automatically. Do not hand-edit `project.pbxproj` to add files.

## Build settings that shape the code

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` (Swift 5 language mode). Everything is MainActor by default, so code that must run off the main thread is explicitly marked `nonisolated` (e.g. `ShellHelper.executeCommand`, `ShellCommandResult.succeeded`) or lives in an `actor`.
- `ENABLE_APP_SANDBOX = NO` is required: the app spawns `/usr/sbin/lsof` and `/bin/kill` via `Process`. Re-enabling the sandbox breaks scanning and killing.

## Architecture

Data flows one way: shell, then service actors, then the view model, then the SwiftUI views.

- **`ShellHelper.swift`**: synchronous `Process` wrapper. Always pass an absolute executable path and an argument array (no shell interpolation).
- **Parsers** (pure, fixture-tested): `LsofParser` reads `lsof -iTCP -sTCP:LISTEN -P -n +c 0 -F pcLun` field output (IPv6, escaped spaces); `NetstatParser` reads `netstat -anv -p tcp` for root/other-user listeners.
- **`PortServices.swift`**: `PortScanService` (actor) runs lsof (failure is thrown) and merges netstat-only pairs as read-only snapshots (netstat failure is silent). `ProcessInspector` does libproc lookups (name, path, owner, start-time identity). `ProcessKillerService` (actor): SIGTERM, polls ~3 s, `forceKill` (SIGKILL) only after user confirmation; both call a `verify` closure right before signaling. `LaunchAtLoginService` wraps `SMAppService.mainApp`.
- **Kill flow**: `PortViewModel.requestKill` rejects read-only rows (user gets a `sudo kill` copy action instead) and unverifiable PIDs, runs `KillSafety.classify` (Docker/system/other-user/self warnings; self is blocking), and sets a pending `KillRequest` (one at a time, expires after 30 s). `KillConfirmationView` shows name, path, port, PID, warnings. On confirm, `KillSafety.revalidate` (same start time/uid/path, matching name, still on the port) gates every signal; if SIGTERM leaves the process running, a second confirm gates SIGKILL.
- **`PortViewModel.swift`**: single source of truth (`ObservableObject`). Owns the refresh loop (Combine timer + cancellable `Task`; `refreshGeneration` discards stale scans), the kill flow, pins (via `PinStore`), banners, and Start at login state. The timer runs only while `visibleSurfaces` is non-empty (idempotent `setSurface(_:visible:)`, driven from real NSWindow state by `WindowVisibilityReader`; interval 3...60 s, default 5). Banners show in one origin only and are announced to VoiceOver; the 30 s pending expiry pauses while the confirmation panel has focus. Persistence is `UserDefaults` under `PortKiller.*` keys; `removeLegacyStorageKeys()` deletes keys of removed features. Start at login is never persisted: it is read from `SMAppService.mainApp.status`.
- **No demo data**: production code never fabricates ports or metrics; only `#Preview` may.
- **`PinStore.swift`**: pure pin logic (exact port + process-name match, pinned-first sort, "not running" `PinnedEntry` placeholders, migration of lsof names truncated to 9 chars). Unit-tested with a throwaway `UserDefaults` suite.
- **`PortItem.swift` / `PortRow.swift`**: `PortItem` is the domain model (`id` = `"port-pid-processName"`; `isReadOnly`, `ownerLabel` for netstat-only rows). `PortRow` is the table/popover line (live item or a not-running pin) built by `PortViewModel.rows(matching:)`.
- **`Port_KillerApp.swift`**: `PortKillerLauncher` (`@main`) picks `Port_KillerApp` on macOS 15+ (`.defaultLaunchBehavior(.suppressed)`) or `LegacyPort_KillerApp` on macOS 14 (no such API; `AppActivation.registerMainWindow` closes the launch-time window unless a one-shot open request is pending). Both use `SharedScenes`: `MenuBarExtra` (`.window` style) and `Settings`, with one shared `PortViewModel` as environment object. `PortCommands` adds the Ports menu (⌘R, ⌘Delete).
- **`AppActivation.swift`**: tracks main/Settings windows by `ObjectIdentifier` (registered by `WindowAccessor`, removed on `willClose`) and derives the activation policy from whether the set is empty (`.regular` / `.accessory`).
- **`Views/`**: `MainWindowView` (SwiftUI `Table`, search, toolbar), `MenuBarPopoverView`, `SettingsView` (Start at login, refresh interval, version, GitHub link), `PortActionsMenu` (shared context menu: kill, copy PID/port, pin, copy `sudo kill`, Activity Monitor; `TagLabel`). `Components` holds shared visuals: `ProcessIconView` (app bundle icon or category symbol, cached by `ProcessIcon`), `PortBadge` (`PortRange` tint), `AddressScope`, `StatChip`, `PortSummaryBar`, `SettingsIcon`. Use system colors and fonts; there is no custom color palette.
- **Tests**: `Port KillerTests/` (`LsofParserTests`, `NetstatParserTests`, `KillSafetyTests`, `PinStoreTests`) with fixtures in `Fixtures/`. UI is not unit-tested.
- **Release**: `scripts/release.sh` (see `--help`; `--dry-run` prints steps). Ad-hoc `.zip` and `.dmg` by default; Developer ID + notarized `.dmg` when an identity and `NOTARY_PROFILE` exist. Output goes to `dist/`. Team ID in the project is `F74446W6S9`.
- **Docs**: `README.md`, `CHANGELOG.md`, and the design spec `docs/superpowers/specs/2026-10-23-simplify-for-github-design.md`. Some UI strings are still Thai.

## Design references

- `UI/<screen>/code.html` + `screen.png`: HTML mockups from the earlier design. The current UI is native macOS controls and no longer follows them closely.
- `UI/monolith_dark/DESIGN.md`: the design system spec ("The Precise Instrument"). Historical reference only: the app no longer implements its custom palette.
- `App Icon Sources/philosophy.md`: the icon's visual concept.
