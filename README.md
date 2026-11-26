# Fiji Field Map

Fiji Field Map 0.2.2 for Android and desktop includes offline OSM road geometry, named trails and hybrid satellite imagery. Use **+ / −** or pinch to zoom. **Use device GPS** zooms to the first valid fix. The street layer draws roads from the local spatial index at zoom 11 and above. Satellite view bundles offline 2021 Sentinel-2 imagery through zoom 12 and automatically fetches and caches high-resolution Esri World Imagery tiles (zooms 13–18) on device when online, with a **Save satellite area offline** tool to pre-cache regions before heading off-road.

**Draw** collects map taps with an optional **Connect to road** toggle that snaps points within 45 m onto nearby OSM roads or saved trails. **Drive** on Android starts a location foreground service and writes raw fixes into a recoverable SQLite journal. Use **Review** or **Finish drive** to compare the line with the bundled Fiji roads and saved routes. Known intervals are removed, GPS gaps split the trace, and the new sections are highlighted together for naming (with a live **Connect to road** preview toggle). Matching uses distance and direction, with a 12 m tolerance, a 35° heading tolerance and a recording accuracy cutoff of 18 m. Closely parallel roads can match the wrong line. Draw and drive drafts survive closing the app.

Open **Routes** to rename, hide/show, delete, or navigate a section forward or in reverse. With a current or manually selected position, choose **Drive to section** for an offline approach using connected, motor-accessible OSM roads and saved trails. Guidance shows distance, bearing, turns, off-route distance and a speed-based ETA. Three successive off-route fixes during the approach can trigger a new route calculation. A disconnected network is reported to the user.

> Large generated assets (`apps/offroad/assets/fiji-roads.sqlite`, `apps/offroad/assets/fiji-satellite.mbtiles`) and release APKs are excluded from Git. Prebuilt signed APKs are published under **GitHub Releases**, and the offline map/road assets can be regenerated with the scripts in `tool/`.

**Route sync** is opt-in. From the dashboard Downloads section, open the authenticated **Route sync key** and paste it in **Routes → Sync** on each device. Paired devices share the private route library via HTTPS. The local outbox retries while the app is open and on resume. Only saved named routes and revisions are exchanged. Immutable revision IDs deduplicate retries and retain concurrent renames as separate heads. Use Disconnect to disable further exchanges. The host stores its copy under /mnt/media4/field-map-data.

## Build

Use Flutter 3.50.1 stable and Dart 3.14.0. Fetch development dependencies once with networking available. The installed app opens its local map in airplane mode.

    cd apps/offroad
    flutter pub get
    flutter run -d linux

From the same directory run the relevant native build command on its target OS.

| Target | Prerequisites | Build |
| --- | --- | --- |
| Linux | Clang, CMake, Ninja, pkg-config, GTK 3 development headers, C++ development toolchain | flutter build linux --release |
| macOS | Xcode with command-line tools and the Flutter macOS toolchain | flutter build macos --release |
| Windows | Visual Studio with Desktop development with C++, Windows SDK and CMake tools | flutter build windows --release |
| Android | Java 21, Android SDK, platform 36, build tools and the project's NDK version | flutter build apk --release |

The Android release build reads FIELD_MAP_KEYSTORE and FIELD_MAP_KEY_PASSWORD from the build environment. Use alias fieldmap in the signing keystore. Keep the signing key for in-place updates. For local development use flutter run on a device or emulator.

## Data and libraries

Flutter and material_ui provide the adaptive interface. flutter_map renders the same map across native targets. flutter_map_mbtiles opens the local raster archive. latlong2 supplies the map coordinates. flutter_riverpod binds the shared tracker to the UI. geolocator obtains OS fixes and flutter_compass reads the device heading. path_provider selects each OS's writable app directory. Drift stores device preferences in SQLite. The position tracker and signal-age policy live in packages/core and use only Dart.

Source, the generated starter MBTiles and build outputs reside on media4 in the homelab. Installed devices keep their own private map and preferences. Android requests location while in use. Drive starts a location foreground service from the visible activity and displays an ongoing notification. An interrupted drive is recoverable through its last committed fix.

## Verify the map and GPS

- Enable airplane mode before the first launch and leave Wi-Fi off. Confirm Fiji appears and pan from Viti Levu to Taveuni across 180°.
- Tap Use device GPS and grant precise, while-in-use location. With an outdoor fix, check coordinates and accuracy, then walk to check speed, follow and course.
- Rotate a phone with a compass and enable compass up. Drag the map to release follow. Tap Show Fiji to reset.
- Deny permission or turn device location off. The map must remain usable and offer a retry or location settings.
- Interrupt fixes. After 15 seconds the last fix becomes stale, after 45 seconds the app reports a lost signal. A fresh fix restores live status.
- Switch to the night map and reopen offline. On desktop, set a manual point, restart and verify its coordinates persist.
- Build and run tests from packages/core with dart pub get and dart test. From apps/offroad run flutter test and flutter analyze. To regenerate the committed Drift binding run dart run build_runner build in packages/storage after dart pub get.

The design directory contains the architecture proposal and full target schema. Database v2 migrates the original settings database in place and adds trail revisions and the durable sync outbox.
