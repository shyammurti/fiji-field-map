import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:offroad_core/position.dart';
import 'package:offroad_maps/overview.dart';
import 'package:offroad_platform/device_position.dart';
import 'package:offroad_storage/storage.dart';
import 'package:path_provider/path_provider.dart';

import 'map_screen.dart';
import 'trail_session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FieldApp()));
}

final trackerProvider = Provider((ref) {
  final tracker = PositionTracker(DevicePosition());
  ref.onDispose(tracker.dispose);
  return tracker;
});
final positionProvider = StreamProvider<PositionState>((ref) async* {
  final tracker = ref.watch(trackerProvider);
  yield tracker.state;
  yield* tracker.changes;
});

class LocalProject {
  LocalProject(
    this.db,
    this.tiles,
    this.night,
    this.manual, [
    this.field,
    this.satellite,
    this.satelliteCache,
  ]);
  final TrailSession? field;
  final TileProvider? satellite;
  final SatelliteTileCache? satelliteCache;
  final ProjectDatabase db;
  final TileProvider tiles;
  final bool night;
  final List<double>? manual;

  static Future<LocalProject> open() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final db = ProjectDatabase(File.fromUri(dir.uri.resolve('project.sqlite')));
    try {
      final night = await db.readValue('night') == true;
      final coords = await db.readValue('manual');
      final manual =
          coords is List && coords.length == 2 && coords.every((v) => v is num)
          ? coords.cast<num>().map((v) => v.toDouble()).toList()
          : null;
      final assets = await Future.wait<Object>([
        installMapAsset(dir, 'fiji-roads.sqlite', 'fiji-roads-v1.sqlite'),
        openOverview(dir),
        openOverview(dir, satellite: true),
      ]);
      final index = assets[0] as File;
      final tiles = assets[1] as TileProvider;
      final satellite = assets[2] as TileProvider;
      final satCache = SatelliteTileCache(
        File.fromUri(dir.uri.resolve('satellite-hi-cache.sqlite')).path,
      );
      final field = TrailSession(db, index.path);
      await field.initialize();
      return LocalProject(db, tiles, night, manual, field, satellite, satCache);
    } catch (_) {
      await db.close();
      rethrow;
    }
  }
}

class FieldApp extends StatefulWidget {
  const FieldApp({super.key});
  @override
  State<FieldApp> createState() => _FieldAppState();
}

class _FieldAppState extends State<FieldApp> {
  late Future<LocalProject> project = LocalProject.open();
  bool? night;
  final notifications = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) => FutureBuilder<LocalProject>(
    future: project,
    builder: (context, result) {
      final data = result.data;
      final dark = night ?? data?.night ?? false;
      final colors = ColorScheme.fromSeed(
        seedColor: const Color(0xff385943),
        brightness: dark ? Brightness.dark : Brightness.light,
      );
      return MaterialApp(
        title: 'Fiji Field Map',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: notifications,
        theme: ThemeData(
          colorScheme: colors,
          useMaterial3: true,
          scaffoldBackgroundColor: dark
              ? const Color(0xff17241d)
              : const Color(0xfff6f5ec),
        ),
        home: data == null
            ? Scaffold(
                body: Center(
                  child: result.hasError
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Could not open local map storage.'),
                            FilledButton(
                              onPressed: () =>
                                  setState(() => project = LocalProject.open()),
                              child: const Text('Retry'),
                            ),
                          ],
                        )
                      : const CircularProgressIndicator(),
                ),
              )
            : MapScreen(
                project: data,
                night: dark,
                onTheme: () async {
                  setState(() => night = !dark);
                  try {
                    await data.db.saveValue('night', !dark);
                  } catch (_) {
                    notifications.currentState?.showSnackBar(
                      const SnackBar(
                        content: Text('Could not save map theme.'),
                      ),
                    );
                  }
                },
              ),
      );
    },
  );
}

Future<void> showMapLicense(BuildContext context) async {
  final license = await rootBundle.loadString('assets/map-license.txt');
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Map sources'),
      content: SingleChildScrollView(child: SelectableText(license)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
