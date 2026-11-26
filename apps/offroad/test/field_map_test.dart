import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:offroad/main.dart';
import 'package:offroad/map_screen.dart';
import 'package:offroad_maps/overview.dart';
import 'package:offroad_storage/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cold start installs the Fiji archive and saves preferences locally',
    () async {
      final dir = await Directory.systemTemp.createTemp('offroad-test-');
      final file = File.fromUri(dir.uri.resolve('project.sqlite'));
      final db = ProjectDatabase(file);
      try {
        final tiles = await openOverview(dir);
        try {
          expect(tiles.mbtiles.getMetadata().name, 'Fiji starter map');
          for (final x in [1023, 0]) {
            // Taveuni straddles the seam. Both TMS columns must exist.
            expect(tiles.mbtiles.getTile(z: 10, x: x, y: 463), isNotNull);
          }
        } finally {
          tiles.dispose();
        }
        await db.saveValue('manual', [-18.14, 178.44]);
        await db.close();
        final reopened = ProjectDatabase(file);
        try {
          expect(await reopened.readValue('manual'), [-18.14, 178.44]);
          final tiles = await openOverview(dir);
          tiles.dispose();
        } finally {
          await reopened.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  testWidgets('desktop manual position and narrow layout use the same map', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = _WidgetDatabase();
    final project = LocalProject(db, _EmptyTiles(), false, null);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MapScreen(project: project, night: false, onTheme: () {}),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('Fiji Field Map'), findsOneWidget);
    await tester.tap(find.text('Set on map'));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
    // The map waits for the double-tap zoom gesture to time out.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();
    expect(find.text('Manual position'), findsOneWidget);
    final controller = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!;
    expect(controller.camera.zoom, greaterThanOrEqualTo(16));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(controller.camera.zoom, 17);
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pump();
    expect(controller.camera.zoom, 16);
    tester.view.physicalSize = const Size(390, 780);
    await tester.pump();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('satellite toggle loads tiles at high zoom without closing MBTiles', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final setup = (await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('offroad-sat-test-');
      final street = await openOverview(dir);
      final sat = await openOverview(dir, satellite: true);
      return (dir: dir, street: street, sat: sat);
    }))!;
    final dir = setup.dir;
    final street = setup.street;
    final sat = setup.sat;
    final db = _WidgetDatabase();
    try {
      final project = LocalProject(db, street, false, null, null, sat);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MapScreen(project: project, night: false, onTheme: () {}),
          ),
        ),
      );
      await tester.pump();
      final controller = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      // Zoom in to Suva street scale, then toggle satellite -> street -> satellite.
      controller.move(const LatLng(-18.14, 178.44), 15);
      await tester.pump();
      await tester.tap(find.byTooltip('Satellite view'));
      await tester.pump();
      expect(find.text('Esri World Imagery · ESA Sentinel-2'), findsOneWidget);
      final satLayer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(satLayer.key, const ValueKey('satellite-base'));
      expect(satLayer.maxZoom, 20);
      expect(satLayer.maxNativeZoom, 12);
      // Switch back to street and then back to satellite: MBTiles must stay open.
      await tester.tap(find.byTooltip('Street map'));
      await tester.pump();
      await tester.tap(find.byTooltip('Satellite view'));
      await tester.pump();
      expect(sat.mbtiles.getTile(z: 12, x: 4078, y: 1838), isNotNull);
      expect(street.mbtiles.getTile(z: 10, x: 1019, y: 459), isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      await tester.runAsync(() async {
        street.dispose();
        sat.dispose();
        await dir.delete(recursive: true);
      });
    }
  });

  test(
    'satellite tile cache plans across 180 deg, prefetches, reads offline and clears',
    () async {
      final dir = await Directory.systemTemp.createTemp('offroad-sat-cache-');
      final cache = SatelliteTileCache(
        File.fromUri(dir.uri.resolve('sat-cache.sqlite')).path,
      );
      try {
        // Taveuni crosses 180° longitude.
        final tiles = SatelliteTileCache.planTiles(
          -16.9,
          179.95,
          -16.8,
          -179.95,
          minZoom: 13,
          maxZoom: 13,
        );
        expect(tiles.any((t) => t.x == (1 << 13) - 1), isTrue);
        expect(tiles.any((t) => t.x == 0), isTrue);
        final fakeJpeg = Uint8List.fromList([
          0xFF,
          0xD8,
          ...List.filled(200, 1),
        ]);
        final res = await cache.prefetch(
          tiles.take(3).toList(),
          fetcher: (z, x, y) async => fakeJpeg,
        );
        expect(res.downloaded, 3);
        expect(res.failed, 0);
        expect(cache.stats().count, 3);
        final second = await cache.prefetch(
          tiles.take(3).toList(),
          fetcher: (z, x, y) async => throw StateError('offline'),
        );
        expect(second.skipped, 3);
        expect(second.downloaded, 0);
        expect(
          cache.read(tiles.first.z, tiles.first.x, tiles.first.y),
          fakeJpeg,
        );
        cache.clear();
        expect(cache.stats().count, 0);
      } finally {
        cache.close();
        await dir.delete(recursive: true);
      }
    },
  );
}

class _WidgetDatabase extends Fake implements ProjectDatabase {
  @override
  Future<void> saveValue(String key, Object value) async {}
}

class _EmptyTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(TileProvider.transparentImage);
}
