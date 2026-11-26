import 'dart:io';

import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:offroad_core/position.dart';

class DevicePosition implements PositionSource {
  @override
  Future<FixStatus> prepare() async {
    if (!await Geolocator.isLocationServiceEnabled()) return FixStatus.disabled;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied)
      permission = await Geolocator.requestPermission();
    return switch (permission) {
      LocationPermission.denied => FixStatus.denied,
      LocationPermission.deniedForever => FixStatus.blocked,
      _ => FixStatus.searching,
    };
  }

  @override
  Stream<Fix> fixes() async* {
    final settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            forceLocationManager: true,
            intervalDuration: const Duration(seconds: 1),
            distanceFilter: 0,
          )
        : const LocationSettings(accuracy: LocationAccuracy.high);
    try {
      await for (final fix in Geolocator.getPositionStream(
        locationSettings: settings,
      )) {
        yield Fix(
          fix.latitude,
          fix.longitude,
          fix.timestamp,
          altitude: fix.altitude.isFinite ? fix.altitude : null,
          speed: _nonNegative(fix.speed),
          accuracy: _nonNegative(fix.accuracy),
          course: fix.speed > 0 && fix.heading >= 0 && fix.heading < 360
              ? fix.heading
              : null,
        );
      }
    } on LocationServiceDisabledException {
      throw FixStatus.disabled;
    } on PermissionDeniedException {
      throw FixStatus.denied;
    }
  }

  double? _nonNegative(double v) => v.isFinite && v >= 0 ? v : null;

  @override
  Stream<double?> headings() {
    if (!Platform.isAndroid && !Platform.isIOS) return const Stream.empty();
    return FlutterCompass.events?.map((e) => e.heading) ?? const Stream.empty();
  }

  Future<bool> openSettings(FixStatus status) => status == FixStatus.blocked
      ? Geolocator.openAppSettings()
      : Geolocator.openLocationSettings();
}
