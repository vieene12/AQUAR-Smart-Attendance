import 'package:geolocator/geolocator.dart';
import 'package:smart_attendance/features/admin/attendance_location/data/attendance_location_repository.dart';
import 'package:smart_attendance/features/attendance/data/location_service.dart';

class AttendanceLocationNotConfiguredException implements Exception {
  const AttendanceLocationNotConfiguredException();
}

class AttendanceLocationConfigUnavailableException implements Exception {
  const AttendanceLocationConfigUnavailableException([this.cause]);

  final Object? cause;
}

class AttendanceOutsideAreaException implements Exception {
  const AttendanceOutsideAreaException(this.distanceMeters, this.radiusMeters);

  final double distanceMeters;
  final double radiusMeters;
}

abstract class AttendanceLocationGate {
  Future<void> verify();
}

class ConfiguredAttendanceLocationGate implements AttendanceLocationGate {
  ConfiguredAttendanceLocationGate({
    AttendanceLocationRepository? repository,
    LocationService? locationService,
  }) : _repository = repository ?? FirestoreAttendanceLocationRepository(),
       _locationService = locationService ?? LocationService();

  final AttendanceLocationRepository _repository;
  final LocationService _locationService;

  @override
  Future<void> verify() async {
    final AttendanceLocationConfig? config;
    try {
      config = await _repository.load();
    } catch (error) {
      throw AttendanceLocationConfigUnavailableException(error);
    }
    if (config == null) {
      throw const AttendanceLocationNotConfiguredException();
    }
    if (!config.isValid) {
      throw AttendanceLocationConfigUnavailableException(
        const FormatException('Cấu hình vị trí không hợp lệ.'),
      );
    }

    final fix = await _locationService.getCurrentLocation(
      maxAccuracyMeters: config.maxAccuracyMeters,
    );
    if (!fix.latitude.isFinite ||
        fix.latitude < -90 ||
        fix.latitude > 90 ||
        !fix.longitude.isFinite ||
        fix.longitude < -180 ||
        fix.longitude > 180) {
      throw const LocationServiceException(LocationFailure.unavailable);
    }
    final distance = Geolocator.distanceBetween(
      fix.latitude,
      fix.longitude,
      config.latitude,
      config.longitude,
    );
    if (!distance.isFinite) {
      throw const LocationServiceException(LocationFailure.unavailable);
    }
    if (distance > config.radiusMeters) {
      throw AttendanceOutsideAreaException(distance, config.radiusMeters);
    }
  }
}
