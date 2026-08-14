# Changelog

## v0.2.0 — 2026-08-15

### Added
- **History view in the popover.** Click the index to switch to a 7- or 30-day trend:
  the national Dryness Index and the Rhine reference gauge at Kaub, with the four
  severity bands behind the index curve, a hover crosshair, and `Esc` to go back.
- **Index samples are recorded locally** after every refresh, with 400-day retention.
  NIWIS publishes no history for the aggregate the index is built from, so this is the
  only place that record exists. Recording gaps are drawn as gaps, not interpolated.
- **Gauge history from PEGELONLINE**, fetched on demand and cached for an hour, so the
  "polls at most every two hours" promise still holds.

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
