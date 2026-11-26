import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:sqlite3/sqlite3.dart';

typedef TileKey = ({int z, int x, int y});

/// Persistent SQLite cache for high-resolution online satellite tiles (zooms 13–18).
/// Viewed or pre-downloaded tiles are stored locally so they keep working offline.
class SatelliteTileCache {
  SatelliteTileCache(this.path, {this.maxBytes = 250 * 1024 * 1024})
    : _db = sqlite3.open(path) {
    _db.execute('PRAGMA journal_mode=WAL;');
    _db.execute('PRAGMA synchronous=NORMAL;');
    _db.execute('PRAGMA busy_timeout=5000;');
    _db.execute(
      'CREATE TABLE IF NOT EXISTS tiles('
      'z INTEGER NOT NULL, x INTEGER NOT NULL, y INTEGER NOT NULL, '
      'data BLOB NOT NULL, used INTEGER NOT NULL, PRIMARY KEY(z, x, y))',
    );
    _db.execute('CREATE INDEX IF NOT EXISTS tiles_used ON tiles(used)');
  }

  final String path;
  final int maxBytes;
  final Database _db;
  bool _closed = false;
  int _writes = 0;

  static Uri tileUri(int z, int x, int y) => Uri.https(
    'server.arcgisonline.com',
    '/ArcGIS/rest/services/World_Imagery/MapServer/tile/$z/$y/$x',
  );

  Uint8List? read(int z, int x, int y) {
    if (_closed) return null;
    final rows = _db.select(
      'SELECT data FROM tiles WHERE z=? AND x=? AND y=?',
      [z, x, y],
    );
    if (rows.isEmpty) return null;
    return rows.first['data'] as Uint8List;
  }

  bool contains(int z, int x, int y) {
    if (_closed) return false;
    final rows = _db.select(
      'SELECT 1 FROM tiles WHERE z=? AND x=? AND y=? LIMIT 1',
      [z, x, y],
    );
    return rows.isNotEmpty;
  }

  void write(int z, int x, int y, Uint8List data) {
    if (_closed || data.isEmpty) return;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    _db.execute(
      'INSERT OR REPLACE INTO tiles(z, x, y, data, used) VALUES(?, ?, ?, ?, ?)',
      [z, x, y, data, now],
    );
    if (++_writes % 60 == 0) _prune();
  }

  void _prune() {
    if (_closed) return;
    final total =
        _db
                .select('SELECT COALESCE(SUM(length(data)), 0) AS s FROM tiles')
                .single['s']
            as int;
    if (total <= maxBytes) return;
    // Evict oldest 15% of rows when cache exceeds its budget.
    final count =
        _db.select('SELECT COUNT(*) AS c FROM tiles').single['c'] as int;
    final drop = math.max(1, (count * 0.15).ceil());
    _db.execute(
      'DELETE FROM tiles WHERE rowid IN '
      '(SELECT rowid FROM tiles ORDER BY used ASC LIMIT ?)',
      [drop],
    );
  }

  ({int count, int bytes}) stats() {
    if (_closed) return (count: 0, bytes: 0);
    final row = _db
        .select(
          'SELECT COUNT(*) AS c, COALESCE(SUM(length(data)), 0) AS b FROM tiles',
        )
        .single;
    return (count: row['c'] as int, bytes: row['b'] as int);
  }

  void clear() {
    if (_closed) return;
    _db.execute('DELETE FROM tiles');
    _db.execute('VACUUM');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _db.close();
  }

  static bool isValidImage(Uint8List bytes) {
    if (bytes.length < 128) return false;
    // JPEG (FF D8) or PNG (89 50 4E 47) or WebP (52 49 46 46)
    return (bytes[0] == 0xFF && bytes[1] == 0xD8) ||
        (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E) ||
        (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46);
  }

  /// Plans XYZ tile keys covering [south, west, north, east] across [minZoom]..[maxZoom].
  /// Handles antimeridian crossings (e.g. Taveuni in Fiji where west > east).
  static List<TileKey> planTiles(
    double south,
    double west,
    double north,
    double east, {
    int minZoom = 13,
    int maxZoom = 16,
  }) {
    final s = south.clamp(-85.0, 85.0);
    final n = north.clamp(-85.0, 85.0);
    if (n < s) return const [];
    double normLon(double lon) => ((lon + 180) % 360 + 360) % 360 - 180;
    final w = normLon(west), e = normLon(east);
    final lonRanges = w <= e ? [(w, e)] : [(w, 179.9999), (-180.0, e)];

    int lonToX(double lon, int z) =>
        (((lon + 180.0) / 360.0) * (1 << z)).floor().clamp(0, (1 << z) - 1);
    int latToY(double lat, int z) {
      final rad = lat * math.pi / 180.0;
      final v =
          (1.0 - math.log(math.tan(rad) + 1.0 / math.cos(rad)) / math.pi) / 2.0;
      return (v * (1 << z)).floor().clamp(0, (1 << z) - 1);
    }

    final result = <TileKey>[];
    for (var z = minZoom; z <= maxZoom; z++) {
      final yTop = latToY(n, z);
      final yBot = latToY(s, z);
      for (final (rw, re) in lonRanges) {
        final xLeft = lonToX(rw, z);
        final xRight = lonToX(re, z);
        for (var x = xLeft; x <= xRight; x++) {
          for (var y = yTop; y <= yBot; y++) {
            result.add((z: z, x: x, y: y));
          }
        }
      }
    }
    return result;
  }

  /// Downloads and caches [tiles] for offline use with bounded concurrency.
  Future<({int downloaded, int skipped, int failed})> prefetch(
    List<TileKey> tiles, {
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
    Future<Uint8List?> Function(int z, int x, int y)? fetcher,
  }) async {
    int downloaded = 0, skipped = 0, failed = 0, done = 0;
    final total = tiles.length;
    final client = fetcher == null
        ? (HttpClient()
            ..connectionTimeout = const Duration(seconds: 6)
            ..maxConnectionsPerHost = 4)
        : null;
    try {
      final queue = <TileKey>[];
      for (final t in tiles) {
        if (contains(t.z, t.x, t.y)) {
          skipped++;
          done++;
        } else {
          queue.add(t);
        }
      }
      onProgress?.call(done, total);
      var cursor = 0;
      Future<void> worker() async {
        while (cursor < queue.length) {
          if (cancelled?.call() == true || _closed) return;
          final tile = queue[cursor++];
          try {
            Uint8List? bytes;
            if (fetcher != null) {
              bytes = await fetcher(tile.z, tile.x, tile.y);
            } else {
              bytes = await _fetchOnline(client!, tile.z, tile.x, tile.y);
            }
            if (bytes != null && isValidImage(bytes)) {
              write(tile.z, tile.x, tile.y, bytes);
              downloaded++;
            } else {
              failed++;
            }
          } catch (_) {
            failed++;
          }
          done++;
          onProgress?.call(done, total);
        }
      }

      await Future.wait([for (var i = 0; i < 4; i++) worker()]);
      _prune();
      return (downloaded: downloaded, skipped: skipped, failed: failed);
    } finally {
      client?.close(force: true);
    }
  }

  static Future<Uint8List?> _fetchOnline(
    HttpClient client,
    int z,
    int x,
    int y,
  ) async {
    final req = await client
        .getUrl(tileUri(z, x, y))
        .timeout(const Duration(seconds: 6));
    req.headers.set(HttpHeaders.userAgentHeader, 'FijiFieldMap/0.2.2');
    final res = await req.close().timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      await res.drain<void>();
      return null;
    }
    final bytes = await consolidateHttpClientResponseBytes(res)
        .timeout(const Duration(seconds: 10));
    return bytes;
  }
}

/// High-resolution satellite [TileProvider] that serves cached tiles offline,
/// fetches & caches missing tiles when online, and falls back to transparent
/// tiles when offline so the bundled Fiji Sentinel-2 layer shows through.
class CachedSatelliteTileProvider extends TileProvider {
  CachedSatelliteTileProvider(this.cache, {this.offlineOnly = false});
  final SatelliteTileCache cache;
  final bool offlineOnly;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..maxConnectionsPerHost = 6;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _CachedSatelliteImageProvider(
        coordinates: coordinates,
        cache: cache,
        client: _client,
        offlineOnly: offlineOnly,
      );

  @override
  void dispose() {
    _client.close(force: true);
    // Intentionally do not close [cache]; it is owned by the app session.
    super.dispose();
  }
}

class _CachedSatelliteImageProvider
    extends ImageProvider<_CachedSatelliteImageProvider> {
  const _CachedSatelliteImageProvider({
    required this.coordinates,
    required this.cache,
    required this.client,
    required this.offlineOnly,
  });

  final TileCoordinates coordinates;
  final SatelliteTileCache cache;
  final HttpClient client;
  final bool offlineOnly;

  @override
  Future<_CachedSatelliteImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _CachedSatelliteImageProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _loadAsync(decode),
    scale: 1,
    debugLabel: 'sat:${coordinates.z}/${coordinates.x}/${coordinates.y}',
  );

  Future<Codec> _loadAsync(ImageDecoderCallback decode) async {
    final z = coordinates.z;
    final n = 1 << z;
    final x = ((coordinates.x % n) + n) % n;
    final y = coordinates.y;
    if (y < 0 || y >= n) {
      return decode(
        await ImmutableBuffer.fromUint8List(TileProvider.transparentImage),
      );
    }
    final cached = cache.read(z, x, y);
    if (cached != null) {
      return decode(await ImmutableBuffer.fromUint8List(cached));
    }
    if (!offlineOnly) {
      try {
        final bytes = await SatelliteTileCache._fetchOnline(client, z, x, y);
        if (bytes != null && SatelliteTileCache.isValidImage(bytes)) {
          cache.write(z, x, y, bytes);
          return decode(await ImmutableBuffer.fromUint8List(bytes));
        }
      } catch (_) {
        // Offline or network timeout: fall back cleanly to base offline layer.
      }
    }
    return decode(
      await ImmutableBuffer.fromUint8List(TileProvider.transparentImage),
    );
  }
}
