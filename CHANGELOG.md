# Changelog

## Unreleased

### Added
- **A map of every gauge in the country**, under the domain donuts: 357 discharge or
  287 groundwater stations as dots coloured by low-water class, over a thin outline of
  the border. The discharge data was already being fetched on every refresh and thrown
  away — only the driest station survived — so that view costs no extra request.
- **Point at a gauge** for its name, class, current reading, trend and days below the
  low-water threshold. `anzahlTageUnterGlw` has been arriving from NIWIS since the first
  release and had never been shown.

### Fixed
- A failed station fetch no longer takes the whole refresh down with it. The call was
  `try`, so a stumble on the map endpoint blanked the index too — even though the index
  is computed from the aggregates alone.
- The index tab decided "too sparse to plot" by counting points, so 32 samples recorded
  over 65 minutes passed the test and drew an invisible smudge against the right edge of
  a 7-day axis. It now measures how much of the window is actually covered, and says how
  long the app has been recording.

## v0.3.0 — 2026-08-15

### Added
- **Longer windows on the index: 3, 6 and 12 months**, alongside 7 and 30 days.
  Retention was already 400 days, so the log can hold them — they fill as the app
  keeps running, and the "n of N days" caption says how far along that is. The gauge
  keeps 7/30 days because PEGELONLINE serves a rolling month and **silently returns
  that same month** for a longer request, which would label 30 days of data as a year.
  Switching from a 12-month index view to the gauge clamps back to 30 days.
- **Discharge and groundwater as curves** under the index, on the same 0–100 axis.
  The headline number is the mean of the two, so on its own it hides which
  compartment is driving it — these overlays show whether the gap between surface
  and sub-surface water is widening or closing. The hover readout gives all three
  values at once. The samples have carried both scores since the history feature
  shipped, so the curves reach back over the whole recorded period.

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
