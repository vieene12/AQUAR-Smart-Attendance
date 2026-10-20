import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:smart_attendance/features/admin/attendance_location/data/attendance_location_repository.dart';
import 'package:smart_attendance/features/admin/attendance_location/presentation/attendance_location_screen.dart';
import 'package:smart_attendance/features/attendance/data/location_service.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/home/presentation/role_home_screens.dart';

void main() {
  test('cấu hình từ Firestore kiểm tra biên và các trường cần thiết', () {
    expect(_config().isValid, isTrue);
    expect(_config(latitude: 91).isValid, isFalse);
    expect(_config(longitude: -181).isValid, isFalse);
    expect(_config(radius: 0).isValid, isFalse);
    expect(_config(accuracy: 0).isValid, isFalse);
    expect(_config(name: '  ').isValid, isFalse);
    expect(
      () => AttendanceLocationConfig.fromMap({
        ..._config().toMap(),
        'extra': true,
      }),
      throwsFormatException,
    );
  });

  testWidgets('Admin mở mục Vị trí chấm công từ trang chủ', (tester) async {
    final repository = _FakeLocationRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminHomeScreen(
          profile: const UserProfile(
            uid: 'admin-1',
            displayName: 'Quản trị viên',
            role: UserRole.admin,
          ),
          onSignOut: () {},
          locationRepository: repository,
          locationService: LocationService(platform: _FakeLocationPlatform()),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Thiết lập vị trí chấm công'));
    await tester.tap(find.text('Thiết lập vị trí chấm công'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(AttendanceLocationScreen), findsOneWidget);
    expect(repository.loadCalls, 1);
  });

  testWidgets('hiển thị loading và cấu hình đã lưu', (tester) async {
    final pending = Completer<AttendanceLocationConfig?>();
    final repository = _FakeLocationRepository()..pendingLoad = pending;
    await _pumpScreen(tester, repository);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(_config());
    await tester.pump();
    expect(find.text('Địa điểm: Trụ sở'), findsOneWidget);
    expect(find.text('Bán kính: 100.0 m'), findsOneWidget);
  });

  testWidgets('form từ chối dữ liệu sai trước khi ghi', (tester) async {
    final repository = _FakeLocationRepository();
    await _pumpScreen(tester, repository);
    await tester.ensureVisible(find.text('Lưu cấu hình'));
    await tester.tap(find.text('Lưu cấu hình'));
    await tester.pump();
    expect(repository.saveCalls, 0);
    expect(find.text('Nhập tên địa điểm.'), findsOneWidget);
    expect(find.text('Nhập số lớn hơn 0.'), findsNWidgets(2));
  });

  testWidgets('lưu thành công chỉ sau khi repository xác nhận', (tester) async {
    final repository = _FakeLocationRepository();
    await _pumpScreen(tester, repository);
    await _fillForm(tester);
    await tester.ensureVisible(find.text('Lưu cấu hình'));
    await tester.tap(find.text('Lưu cấu hình'));
    await tester.pump();
    await tester.pump();
    expect(repository.saveCalls, 1);
    expect(repository.saved?.name, 'Trụ sở');
    expect(find.text('Đã lưu vị trí chấm công.'), findsOneWidget);
    expect(find.text('Địa điểm: Trụ sở'), findsOneWidget);
  });

  testWidgets('lỗi ghi Firestore không báo lưu thành công', (tester) async {
    final repository = _FakeLocationRepository()
      ..saveError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    await _pumpScreen(tester, repository);
    await _fillForm(tester);
    await tester.ensureVisible(find.text('Lưu cấu hình'));
    await tester.tap(find.text('Lưu cấu hình'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Đã lưu vị trí chấm công.'), findsNothing);
    expect(
      find.text('Không có quyền lưu hoặc đọc cấu hình vị trí.'),
      findsOneWidget,
    );
    expect(find.text('Chưa có cấu hình vị trí chấm công.'), findsOneWidget);
  });

  testWidgets('quyền GPS chỉ được hỏi khi nhấn lấy vị trí', (tester) async {
    final platform = _FakeLocationPlatform()
      ..permission = LocationPermission.denied;
    final repository = _FakeLocationRepository();
    await _pumpScreen(tester, repository, platform);
    expect(platform.permissionRequests, 0);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Độ chính xác GPS tối đa (m)'),
      '30',
    );
    await tester.ensureVisible(find.text('Lấy vị trí hiện tại'));
    await tester.tap(find.text('Lấy vị trí hiện tại'));
    await tester.pump();
    await tester.pump();
    expect(platform.permissionRequests, 1);
    expect(platform.positionRequests, 1);
    expect(repository.saveCalls, 0);
    expect(find.textContaining('Đã lấy vị trí hiện tại'), findsOneWidget);
  });

  testWidgets('lỗi quyền Firestore có nút thử lại', (tester) async {
    final repository = _FakeLocationRepository()
      ..loadError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    await _pumpScreen(tester, repository);
    expect(
      find.text('Không có quyền lưu hoặc đọc cấu hình vị trí.'),
      findsOneWidget,
    );
    repository.loadError = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pump();
    expect(repository.loadCalls, 2);
    expect(find.text('Chưa có cấu hình vị trí chấm công.'), findsOneWidget);
  });
}

AttendanceLocationConfig _config({
  String name = 'Trụ sở',
  double latitude = 10.77,
  double longitude = 106.69,
  double radius = 100,
  double accuracy = 30,
}) => AttendanceLocationConfig(
  name: name,
  latitude: latitude,
  longitude: longitude,
  radiusMeters: radius,
  maxAccuracyMeters: accuracy,
);

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeLocationRepository repository, [
  _FakeLocationPlatform? platform,
]) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AttendanceLocationScreen(
        repository: repository,
        locationService: LocationService(
          platform: platform ?? _FakeLocationPlatform(),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _fillForm(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Tên địa điểm'),
    'Trụ sở',
  );
  await tester.enterText(find.widgetWithText(TextFormField, 'Vĩ độ'), '10.77');
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Kinh độ'),
    '106.69',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Bán kính cho phép (m)'),
    '100',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Độ chính xác GPS tối đa (m)'),
    '30',
  );
}

class _FakeLocationRepository implements AttendanceLocationRepository {
  AttendanceLocationConfig? saved;
  Completer<AttendanceLocationConfig?>? pendingLoad;
  Object? loadError;
  Object? saveError;
  int loadCalls = 0;
  int saveCalls = 0;

  @override
  Future<AttendanceLocationConfig?> load() async {
    loadCalls++;
    if (loadError != null) throw loadError!;
    return pendingLoad?.future ?? saved;
  }

  @override
  Future<AttendanceLocationConfig> save(AttendanceLocationConfig config) async {
    saveCalls++;
    if (saveError != null) throw saveError!;
    return saved = config;
  }
}

class _FakeLocationPlatform implements LocationPlatform {
  LocationPermission permission = LocationPermission.whileInUse;
  int permissionRequests = 0;
  int positionRequests = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    return LocationPermission.whileInUse;
  }

  @override
  Future<LocationFix> getCurrentPosition({required Duration timeout}) async {
    positionRequests++;
    return LocationFix(
      latitude: 10.77,
      longitude: 106.69,
      accuracyMeters: 12,
      timestamp: DateTime.utc(2026, 10, 10),
    );
  }
}
