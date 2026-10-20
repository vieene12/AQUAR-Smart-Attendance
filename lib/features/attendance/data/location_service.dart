import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum LocationFailure {
  gpsDisabled,
  permissionDenied,
  permissionDeniedForever,
  timeout,
  inaccurate,
  unavailable,
}

class LocationServiceException implements Exception {
  const LocationServiceException(this.reason, {this.accuracyMeters});

  final LocationFailure reason;
  final double? accuracyMeters;
}

class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;
}

/// Adapter riêng để kiểm thử mà không dùng GPS hoặc mở hộp thoại quyền.
abstract class LocationPlatform {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<LocationFix> getCurrentPosition({required Duration timeout});
}

class GeolocatorLocationPlatform implements LocationPlatform {
  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<LocationFix> getCurrentPosition({required Duration timeout}) async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeout,
      ),
    );
    return LocationFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      timestamp: position.timestamp,
    );
  }
}

/// Gọi chủ động khi cần vị trí cho một thao tác chấm công, không theo dõi nền.
class LocationService {
  LocationService({LocationPlatform? platform})
    : _platform = platform ?? GeolocatorLocationPlatform();

  final LocationPlatform _platform;

  Future<LocationFix> getCurrentLocation({
    required double maxAccuracyMeters,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!maxAccuracyMeters.isFinite || maxAccuracyMeters <= 0) {
      throw ArgumentError.value(maxAccuracyMeters, 'maxAccuracyMeters');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout');
    }

    try {
      if (!await _platform.isLocationServiceEnabled()) {
        throw const LocationServiceException(LocationFailure.gpsDisabled);
      }

      var permission = await _platform.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _platform.requestPermission();
      }
      switch (permission) {
        case LocationPermission.denied:
          throw const LocationServiceException(
            LocationFailure.permissionDenied,
          );
        case LocationPermission.deniedForever:
          throw const LocationServiceException(
            LocationFailure.permissionDeniedForever,
          );
        case LocationPermission.unableToDetermine:
          throw const LocationServiceException(LocationFailure.unavailable);
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          break;
      }

      final fix = await _platform
          .getCurrentPosition(timeout: timeout)
          .timeout(timeout);
      if (!fix.accuracyMeters.isFinite ||
          fix.accuracyMeters < 0 ||
          fix.accuracyMeters > maxAccuracyMeters) {
        throw LocationServiceException(
          LocationFailure.inaccurate,
          accuracyMeters: fix.accuracyMeters,
        );
      }
      return fix;
    } on LocationServiceException {
      rethrow;
    } on TimeoutException {
      throw const LocationServiceException(LocationFailure.timeout);
    } on LocationServiceDisabledException {
      throw const LocationServiceException(LocationFailure.gpsDisabled);
    } on PermissionDeniedException {
      throw const LocationServiceException(LocationFailure.permissionDenied);
    } catch (_) {
      throw const LocationServiceException(LocationFailure.unavailable);
    }
  }
}
