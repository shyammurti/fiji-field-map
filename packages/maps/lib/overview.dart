import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';

export 'satellite_cache.dart';

Future<File> installMapAsset(
  Directory support,
  String asset,
  String name,
) async {
  final target = File.fromUri(support.uri.resolve(name));
  if (!await target.exists()) {
    final temporary = await support.createTemp('map-');
    try {
      final bytes = await rootBundle.load('assets/$asset');
      final file = File.fromUri(temporary.uri.resolve(asset));
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      try {
        await file.rename(target.path);
      } on FileSystemException {
        if (!await target.exists()) rethrow;
      }
    } finally {
      await temporary.delete(recursive: true);
    }
  }
  return target;
}

Future<MbTilesTileProvider> openOverview(
  Directory support, {
  bool satellite = false,
}) async {
  final file = await installMapAsset(
    support,
    satellite ? 'fiji-satellite.mbtiles' : 'fiji.mbtiles',
    satellite ? 'fiji-satellite-2021-v1.mbtiles' : 'fiji-starter-v1.mbtiles',
  );
  return MbTilesTileProvider.fromPath(
    path: file.path,
    silenceTileNotFound: true,
  );
}

/// Returns a non-owning view of an [MbTilesTileProvider] so remounting a
/// [TileLayer] (for example when toggling street and satellite views) does not
/// close the shared SQLite MBTiles connection on dispose.
TileProvider sharedTileProvider(TileProvider source) =>
    source is MbTilesTileProvider
    ? MbTilesTileProvider(
        mbtiles: source.mbtiles,
        silenceTileNotFound: source.silenceTileNotFound,
      )
    : source;
