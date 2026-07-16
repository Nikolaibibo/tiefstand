# 🅣 Tiefstand

**A native macOS menu-bar app that shows Germany's nationwide low-water situation as a single, color-coded number — with a local-gauge option.**

> *Tiefstand* (German): a water body's lowest level — and, figuratively, a low point.

Germany now has a nationwide low-water information system, [**NIWIS**](https://niwis-online.de/), launched by the Federal Institute of Hydrology (BfG) on 15 July 2026. *Tiefstand* distills its data into one glanceable metric that lives in your menu bar, so you always know how dry the country's rivers and groundwater are right now.

> ⚠️ **Work in progress.** Runs as a real menu-bar app with live NIWIS data. Nearest-gauge (CoreLocation), the Germany map and a WidgetKit widget are next. Built in the open.

<p align="center">
  <img src="docs/preview.png" width="340" alt="Tiefstand popover with live NIWIS data">
</p>

<p align="center">
  <img src="docs/menubar.png" width="140" alt="Tiefstand in the macOS menu bar">
</p>

<p align="center"><sub>The running menu-bar app with live NIWIS data (16 Jul 2026, index 45 · “Elevated”).</sub></p>

---

## What it does

- **Menu bar:** the national **Dryness Index (0–100)**, color-coded, as a wave-fill indicator.
- **Popover dashboard:** per-domain breakdown (discharge, groundwater, spring flow, water level), a Germany map, and your **local gauge** with its class, trend and current value.
- **Desktop widget:** the index at a glance via WidgetKit.
- **Local option:** automatically resolves the nearest discharge + groundwater station via your location, or pin a favorite.

## The Dryness Index

*Tiefstand* condenses NIWIS's four-level low-water classification into one transparent score:

```
severity(station) = { none: 0, low: 33, very low: 67, extremely low: 100 }
domainScore(d)     = mean severity across d's stations (excluding no-data)
DrynessIndex       = (domainScore(discharge) + domainScore(groundwater)) / 2
```

- **Discharge + groundwater, weighted 50/50** — two independent hydrological compartments ("surface" and "sub-surface"). Water level is deliberately excluded to avoid double-counting surface water; spring flow is shown in the dashboard but kept out of the headline (sparse, regional network).
- The methodology is intentionally open so the number can be read, checked and challenged.

## Data sources

| | Source | Notes |
|---|---|---|
| Primary | [NIWIS](https://niwis-online.de/) (BfG) | Four-level classification, per-station trend, no auth |
| Fallback | [PEGELONLINE](https://www.pegelonline.wsv.de/) (WSV) | Documented, stable; binary low/normal/high |

A `DataProvider` protocol abstracts the source, so PEGELONLINE transparently takes over if the (newly launched, still-undocumented) NIWIS API changes.

## Architecture

- **Swift · SwiftUI · WidgetKit · CoreLocation**
- `DataProvider` protocol → `NIWISProvider` (primary) + `PEGELONLINEProvider` (fallback)
- Index computation is pure and unit-tested against live reference values.

## Build from source

Requires macOS + Xcode (or the Swift toolchain).

```bash
git clone https://github.com/Nikolaibibo/tiefstand.git
cd tiefstand
swift test              # run the TiefstandCore suite
Scripts/make-app.sh     # assemble build/Tiefstand.app and code-sign it
open build/Tiefstand.app
```

> `make-app.sh` wraps the SwiftPM release binary into a real `.app` bundle (`LSUIElement`, ad-hoc signed) — no Xcode project and no paid Apple Developer account required. A notarized `.dmg` release will follow; until then, build from source.

## Roadmap

- [x] Data layer: `DataProvider` protocol + NIWIS client + models
- [x] Dryness Index + unit tests against live reference
- [x] Menu-bar item (wave-fill glyph + number)
- [x] Popover dashboard (index + per-domain donuts + local station)
- [x] App bundle (`LSUIElement`) so it runs as a real menu-bar app
- [ ] Nearest gauge via CoreLocation + Germany map in the popover
- [ ] WidgetKit desktop widget
- [ ] PEGELONLINE fallback provider
- [ ] Hydro visual polish (light/dark)
- [ ] README screenshots + demo GIF, notarized release, landing page

## Attribution & license

Water data © [NIWIS / Bundesanstalt für Gewässerkunde (BfG)](https://niwis-online.de/) and the respective federal-state authorities, and © [WSV / PEGELONLINE](https://www.pegelonline.wsv.de/). Used with attribution per the sources' terms. *Tiefstand* is an independent project and is not affiliated with or endorsed by the BfG or WSV.

Code licensed under the [MIT License](./LICENSE).
