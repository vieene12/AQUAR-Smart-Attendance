import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:smart_attendance/features/attendance/data/location_service.dart';

void main() {
  test(
    'chỉ hỏi quyền khi gọi dịch vụ và trả vị trí kèm độ chính xác',
    () async {
      final platform = _FakeLocationPlatform()
        ..permission = LocationPermission.denied
        ..requestedPermission = LocationPermission.whileInUse;
      final service = LocationService(platform: platform);
      expect(platform.permissionRequests, 0);

      final fix = await service.getCurrentLocation(maxAccuracyMeters: 30);
      expect(platform.permissionRequests, 1);
      expect(platform.positionRequests, 1);
      expect(fix.latitude, 10.77);
      expect(fix.longitude, 106.69);
      expect(fix.accuracyMeters, 12);
    },
  );

  test('GPS tắt thì không hỏi quyền hoặc lấy vị trí', () async {
    final platform = _FakeLocationPlatform()..gpsEnabled = false;
    await _expectFailure(platform, LocationFailure.gpsDisabled);
    expect(platform.permissionRequests, 0);
    expect(platform.positionRequests, 0);
  });

  test('từ chối quyền sau yêu cầu', () async {
    final platform = _FakeLocationPlatform()
      ..permission = LocationPermission.denied
      ..requestedPermission = LocationPermission.denied;
    await _expectFailure(platform, LocationFailure.permissionDenied);
    expect(platform.permissionRequests, 1);
    expect(platform.positionRequests, 0);
  });

  test('từ chối vĩnh viễn không mở lại hộp thoại', () async {
    final platform = _FakeLocationPlatform()
      ..permission = LocationPermission.deniedForever;
    await _expectFailure(platform, LocationFailure.permissionDeniedForever);
    expect(platform.permissionRequests, 0);
    expect(platform.positionRequests, 0);
  });

  test('từ chối vĩnh viễn sau yêu cầu quyền', () async {
    final platform = _FakeLocationPlatform()
      ..permission = LocationPermission.denied
      ..requestedPermission = LocationPermission.deniedForever;
    await _expectFailure(platform, LocationFailure.permissionDeniedForever);
    expect(platform.permissionRequests, 1);
    expect(platform.positionRequests, 0);
  });

  test('lấy vị trí quá thời gian chờ', () async {
    final platform = _FakeLocationPlatform()
      ..positionFuture = Completer<LocationFix>().future;
    await expectLater(
      LocationService(platform: platform).getCurrentLocation(
        maxAccuracyMeters: 30,
        timeout: const Duration(milliseconds: 5),
      ),
      throwsA(
        isA<LocationServiceException>().having(
          (error) => error.reason,
          'reason',
          LocationFailure.timeout,
        ),
      ),
    );
  });

  test('vị trí không đủ chính xác trả sai số thực tế', () async {
    final platform = _FakeLocationPlatform()..fix = _fix(accuracyMeters: 75);
    await expectLater(
      LocationService(platform: platform)
          .getCurrentLocation(maxAccuracyMeters: 30),
      throwsA(
        isA<LocationServiceException>()
            .having(
              (error) => error.reason,
              'reason',
              LocationFailure.inaccurate,
            )
            .having((error) => error.accuracyMeters, 'accuracy', 75),
      ),
    );
  });

  test('quyền đã cấp không hỏi lại', () async {
    final platform = _FakeLocationPlatform();
    await LocationService(platform: platform)
        .getCurrentLocation(maxAccuracyMeters: 30);
    expect(platform.permissionRequests, 0);
  });
}

Future<void> _expectFailure(
  _FakeLocationPlatform platform,
  LocationFailure reason,
) => expectLater(
  LocationService(platform: platform).getCurrentLocation(maxAccuracyMeters: 30),
  throwsA(
    isA<LocationServiceException>().having(
      (error) => error.reason,
      'reason',
      reason,
    ),
  ),
);

LocationFix _fix({required double accuracyMeters}) => LocationFix(
  latitude: 10.77,
  longitude: 106.69,
  accuracyMeters: accuracyMeters,
  timestamp: DateTime.utc(2026, 10, 10),
);

class _FakeLocationPlatform implements LocationPlatform {
  bool gpsEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requestedPermission = LocationPermission.whileInUse;
  LocationFix fix = _fix(accuracyMeters: 12);
  Future<LocationFix>? positionFuture;
  int permissionRequests = 0;
  int positionRequests = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => gpsEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    return requestedPermission;
  }

  @override
  Future<LocationFix> getCurrentPosition({required Duration timeout}) {
    positionRequests++;
    return positionFuture ?? Future.value(fix);
  }
}
