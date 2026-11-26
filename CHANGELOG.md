# Changelog

All notable changes to **Fiji Field Map** are documented here.

## [0.3.1] - 2026-11-26

### Improved
- **Live driving direction arrow & Heading-Up mode**: Replaced the static position dot with a rotated directional navigation puck (`DirectionPuck`) and forward heading cone using live GPS course (with movement-bearing calculation, compass fallback, and initial route direction before moving). Starting navigation now automatically engages **Heading-Up** map rotation, and Android GPS updates run at 1-second intervals for smoother driving tracking.
- **Push-down & auto-hiding bottom GPS tray**: On phones, the bottom GPS details drawer now starts collapsed as a slim single-line bar (tap or swipe up to expand, tap or swipe down to push down) and hides completely during active navigation for a full-screen driving view.

---

## [0.3.0] - 2026-11-26

### Added
- **Point A → Point B offline navigation service**:
  - New **Navigate** button on the main bar opens a Point A → Point B planner with **My GPS**, **Pick on map**, **Offline Search** across all 1,285 named Fiji OSM roads plus saved custom trails, **Swap A ↔ B**, live route preview (distance + ETA), and automatic off-route rerouting.
  - **Long-press shortcut**: Long-press anywhere on the map to drop Point B and plan directions immediately.
- **Live Active Speed & ETA HUD**:
  - High-contrast Google-Maps-style top turn banner scanning ahead along the route for real upcoming turns (`Turn right in 240 m`, `Keep left`, `Off route`, `Arrived`).
  - Bottom live telemetry bar displaying **Active Speed (`km/h`)**, smoothed **remaining drive time**, **clock arrival ETA** (`3:28 PM`), and remaining distance — with a Fiji road-speed baseline estimate even before moving.
  - Compact floating **Speedometer badge (`km/h`)** on the map whenever GPS is live outside active navigation.
- **Faster offline A* routing**: Replaced Vincenty heuristic with a fast admissible equirectangular lower bound, expanded off-road endpoint snapping to 250 m, and added a 250k node cap for instant feedback on disconnected islands.

---

## [0.2.2] - 2026-11-26

### Added
- **Hybrid high-resolution satellite view (zooms 13–18)**: When zoomed into satellite view with internet available, the app now loads crisp Esri World Imagery tiles (`z13–18`) on top of the bundled offline Fiji Sentinel-2 (`z5–12`) base layer and automatically saves viewed tiles to an on-device SQLite cache (`satellite-hi-cache.sqlite`, 250 MiB LRU cap) so they stay sharp offline. Uncached areas fall back seamlessly to the bundled offline Sentinel-2 layer.
- **Save satellite area offline**: Added a download button in the top bar while in satellite mode to pre-cache the visible area (`z13–16` / `z13–17`) with live progress, cancel support, cache size indicator, and a clear-cache option.

---

## [0.2.1] - 2026-11-26

### Fixed
- **Satellite view loading at all zoom levels**: Switching between street and satellite layers now mounts a fresh `TileLayer` backed by a non-owning `MbTilesTileProvider` (`sharedTileProvider`) so tiles load immediately at any zoom (`5–20`) without closing the shared SQLite MBTiles database. Matched the satellite ocean background (`#102a33`) to `fiji-satellite.mbtiles`.

### Added
- **Optional "Connect to road" snapping**: Added a **Connect to road** toggle chip in both the **Draw** and **Review** bars. When enabled, tapped points and reviewed new route endpoints within 45 m snap cleanly onto nearby OSM roads or saved trails, with a live preview toggle before saving.
- **Improved trail-to-trail & trail-to-road routing**: Extended offline A* graph attachment to 45 m onto OSM roads and bridged saved trail endpoints onto adjacent saved trails.
- **Delete & Hide buttons**:
  - Per-route **Hide / Show** button in **Routes**, inside the route detail sheet, a **Hide all / Show all** header toggle, and a quick map-side **Hide / Show routes** control (persisted locally).
  - Per-route **Delete** button with confirmation dialog, writing sync-safe tombstone revisions (`deleted: true`) validated by `server/sync.py`.

### Performance
- Scoped Riverpod `Consumer` widgets so live GPS and compass ticks no longer rebuild `FlutterMap` or road polylines.
- Added padded-viewport road caching (skipping SQLite queries on small pans), zoom-tier road filtering, memoized road polylines with simplification, and concurrent cold-start asset extraction.

---

## [0.2.0] - 2026-11-26

### Added
- **Draw & Drive new routes**: Tap **Draw** to plot custom trails or **Drive** on Android to record via a location foreground service (`DriveService.kt`) with a crash-recoverable SQLite journal.
- **Known-road filtering**: Reviewing a draw or drive compares against bundled Fiji OSM roads and saved trails (12 m distance, 35° heading tolerance, splitting on GPS gaps / >18 m accuracy) so only genuinely new sections are offered for naming and saving.
- **Offline street-level vector roads & zoom controls**: Bundled `fiji-roads.sqlite` OSM spatial index and routing graph, visible `+ / −` zoom buttons, auto-zoom to first fix, vector roads at zoom 11+, and street names at zoom 14+.
- **Offline 2021 Sentinel-2 satellite imagery**: Bundled `fiji-satellite.mbtiles` with a top-bar satellite view toggle.
- **Route naming & offline turn-by-turn navigation**: Name and rename trails, follow sections forward or in reverse, or tap **Drive to section** for offline A* routing with turn prompts, bearing, off-route distance, speed-based ETA, and automatic re-routing.
- **Private opt-in HTTPS route sync**: Durable Drift v2 local outbox with immutable revision IDs, concurrent rename head retention, and self-hosted `server/sync.py` backend.

---

## [0.1.0] - 2026-11-26

### Added
- Initial **M1** release of **Fiji Field Map** for Android and desktop.
- Bundled offline Fiji OSM starter basemap (`fiji.mbtiles`) covering both sides of the 180° antimeridian (Viti Levu to Taveuni and Rotuma).
- Live GPS position tracking with follow mode, compass-up rotation, stale/lost signal handling (15 s stale, 45 s lost), day/night map theme persistence, and desktop manual planning position.
- Architecture proposal (`design/architecture.txt`) and target SQLite schema (`design/schema.sql`).
