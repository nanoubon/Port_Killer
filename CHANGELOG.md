# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-10-23 (Unreleased until tagged)

### Added

- Menu bar popover and main window with a sortable, multi-select table of TCP listening ports.
- Search by port, process name, or PID.
- Pins with exact port and process name matching; pinned ports sort first and show as "not running" when absent.
- Read-only rows for root and other-user listeners, with a copyable `sudo kill <pid>` command.
- Kill confirmation showing full name, path, port, and PID, with warnings for Docker, system, and other-user processes.
- SIGTERM first, then a prompt before SIGKILL.
- PID identity re-check immediately before signaling.
- Start at login through `SMAppService`.
- Settings window with auto refresh toggle and interval (3 to 60 seconds).
- Refresh only while the popover or window is visible.
- Unit tests for parsers, kill safety, and pin logic.
- `scripts/release.sh` for building release artifacts.

### Changed

- Minimum macOS version is 14.0.

### Removed

- Unfinished features from earlier prototypes (auto-kill rules, kill history, onboarding); their stored settings are deleted on first launch.

### Notes

- The first release is an unsigned, not notarized `.zip`. See the README for first-launch steps.
