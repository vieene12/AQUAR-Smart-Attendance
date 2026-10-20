import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:nfc_manager/nfc_manager.dart';

import 'dart:typed_data';

import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';
import 'package:smart_attendance/features/attendance/data/attendance_location_gate.dart';
import 'package:smart_attendance/features/attendance/data/location_service.dart';
import 'package:smart_attendance/features/attendance/data/biometric_authenticator.dart';
import 'package:smart_attendance/features/attendance/data/nfc_availability_checker.dart';
import 'package:smart_attendance/features/attendance/data/nfc_tag_reader.dart';
import 'package:smart_attendance/features/attendance/presentation/attendance_screen.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/home/presentation/role_home_screens.dart';

void main() {
  testWidgets('nhân viên mở mục Chấm công từ trang chủ', (tester) async {
    const profile = UserProfile(
      uid: 'employee-1',
      displayName: 'Nhân viên thử nghiệm',
      role: UserRole.employee,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EmployeeHomeScreen(
          profile: profile,
          onSignOut: () {},
          attendanceRepository: _FakeAttendanceRepository(),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Xem giờ hiện tại và chấm công'));
    await tester.tap(find.text('Xem giờ hiện tại và chấm công'));
    await tester.pump();

    expect(find.byType(AttendanceScreen), findsOneWidget);
    expect(find.text('Check-in'), findsOneWidget);
    expect(find.text('Check-out'), findsOneWidget);
  });

  testWidgets('ngày giờ cập nhật mỗi giây', (tester) async {
    var currentTime = DateTime.utc(2026, 10, 10, 2, 8, 7);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AttendanceScreen(
              employeeId: 'employee-1',
              now: () => currentTime,
              repository: _FakeAttendanceRepository(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Thứ Bảy, 10/10/2026'), findsOneWidget);
    expect(find.text('09:08:07'), findsOneWidget);

    currentTime = currentTime.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('09:08:08'), findsOneWidget);
  });

  testWidgets('Check-in thành công hiển thị giờ vào từ repository', (
    tester,
  ) async {
    final auth = _FakeBiometricAuthenticator();
    final repository = _FakeAttendanceRepository();
    await _pumpAttendance(tester, auth, repository);

    expect(find.text('Chưa có dữ liệu'), findsNWidgets(3));
    expect(find.text('Chưa chấm công'), findsNWidgets(2));
    expect(find.text('Đang làm việc'), findsOneWidget);
    expect(find.text('Đã kết thúc'), findsOneWidget);

    await tester.ensureVisible(find.text('Check-in'));
    await tester.tap(find.text('Check-in'));
    await tester.pump();
    await tester.pump();
    expect(auth.calls, 1);
    expect(auth.lastReason, 'Xác thực sinh trắc học để chấm công vào');
    expect(repository.checkInCalls, 1);
    expect(find.text('Chưa có dữ liệu'), findsNWidgets(2));
    expect(find.text('Đang làm việc'), findsNWidgets(2));
    expect(find.text('09:00:00'), findsOneWidget);
    expect(find.text('Check-in thành công.'), findsOneWidget);
  });

  testWidgets('không mở prompt khi thiết bị không hỗ trợ', (tester) async {
    final auth = _FakeBiometricAuthenticator(supported: false);
    await _pumpAttendance(
      tester,
      auth,
      _FakeAttendanceRepository()..record = _workingRecord(),
    );
    await tester.ensureVisible(find.text('Check-out'));
    await tester.tap(find.text('Check-out'));
    await tester.pump();
    await tester.pump();
    expect(auth.calls, 0);
    expect(find.text('Thiết bị không hỗ trợ sinh trắc học.'), findsOneWidget);
  });

  testWidgets('không mở prompt khi chưa đăng ký sinh trắc học', (tester) async {
    final auth = _FakeBiometricAuthenticator(enrolled: false);
    await _pumpAttendance(tester, auth);
    await tester.ensureVisible(find.text('Check-in'));
    await tester.tap(find.text('Check-in'));
    await tester.pump();
    await tester.pump();
    expect(auth.calls, 0);
    expect(
      find.text('Chưa đăng ký sinh trắc học trên thiết bị.'),
      findsOneWidget,
    );
  });

  testWidgets('báo xác thực thất bại', (tester) async {
    final auth = _FakeBiometricAuthenticator(result: false);
    final repository = _FakeAttendanceRepository();
    await _pumpAttendance(tester, auth, repository);
    await tester.ensureVisible(find.text('Check-in'));
    await tester.tap(find.text('Check-in'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Xác thực không thành công. Vui lòng thử lại.'),
      findsOneWidget,
    );
    expect(repository.checkInCalls, 0);
    expect(find.text('Chưa có dữ liệu'), findsNWidgets(3));
  });

  testWidgets('báo hủy xác thực', (tester) async {
    final auth = _FakeBiometricAuthenticator()
      ..error = const LocalAuthException(
        code: LocalAuthExceptionCode.userCanceled,
      );
    await _pumpAttendance(tester, auth);
    await tester.ensureVisible(find.text('Check-in'));
    await tester.tap(find.text('Check-in'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Đã hủy xác thực sinh trắc học.'), findsOneWidget);
    expect(find.text('Chưa có dữ liệu'), findsNWidgets(3));
  });

  testWidgets('khóa cả hai nút trong lúc xác thực', (tester) async {
    final pending = Completer<bool>();
    final auth = _FakeBiometricAuthenticator(pending: pending);
    await _pumpAttendance(tester, auth);
    await tester.ensureVisible(find.text('Check-in'));
    await tester.tap(find.text('Check-in'));
    await tester.pump();
    await tester.pump();
    expect(auth.calls, 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Check-in'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Check-out'),
          )
          .onPressed,
      isNull,
    );
    pending.complete(true);
    await tester.pump();
    await tester.pump();
    expect(find.text('Check-in thành công.'), findsOneWidget);
  });

  testWidgets('Check-out chỉ lưu sau sinh trắc học và hiển thị giờ làm thật', (
    tester,
  ) async {
    final auth = _FakeBiometricAuthenticator();
    final repository = _FakeAttendanceRepository()..record = _workingRecord();
    await _pumpAttendance(tester, auth, repository);
    await tester.ensureVisible(find.text('Check-out'));
    await tester.tap(find.text('Check-out'));
    await tester.pump();
    await tester.pump();
    expect(repository.checkInCalls, 0);
    expect(repository.checkOutCalls, 1);
    expect(auth.lastReason, 'Xác thực sinh trắc học để chấm công ra');
    expect(find.text('Check-out thành công.'), findsOneWidget);
    expect(find.text('17:30:05'), findsOneWidget);
    expect(find.text('8 giờ 30 phút 05 giây'), findsOneWidget);
    expect(find.text('Đã kết thúc'), findsNWidgets(2));
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Check-out'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('chưa Check-in thì không thể Check-out', (tester) async {
    final auth = _FakeBiometricAuthenticator();
    final repository = _FakeAttendanceRepository();
    await _pumpAttendance(tester, auth, repository);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Check-out'),
          )
          .onPressed,
      isNull,
    );
    expect(auth.calls, 0);
    expect(repository.checkOutCalls, 0);
  });

  testWidgets('xác thực Check-out thất bại không ghi dữ liệu', (tester) async {
    final auth = _FakeBiometricAuthenticator(result: false);
    final repository = _FakeAttendanceRepository()..record = _workingRecord();
    await _pumpAttendance(tester, auth, repository);
    await tester.ensureVisible(find.text('Check-out'));
    await tester.tap(find.text('Check-out'));
    await tester.pump();
    await tester.pump();
    expect(repository.checkOutCalls, 0);
    expect(find.text('Đang làm việc'), findsNWidgets(2));
  });

  testWidgets('lỗi mạng Check-out không báo thành công', (tester) async {
    final repository = _FakeAttendanceRepository()
      ..record = _workingRecord()
      ..checkOutError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
    await _pumpAttendance(tester, _FakeBiometricAuthenticator(), repository);
    await tester.ensureVisible(find.text('Check-out'));
    await tester.tap(find.text('Check-out'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Check-out thành công.'), findsNothing);
    expect(find.text('Chưa xác định'), findsNWidgets(2));
    expect(find.text('Tải lại'), findsOneWidget);
  });

  testWidgets('Check-out đã hoàn tất thì khóa nút', (tester) async {
    final auth = _FakeBiometricAuthenticator();
    final repository = _FakeAttendanceRepository()
      ..record = AttendanceRecord(
        employeeId: 'employee-1',
        workDate: '2026-10-10',
        checkInAt: DateTime.utc(2026, 10, 10, 2),
        checkOutAt: DateTime.utc(2026, 10, 10, 10, 30, 5),
      );
    await _pumpAttendance(tester, auth, repository);
    expect(find.text('Đã kết thúc'), findsNWidgets(2));
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Check-out'),
          )
          .onPressed,
      isNull,
    );
    expect(auth.calls, 0);
    expect(repository.checkOutCalls, 0);
  });

  testWidgets('lỗi quyền Check-out không báo thành công', (tester) async {
    final repository = _FakeAttendanceRepository()
      ..record = _workingRecord()
      ..checkOutError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    await _pumpAttendance(tester, _FakeBiometricAuthenticator(), repository);
    await tester.ensureVisible(find.text('Check-out'));
    await tester.tap(find.text('Check-out'));
    await tester.pump();
    await tester.pump();
    expect(repository.checkOutCalls, 1);
    expect(find.text('Check-out thành công.'), findsNothing);
    expect(
      find.text(
        'Không có quyền chấm công. Kiểm tra tài khoản, Rules và ngày giờ thiết bị.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Check-in trùng tải lại bản ghi hiện có', (tester) async {
    final repository = _FakeAttendanceRepository()
      ..checkInError = const AttendanceAlreadyCheckedInException()
      ..record = AttendanceRecord(
        employeeId: 'employee-1',
        workDate: '2026-10-10',
        checkInAt: DateTime.utc(2026, 10, 10, 2),
      );
    // Giả lập bản ghi xuất hiện trên thiết bị khác sau lần tải đầu tiên.
    repository.hideRecordOnFirstLoad = true;
    await _pumpAttendance(tester, _FakeBiometricAuthenticator(), repository);
    await tester.ensureVisible(find.text('Check-in'));
    await tester.tap(find.text('Check-in'));
    await tester.pump();
    await tester.pump();
    expect(repository.checkInCalls, 1);
    expect(find.text('Hôm nay bạn đã check-in.'), findsOneWidget);
    expect(find.text('09:00:00'), findsOneWidget);
  });

  testWidgets('lỗi quyền không báo check-in thành công', (tester) async {
    final repository = _FakeAttendanceRepository()
      ..checkInError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    await _pumpAttendance(tester, _FakeBiometricAuthenticator(), repository);
    await tester.ensureVisible(find.text('Check-in'));
    await tester.tap(find.text('Check-in'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text(
        'Không có quyền chấm công. Kiểm tra tài khoản, Rules và ngày giờ thiết bị.',
      ),
      findsOneWidget,
    );
    expect(find.text('Check-in thành công.'), findsNothing);
  });

  testWidgets('lỗi mạng giữ trạng thái chưa xác định', (tester) async {
    final repository = _FakeAttendanceRepository()
      ..checkInError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
    await _pumpAttendance(tester, _FakeBiometricAuthenticator(), repository);
    await tester.ensureVisible(find.text('Check-in'));
    await tester.tap(find.text('Check-in'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Chưa xác định'), findsNWidgets(2));
    expect(find.text('Check-in thành công.'), findsNothing);
    expect(find.text('Tải lại'), findsOneWidget);
  });

  testWidgets('Check-in thiếu cấu hình chặn trước sinh trắc học', (
    tester,
  ) async {
    final gate = _FakeAttendanceLocationGate()
      ..error = const AttendanceLocationNotConfiguredException();
    final auth = _FakeBiometricAuthenticator();
    final repository = _FakeAttendanceRepository();
    await _pumpAttendance(tester, auth, repository, null, gate);
    await tester.ensureVisible(find.text('Check-in'));
    await tester.tap(find.text('Check-in'));
    await tester.pump();
    await tester.pump();
    expect(gate.calls, 1);
    expect(auth.calls, 0);
    expect(repository.checkInCalls, 0);
    expect(
      find.textContaining('Chưa có cấu hình vị trí chấm công'),
      findsOneWidget,
    );
  });

  testWidgets('Check-out ngoài phạm vi chặn trước sinh trắc học', (
    tester,
  ) async {
    final gate = _FakeAttendanceLocationGate()
      ..error = const AttendanceOutsideAreaException(250, 100);
    final auth = _FakeBiometricAuthenticator();
    final repository = _FakeAttendanceRepository()..record = _workingRecord();
    await _pumpAttendance(tester, auth, repository, null, gate);
    await tester.ensureVisible(find.text('Check-out'));
    await tester.tap(find.text('Check-out'));
    await tester.pump();
    await tester.pump();
    expect(gate.calls, 1);
    expect(auth.calls, 0);
    expect(repository.checkOutCalls, 0);
    expect(find.textContaining('ngoài phạm vi chấm công'), findsOneWidget);
  });

  testWidgets('GPS tắt thì không mở prompt hoặc ghi Check-in', (tester) async {
    final gate = _FakeAttendanceLocationGate()
      ..error = const LocationServiceException(LocationFailure.gpsDisabled);
    final auth = _FakeBiometricAuthenticator();
    final repository = _FakeAttendanceRepository();
    await _pumpAttendance(tester, auth, repository, null, gate);
    await tester.ensureVisible(find.text('Check-in'));
    await tester.tap(find.text('Check-in'));
    await tester.pump();
    await tester.pump();
    expect(auth.calls, 0);
    expect(repository.checkInCalls, 0);
    expect(find.textContaining('GPS đang tắt'), findsOneWidget);
  });

  testWidgets('khóa thao tác trong lúc kiểm tra vị trí', (tester) async {
    final pending = Completer<void>();
    final gate = _FakeAttendanceLocationGate()..pending = pending;
    final auth = _FakeBiometricAuthenticator();
    await _pumpAttendance(
      tester,
      auth,
      _FakeAttendanceRepository(),
      null,
      gate,
    );
    await tester.ensureVisible(find.text('Check-in'));
    await tester.tap(find.text('Check-in'));
    await tester.pump();
    expect(gate.calls, 1);
    expect(auth.calls, 0);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Check-in'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Check-out'),
          )
          .onPressed,
      isNull,
    );
    pending.complete();
    await tester.pump();
    await tester.pump();
    expect(auth.calls, 1);
  });

  testWidgets('không hỗ trợ NFC thì vô hiệu hóa lựa chọn', (tester) async {
    await _pumpAttendance(
      tester,
      _FakeBiometricAuthenticator(),
      _FakeAttendanceRepository(),
      _FakeNfcChecker(NfcAvailability.unsupported),
    );
    expect(find.text('Thiết bị không hỗ trợ NFC.'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Thẻ NFC'))
          .onSelected,
      isNull,
    );
  });

  testWidgets('NFC đang tắt thì hướng dẫn bật trong Cài đặt', (tester) async {
    final auth = _FakeBiometricAuthenticator();
    final repository = _FakeAttendanceRepository();
    await _pumpAttendance(
      tester,
      auth,
      repository,
      _FakeNfcChecker(NfcAvailability.disabled),
    );
    expect(find.text('NFC có sẵn nhưng đang tắt.'), findsOneWidget);
    expect(find.textContaining('Mở Cài đặt Android'), findsOneWidget);
    await tester.ensureVisible(find.text('Thẻ NFC'));
    await tester.tap(find.text('Thẻ NFC'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Check-in'))
          .onPressed,
      isNull,
    );
    expect(repository.checkInCalls, 0);
    expect(auth.calls, 0);
  });

  testWidgets('NFC đang bật vẫn chưa chấm công bằng thẻ', (tester) async {
    final auth = _FakeBiometricAuthenticator();
    final repository = _FakeAttendanceRepository();
    await _pumpAttendance(
      tester,
      auth,
      repository,
      _FakeNfcChecker(NfcAvailability.enabled),
    );
    await tester.ensureVisible(find.text('Thẻ NFC'));
    await tester.tap(find.text('Thẻ NFC'));
    await tester.pump();
    expect(find.text('NFC đang bật trên thiết bị.'), findsOneWidget);
    expect(
      find.textContaining('Chưa liên kết thẻ hoặc chấm công bằng NFC.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Check-in'))
          .onPressed,
      isNull,
    );
    expect(repository.checkInCalls, 0);
    expect(auth.calls, 0);
  });

  testWidgets('kiểm tra lại NFC sau khi bật trong Cài đặt', (tester) async {
    final checker = _FakeNfcChecker(NfcAvailability.disabled);
    await _pumpAttendance(
      tester,
      _FakeBiometricAuthenticator(),
      _FakeAttendanceRepository(),
      checker,
    );
    expect(find.text('NFC có sẵn nhưng đang tắt.'), findsOneWidget);
    checker.availability = NfcAvailability.enabled;
    await tester.ensureVisible(find.text('Kiểm tra lại NFC'));
    await tester.tap(find.text('Kiểm tra lại NFC'));
    await tester.pump();
    await tester.pump();
    expect(find.text('NFC đang bật trên thiết bị.'), findsOneWidget);
  });

  testWidgets(
    'bản ghi NFC tại quầy hiện trạng thái và hướng dẫn Check-out tại quầy',
    (tester) async {
      final repository = _FakeAttendanceRepository()
        ..record = AttendanceRecord(
          employeeId: 'employee-1',
          workDate: '2026-10-10',
          checkInAt: DateTime.utc(2026, 10, 10, 2),
          method: 'nfc',
        );
      await _pumpAttendance(tester, _FakeBiometricAuthenticator(), repository);
      expect(find.text('Đang làm việc'), findsNWidgets(2));
      expect(find.textContaining('cần Check-out tại quầy'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Check-out'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'bản ghi manual không cho nhân viên Check-out bằng sinh trắc học',
    (tester) async {
      final repository = _FakeAttendanceRepository()
        ..record = AttendanceRecord(
          employeeId: 'employee-1',
          workDate: '2026-10-10',
          checkInAt: DateTime.utc(2026, 10, 10, 2),
          method: 'manual',
        );
      await _pumpAttendance(tester, _FakeBiometricAuthenticator(), repository);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Check-out'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('cần Manager/Admin bổ sung giờ ra'),
        findsOneWidget,
      );
    },
  );

  testWidgets('quét UID hex, dừng phiên và cho phép quét lại', (tester) async {
    final reader = _FakeNfcTagReader();
    final repository = _FakeAttendanceRepository();
    await _pumpAttendance(
      tester,
      _FakeBiometricAuthenticator(),
      repository,
      _FakeNfcChecker(NfcAvailability.enabled),
      null,
      reader,
    );
    await tester.ensureVisible(find.text('Thẻ NFC'));
    await tester.tap(find.text('Thẻ NFC'));
    await tester.pump();
    await tester.tap(find.text('Quét thẻ NFC'));
    await tester.pump();
    expect(find.textContaining('Đưa thẻ đến mặt lưng'), findsOneWidget);
    reader.discover(Uint8List.fromList([0x04, 0x0a, 0xff]));
    await tester.pump();
    await tester.pump();
    expect(find.text('UID (hex): 040AFF'), findsOneWidget);
    expect(reader.stopCalls, 1);
    expect(repository.checkInCalls, 0);
    expect(repository.checkOutCalls, 0);
    await tester.tap(find.text('Quét thẻ NFC'));
    await tester.pump();
    reader.discover(null);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('không cung cấp UID'), findsOneWidget);
    expect(find.text('UID (hex): 040AFF'), findsNothing);
    expect(reader.stopCalls, 2);
  });

  testWidgets('hủy quét đóng phiên và bỏ qua thẻ đến muộn', (tester) async {
    final reader = _FakeNfcTagReader();
    await _pumpAttendance(
      tester,
      _FakeBiometricAuthenticator(),
      null,
      _FakeNfcChecker(NfcAvailability.enabled),
      null,
      reader,
    );
    await tester.ensureVisible(find.text('Thẻ NFC'));
    await tester.tap(find.text('Thẻ NFC'));
    await tester.pump();
    await tester.tap(find.text('Quét thẻ NFC'));
    await tester.pump();
    final oldCallback = reader.onTag!;
    await tester.tap(find.text('Hủy'));
    await tester.pump();
    oldCallback(Uint8List.fromList([1]));
    await tester.pump();
    expect(find.text('Đã hủy quét NFC.'), findsOneWidget);
    expect(find.text('UID (hex): 01'), findsNothing);
    expect(reader.stopCalls, 1);
  });

  testWidgets('lỗi mở phiên NFC được báo và có thể thử lại', (tester) async {
    final reader = _FakeNfcTagReader()
      ..startError = StateError('reader failed');
    await _pumpAttendance(
      tester,
      _FakeBiometricAuthenticator(),
      null,
      _FakeNfcChecker(NfcAvailability.enabled),
      null,
      reader,
    );
    await tester.ensureVisible(find.text('Thẻ NFC'));
    await tester.tap(find.text('Thẻ NFC'));
    await tester.pump();
    await tester.tap(find.text('Quét thẻ NFC'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Không thể'), findsWidgets);
    reader.startError = null;
    await tester.tap(find.text('Quét thẻ NFC'));
    await tester.pump();
    expect(find.textContaining('Đưa thẻ đến mặt lưng'), findsOneWidget);
  });

  test('UID được mã hóa hex đủ hai ký tự mỗi byte', () {
    expect(nfcUidHex(Uint8List.fromList([0, 1, 254])), '0001FE');
    expect(nfcUidHex(null), isNull);
    expect(nfcUidHex(Uint8List(0)), isNull);
  });

  test('ngày làm việc theo Asia/Ho_Chi_Minh tại ranh giới UTC', () {
    expect(vietnamWorkDate(DateTime.utc(2026, 10, 10, 16, 59)), '2026-10-10');
    expect(vietnamWorkDate(DateTime.utc(2026, 10, 10, 17)), '2026-10-11');
    expect(
      attendanceDocumentId('employee-1', '2026-10-11'),
      'employee-1_2026-10-11',
    );
  });

  test('local_auth luôn yêu cầu biometricOnly', () async {
    final spy = _SpyLocalAuthentication();
    final auth = LocalBiometricAuthenticator(localAuth: spy);
    expect(await auth.canCheckBiometrics(), isTrue);
    expect(await auth.hasEnrolledBiometrics(), isTrue);
    expect(await auth.authenticate(reason: 'Kiểm tra'), isTrue);
    expect(spy.biometricOnly, isTrue);
  });
}

Future<void> _pumpAttendance(
  WidgetTester tester,
  BiometricAuthenticator authenticator, [
  AttendanceRepository? repository,
  NfcAvailabilityChecker? nfcChecker,
  AttendanceLocationGate? locationGate,
  NfcTagReader? nfcReader,
]) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AttendanceScreen(
            employeeId: 'employee-1',
            authenticator: authenticator,
            repository: repository ?? _FakeAttendanceRepository(),
            locationGate: locationGate ?? _FakeAttendanceLocationGate(),
            nfcChecker: nfcChecker ?? _FakeNfcChecker(NfcAvailability.enabled),
            nfcReader: nfcReader ?? _FakeNfcTagReader(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _FakeNfcTagReader implements NfcTagReader {
  void Function(Uint8List? uid)? onTag;
  int stopCalls = 0;
  Object? startError;

  @override
  Future<void> start({required void Function(Uint8List? uid) onTag}) async {
    if (startError != null) throw startError!;
    this.onTag = onTag;
  }

  void discover(Uint8List? uid) => onTag!(uid);

  @override
  Future<void> stop() async {
    stopCalls++;
    onTag = null;
  }
}

class _FakeAttendanceLocationGate implements AttendanceLocationGate {
  Object? error;
  Completer<void>? pending;
  int calls = 0;

  @override
  Future<void> verify() async {
    calls++;
    if (error != null) throw error!;
    if (pending != null) await pending!.future;
  }
}

class _FakeNfcChecker implements NfcAvailabilityChecker {
  _FakeNfcChecker(this.availability);

  NfcAvailability availability;

  @override
  Future<NfcAvailability> checkAvailability() async => availability;
}

class _FakeAttendanceRepository implements AttendanceRepository {
  AttendanceRecord? record;
  Object? checkInError;
  Object? checkOutError;
  bool hideRecordOnFirstLoad = false;
  int checkInCalls = 0;
  int checkOutCalls = 0;
  int loadCalls = 0;

  @override
  Future<AttendanceRecord?> loadToday(String employeeId) async {
    loadCalls++;
    if (hideRecordOnFirstLoad && loadCalls == 1) return null;
    return record;
  }

  @override
  Future<AttendanceRecord> checkIn(String employeeId) async {
    checkInCalls++;
    if (checkInError != null) throw checkInError!;
    return record = AttendanceRecord(
      employeeId: employeeId,
      workDate: '2026-10-10',
      checkInAt: DateTime.utc(2026, 10, 10, 2),
    );
  }

  @override
  Future<AttendanceRecord> checkOut(String employeeId) async {
    checkOutCalls++;
    if (checkOutError != null) {
      throw checkOutError!;
    }
    final existing = record;
    if (existing == null) {
      throw const AttendanceNotCheckedInException();
    }
    if (existing.checkOutAt != null) {
      throw const AttendanceAlreadyCheckedOutException();
    }
    return record = AttendanceRecord(
      employeeId: existing.employeeId,
      workDate: existing.workDate,
      checkInAt: existing.checkInAt,
      checkOutAt: DateTime.utc(2026, 10, 10, 10, 30, 5),
    );
  }

  @override
  Future<List<AttendanceRecord>> loadHistory(
    String employeeId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async => record == null ? [] : [record!];
}

AttendanceRecord _workingRecord() => AttendanceRecord(
  employeeId: 'employee-1',
  workDate: '2026-10-10',
  checkInAt: DateTime.utc(2026, 10, 10, 2),
);

class _FakeBiometricAuthenticator implements BiometricAuthenticator {
  _FakeBiometricAuthenticator({
    this.supported = true,
    this.enrolled = true,
    this.result = true,
    this.pending,
  });

  final bool supported;
  final bool enrolled;
  final bool result;
  final Completer<bool>? pending;
  Object? error;
  int calls = 0;
  String? lastReason;

  @override
  Future<bool> canCheckBiometrics() async => supported;

  @override
  Future<bool> hasEnrolledBiometrics() async => enrolled;

  @override
  Future<bool> authenticate({required String reason}) {
    calls++;
    lastReason = reason;
    if (error != null) return Future.error(error!);
    return pending?.future ?? Future.value(result);
  }
}

class _SpyLocalAuthentication implements LocalAuthentication {
  bool? biometricOnly;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #canCheckBiometrics) {
      return Future.value(true);
    }
    if (invocation.memberName == #getAvailableBiometrics) {
      return Future.value([BiometricType.strong]);
    }
    if (invocation.memberName == #authenticate) {
      biometricOnly = invocation.namedArguments[#biometricOnly] as bool?;
      return Future.value(true);
    }
    return super.noSuchMethod(invocation);
  }
}
