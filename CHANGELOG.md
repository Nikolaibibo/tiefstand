# Changelog

## v0.1.1 — 2026-07-19

### Fixed
- **Menu-bar value no longer goes stale.** The index was only refreshed when the
  popover was opened, so the menu-bar label sat frozen between clicks. The app
  now fetches once at launch and polls in the background on its own.

### Added
- **Background auto-refresh** every 120 minutes, plus an immediate refresh on
  wake from sleep (`NSWorkspace.didWakeNotification`) so the value can't sit
  stale for a full interval after a lid-close.

## v0.1.0 — 2026-07-16

- Initial release: SwiftUI `MenuBarExtra` app showing the national dryness index
  from NIWIS / PEGELONLINE, with a rich hydro popover and quit/settings menu.
