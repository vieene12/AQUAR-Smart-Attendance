import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:smart_attendance/features/admin/attendance_location/data/attendance_location_repository.dart';
import 'package:smart_attendance/features/attendance/data/attendance_location_gate.dart';
import 'package:smart_attendance/features/attendance/data/location_service.dart';

void main() {
  test('trong bán kính và đủ chính xác thì được tiếp tục', () async {
    final repository = _FakeConfigRepository()..config = _config();
    final platform = _FakeLocationPlatform();
    await _gate(repository, platform).verify();
    expect(repository.loadCalls, 1);
    expect(platform.positionCalls, 1);
  });

  test('ngoài bán kính thì bị chặn', () async {
    final repository = _FakeConfigRepository()..config = _config();
    final platform = _FakeLocationPlatform()..longitude = 106.70;
    await expectLater(
      _gate(repository, platform).verify(),
      throwsA(isA<AttendanceOutsideAreaException>()),
    );
  });

  test('GPS tắt thì bị chặn trước khi lấy vị trí', () async {
    final repository = _FakeConfigRepository()..config = _config();
    final platform = _FakeLocationPlatform()..gpsEnabled = false;
    await expectLater(
      _gate(repository, platform).verify(),
      throwsA(
        isA<LocationServiceException>().having(
          (error) => error.reason,
          'reason',
          LocationFailure.gpsDisabled,
        ),
      ),
    );
    expect(platform.positionCalls, 0);
  });

  test('sai số GPS vượt cấu hình thì bị chặn', () async {
    final repository = _FakeConfigRepository()..config = _config();
    final platform = _FakeLocationPlatform()..accuracyMeters = 40;
    await expectLater(
      _gate(repository, platform).verify(),
      throwsA(
        isA<LocationServiceException>().having(
          (error) => error.reason,
          'reason',
          LocationFailure.inaccurate,
        ),
      ),
    );
  });

  test('chưa có cấu hình thì không yêu cầu GPS', () async {
    final repository = _FakeConfigRepository();
    final platform = _FakeLocationPlatform();
    await expectLater(
      _gate(repository, platform).verify(),
      throwsA(isA<AttendanceLocationNotConfiguredException>()),
    );
    expect(platform.positionCalls, 0);
  });

  test('không tải được cấu hình thì không yêu cầu GPS', () async {
    final repository = _FakeConfigRepository()..error = StateError('offline');
    final platform = _FakeLocationPlatform();
    await expectLater(
      _gate(repository, platform).verify(),
      throwsA(isA<AttendanceLocationConfigUnavailableException>()),
    );
    expect(platform.positionCalls, 0);
  });
}

ConfiguredAttendanceLocationGate _gate(
  _FakeConfigRepository repository,
  _FakeLocationPlatform platform,
) => ConfiguredAttendanceLocationGate(
  repository: repository,
  locationService: LocationService(platform: platform),
);

AttendanceLocationConfig _config() => const AttendanceLocationConfig(
  name: 'Trụ sở',
  latitude: 10.77,
  longitude: 106.69,
  radiusMeters: 100,
  maxAccuracyMeters: 30,
);

class _FakeConfigRepository implements AttendanceLocationRepository {
  AttendanceLocationConfig? config;
  Object? error;
  int loadCalls = 0;

  @override
  Future<AttendanceLocationConfig?> load() async {
    loadCalls++;
    if (error != null) throw error!;
    return config;
  }

  @override
  Future<AttendanceLocationConfig> save(
    AttendanceLocationConfig config,
  ) async => throw UnimplementedError();
}

class _FakeLocationPlatform implements LocationPlatform {
  bool gpsEnabled = true;
  double longitude = 106.69;
  double accuracyMeters = 10;
  int positionCalls = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => gpsEnabled;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationFix> getCurrentPosition({required Duration timeout}) async {
    positionCalls++;
    return LocationFix(
      latitude: 10.77,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      timestamp: DateTime.utc(2026, 10, 10),
    );
  }
}
