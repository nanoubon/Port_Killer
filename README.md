# Port Killer

A native macOS menu bar app that shows which process is holding a TCP port and lets you kill it safely.

<!-- TODO: screenshots -->

## Features

- Menu bar popover for quick access, plus a main window with a sortable table (Port, Process, PID, User, Address) and multi-row selection.
- Search by port, process name, or PID.
- Pins: pin a port by exact port and process name. Pinned ports stay at the top, and a pinned port that is not running appears as a dimmed row you can unpin.
- Read-only rows for listeners owned by root or another user. You cannot kill them from the app, but you can copy the `sudo kill <pid>` command.
- Every kill needs confirmation. The dialog shows the full process name, executable path, port, and PID, with warnings for Docker, macOS system processes, and other-user processes. Port Killer refuses to kill itself.
- Kill sends SIGTERM and waits about 3 seconds. If the process is still running, the app asks before it sends SIGKILL.
- Before sending a signal, the app re-checks that the PID is still the same process (start time, owner, name) and still listens on that port. If not, it sends nothing.
- Start at login (uses the system login item API; the switch reflects the real system state).
- Auto refresh runs only while the popover or main window is visible (3 to 60 seconds, default 5).

## Requirements

- macOS 14 (Sonoma) or later.

## Install

The first release is unsigned and not notarized, as a `.dmg` or a `.zip`. macOS Gatekeeper blocks it on first launch.

1. Download the `.dmg` (or `.zip`) from the GitHub Releases page and open it.
2. Drag `Port Killer.app` to `/Applications` (the `.dmg` window has a shortcut to it).
3. Open it once with one of these methods:
   - Right-click (or Control-click) the app, choose **Open**, then click **Open** in the dialog.
   - Or double-click the app, then open **System Settings › Privacy & Security**, scroll to the Security section, and click **Open Anyway**.

You only need to do this once. Do not disable Gatekeeper system-wide.

Advanced: you can instead remove the quarantine attribute from the app. Do this only if you trust the download.

```bash
xattr -dr com.apple.quarantine "/Applications/Port Killer.app"
```

The app has no Dock icon at rest. Look for its icon in the menu bar.

## Build from source

You need the full Xcode app. The project was created with Xcode 26.2; use a recent Xcode. There are no third-party dependencies.

```bash
git clone <repository-url>
cd Port_Killer
open "Port Killer.xcodeproj"
```

Select the `Port Killer` scheme and run. Or build from the command line:

```bash
xcodebuild -project "Port Killer.xcodeproj" -scheme "Port Killer" -configuration Debug build
```

If `xcode-select -p` prints `/Library/Developer/CommandLineTools`, `xcodebuild` fails. Either run `sudo xcode-select -s /Applications/Xcode.app`, or prefix the command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

### Run tests

```bash
xcodebuild test -project "Port Killer.xcodeproj" -scheme "Port Killer" -derivedDataPath "$TMPDIR/pk-dd" CODE_SIGNING_ALLOWED=NO
```

Tests cover the lsof and netstat parsers, kill safety rules, and pin logic. Fixtures are in `Port KillerTests/Fixtures`.

### Release build

`scripts/release.sh` runs the tests, builds a Release app (hardened runtime; universal arm64 + x86_64 when the toolchain supports it), signs it, and writes the artifact and its SHA-256 to `dist/`. It publishes nothing.

- Default: ad-hoc signed, not notarized `Port-Killer-<version>-unsigned.zip` and `Port-Killer-<version>-unsigned.dmg`.
- With a "Developer ID Application" identity in the keychain and `NOTARY_PROFILE` set (a `notarytool` keychain profile name): signed, notarized, stapled `Port-Killer-<version>.dmg`.

```bash
scripts/release.sh --dry-run            # print the steps only
scripts/release.sh --version 1.0.0      # build into ./dist
```

Other options: `--out DIR`, `--notarize` (fail instead of falling back if credentials are missing). Run `scripts/release.sh --help` for details.

## Privacy

Port Killer makes no network requests and has no telemetry or analytics. The source contains no networking code. It only reads local process and port data and stores its settings and pins in `UserDefaults`.

## Why the App Sandbox is off

The app runs `/usr/sbin/lsof` and `/usr/sbin/netstat` to list listeners and sends signals to other processes. The App Sandbox blocks both, so `ENABLE_APP_SANDBOX` is set to `NO`.

## Limitations

- TCP listeners only. UDP is not shown.
- Root and other-user processes are listed read-only. Use the copied `sudo kill` command in a terminal.

## Project structure

```text
Port Killer/
  Port_KillerApp.swift     Entry point, scenes (main window, menu bar, Settings), commands
  AppActivation.swift      Switches Dock/menu-bar behavior while windows are open
  PortViewModel.swift      Single source of truth: refresh loop, kill flow, pins, login state
  PortServices.swift       Scan (lsof, netstat), kill (SIGTERM/SIGKILL), login item services
  LsofParser.swift         Parses lsof -F output
  NetstatParser.swift      Parses netstat output for read-only rows
  KillSafety.swift         Warnings, PID identity re-check, name sanitizing
  KillConfirmationView.swift  Confirmation dialog
  PinStore.swift           Pin logic and persistence
  PortItem.swift, PortRow.swift, ShellHelper.swift
  Views/                   MainWindowView, MenuBarPopoverView, SettingsView, PortActionsMenu
Port KillerTests/          XCTest unit tests and fixtures
scripts/release.sh         Release packaging
```

## License

MIT. See [LICENSE](LICENSE).
