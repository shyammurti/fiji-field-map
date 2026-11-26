/// Geographic coverage of the bundled Fiji map. Fiji occupies both the east
/// and west edge of the conventional longitude range.
class FijiStarter {
  static const centerLat = -17.35, centerLon = 178.65;
  static const minZoom = 5, maxZoom = 10;
  static double longitude(double value) => (value + 180) % 360 - 180;
  static bool covers(double lat, double lon) {
    final x = longitude(lon);
    return lat >= -21.2 && lat <= -12 && (x >= 176 || x <= -177.7);
  }
}
