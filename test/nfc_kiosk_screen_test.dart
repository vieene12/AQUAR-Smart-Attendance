import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:smart_attendance/features/attendance/data/nfc_availability_checker.dart';
import 'package:smart_attendance/features/attendance/data/nfc_tag_reader.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/home/presentation/role_home_screens.dart';
import 'package:smart_attendance/features/kiosk/data/nfc_kiosk_repository.dart';
import 'package:smart_attendance/features/kiosk/data/kiosk_attendance_repository.dart';
import 'package:smart_attendance/features/kiosk/presentation/nfc_kiosk_screen.dart';

const _manager = UserProfile(
  uid: 'manager-1',
  displayName: 'Quản lý',
  role: UserRole.manager,
);
final _now = DateTime.utc(2026, 10, 11, 3);

void main() {
  test('tra cứu thẻ active và trạng thái chấm công hôm nay', () async {
    final source = _FakeKioskSource();
    final repository = NfcKioskRepository(source);
    final noRecord = await repository.lookup(' 04ab01 ', _now);
    expect(noRecord.cardStatus, KioskCardStatus.active);
    expect(noRecord.employeeName, 'Nguyễn Văn A');
    expect(noRecord.attendanceStatus, KioskAttendanceStatus.notCheckedIn);
    expect(source.lastAttendanceId, 'employee-1_2026-10-11');

    source.attendanceData = _attendance('working');
    expect(
      (await repository.lookup('04AB01', _now)).attendanceStatus,
      KioskAttendanceStatus.working,
    );
    source.attendanceData = _attendance('completed');
    expect(
      (await repository.lookup('04AB01', _now)).attendanceStatus,
      KioskAttendanceStatus.completed,
    );
  });

  test('thẻ thiếu hoặc đã thu hồi không tra cứu tài khoản/chấm công', () async {
    final source = _FakeKioskSource()..cardData = null;
    final repository = NfcKioskRepository(source);
    final missing = await repository.lookup('04AB01', _now);
    expect(missing.cardStatus, KioskCardStatus.unregisteredOrRevoked);
    expect(source.employeeReads, 0);
    expect(source.attendanceReads, 0);

    source.cardData = {'employeeUid': 'employee-1', 'status': 'revoked'};
    final markedRevoked = await repository.lookup('04AB01', _now);
    expect(markedRevoked.cardStatus, KioskCardStatus.unregisteredOrRevoked);

    source.cardData = {'employeeUid': 'employee-1'};
    source.linkData = null;
    final revoked = await repository.lookup('04AB01', _now);
    expect(revoked.cardStatus, KioskCardStatus.unregisteredOrRevoked);
    expect(source.employeeReads, 0);
  });

  test('tài khoản bị khóa không đọc bản ghi chấm công', () async {
    final source = _FakeKioskSource()
      ..employeeData = {
        'fullName': 'Nguyễn Văn A',
        'role': 'employee',
        'status': 'locked',
      };
    final result = await NfcKioskRepository(source).lookup('04AB01', _now);
    expect(result.cardStatus, KioskCardStatus.employeeInactive);
    expect(result.employeeName, 'Nguyễn Văn A');
    expect(source.attendanceReads, 0);
  });

  testWidgets('Manager quét, thấy nhân viên và nút Check-out phù hợp', (
    tester,
  ) async {
    final reader = _FakeNfcReader();
    final source = _FakeKioskSource()..attendanceData = _attendance('working');
    await _pumpScreen(tester, source, reader);
    await tester.tap(find.text('Quét thẻ NFC'));
    await tester.pump();
    expect(find.textContaining('Đưa thẻ đến mặt lưng'), findsOneWidget);
    reader.discover([0x04, 0xAB, 0x01]);
    await tester.pumpAndSettle();
    expect(reader.stops, 1);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('Thẻ đang hoạt động.'), findsOneWidget);
    expect(find.text('Hôm nay: Đang làm việc.'), findsOneWidget);
    expect(find.text('Check-in'), findsNothing);
    expect(find.text('Check-out'), findsOneWidget);
  });

  testWidgets('thiết bị không có NFC vẫn mở màn hình nhưng nút quét bị khóa', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      _FakeKioskSource(),
      _FakeNfcReader(),
      NfcAvailability.unsupported,
    );
    expect(find.textContaining('Thiết bị không hỗ trợ NFC'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Quét thẻ NFC'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('thẻ chưa đăng ký hoặc đã thu hồi hiện thông báo', (
    tester,
  ) async {
    final reader = _FakeNfcReader();
    final source = _FakeKioskSource()..cardData = null;
    await _pumpScreen(tester, source, reader);
    await tester.tap(find.text('Quét thẻ NFC'));
    await tester.pump();
    reader.discover([0x04, 0xAB, 0x01]);
    await tester.pumpAndSettle();
    expect(find.text('Thẻ chưa đăng ký hoặc đã thu hồi.'), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsNothing);
  });

  testWidgets('Check-in và Check-out cập nhật nút, chặn nhấn liên tục', (
    tester,
  ) async {
    final source = _FakeKioskSource();
    final reader = _FakeNfcReader();
    final pending = Completer<void>();
    final writer = _FakeKioskWriter()
      ..onCheckIn = () async {
        await pending.future;
        source.attendanceData = _attendance('working');
      }
      ..onCheckOut = () async {
        source.attendanceData = _attendance('completed');
      };
    await _pumpScreen(tester, source, reader, NfcAvailability.enabled, writer);
    await tester.tap(find.text('Quét thẻ NFC'));
    await tester.pump();
    reader.discover([0x04, 0xAB, 0x01]);
    await tester.pumpAndSettle();
    expect(find.text('Check-in'), findsOneWidget);
    await tester.tap(find.text('Check-in'));
    await tester.pump();
    expect(writer.checkInCalls, 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Check-in'))
          .onPressed,
      isNull,
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Check-out'), findsOneWidget);
    await tester.tap(find.text('Check-out'));
    await tester.pumpAndSettle();
    expect(writer.checkOutCalls, 1);
    expect(find.text('Hôm nay: Đã kết thúc.'), findsOneWidget);
    expect(find.text('Check-out'), findsNothing);
  });

  testWidgets('lỗi quyền khi ghi được báo, không hiển thị thành công', (
    tester,
  ) async {
    final source = _FakeKioskSource();
    final reader = _FakeNfcReader();
    final writer = _FakeKioskWriter()
      ..onCheckIn = () async {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        );
      };
    await _pumpScreen(tester, source, reader, NfcAvailability.enabled, writer);
    await tester.tap(find.text('Quét thẻ NFC'));
    await tester.pump();
    reader.discover([0x04, 0xAB, 0x01]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check-in'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Không có quyền thao tác tại quầy'),
      findsOneWidget,
    );
    expect(find.textContaining('Đã ghi Check-in'), findsNothing);
  });

  testWidgets('Employee không được dùng màn hình quầy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NfcKioskScreen(
          profile: UserProfile(
            uid: 'employee',
            displayName: 'Nhân viên',
            role: UserRole.employee,
          ),
        ),
      ),
    );
    expect(
      find.text('Bạn không có quyền dùng quầy chấm công NFC.'),
      findsOneWidget,
    );
  });

  testWidgets('Manager mở mục NFC tại quầy từ trang chủ', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ManagerHomeScreen(
          profile: _manager,
          onSignOut: () {},
          kioskRepository: NfcKioskRepository(_FakeKioskSource()),
          nfcChecker: _FakeNfcChecker(NfcAvailability.enabled),
          nfcReader: _FakeNfcReader(),
        ),
      ),
    );
    await tester.ensureVisible(
      find.text('Quét thẻ và xem trạng thái chấm công hôm nay'),
    );
    await tester.tap(find.text('Quét thẻ và xem trạng thái chấm công hôm nay'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(NfcKioskScreen), findsOneWidget);
  });

  testWidgets('Admin mở mục NFC tại quầy từ trang chủ', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminHomeScreen(
          profile: const UserProfile(
            uid: 'admin-1',
            displayName: 'Admin',
            role: UserRole.admin,
          ),
          onSignOut: () {},
          kioskRepository: NfcKioskRepository(_FakeKioskSource()),
          nfcChecker: _FakeNfcChecker(NfcAvailability.enabled),
          nfcReader: _FakeNfcReader(),
        ),
      ),
    );
    await tester.ensureVisible(
      find.text('Quét thẻ và xem trạng thái chấm công hôm nay'),
    );
    await tester.tap(find.text('Quét thẻ và xem trạng thái chấm công hôm nay'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(NfcKioskScreen), findsOneWidget);
  });
}

Map<String, dynamic> _attendance(String status) => {
  'employeeId': 'employee-1',
  'workDate': '2026-10-11',
  'checkInAt': Timestamp.fromDate(DateTime.utc(2026, 10, 11, 2)),
  'status': status,
  if (status == 'completed')
    'checkOutAt': Timestamp.fromDate(DateTime.utc(2026, 10, 11, 10)),
};

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeKioskSource source,
  _FakeNfcReader reader, [
  NfcAvailability availability = NfcAvailability.enabled,
  KioskAttendanceWriter? writer,
]) async {
  await tester.pumpWidget(
    MaterialApp(
      home: NfcKioskScreen(
        profile: _manager,
        repository: NfcKioskRepository(source),
        checker: _FakeNfcChecker(availability),
        reader: reader,
        writer: writer ?? _FakeKioskWriter(),
        now: () => _now,
      ),
    ),
  );
  await tester.pump();
}

class _FakeKioskWriter implements KioskAttendanceWriter {
  Future<void> Function()? onCheckIn;
  Future<void> Function()? onCheckOut;
  int checkInCalls = 0;
  int checkOutCalls = 0;

  @override
  Future<void> checkIn(String cardUid, DateTime now) async {
    checkInCalls++;
    if (onCheckIn != null) await onCheckIn!();
  }

  @override
  Future<void> checkOut(String cardUid, DateTime now) async {
    checkOutCalls++;
    if (onCheckOut != null) await onCheckOut!();
  }
}

class _FakeKioskSource implements KioskDataSource {
  Map<String, dynamic>? cardData = {'employeeUid': 'employee-1'};
  Map<String, dynamic>? linkData = {'cardUid': '04AB01'};
  Map<String, dynamic>? employeeData = {
    'fullName': 'Nguyễn Văn A',
    'role': 'employee',
    'status': 'active',
  };
  Map<String, dynamic>? attendanceData;
  String? lastAttendanceId;
  int employeeReads = 0;
  int attendanceReads = 0;

  @override
  Future<Map<String, dynamic>?> card(String cardUid) async {
    expectSync(cardUid, '04AB01');
    return cardData;
  }

  @override
  Future<Map<String, dynamic>?> employeeCard(String employeeUid) async {
    expectSync(employeeUid, 'employee-1');
    return linkData;
  }

  @override
  Future<Map<String, dynamic>?> employee(String employeeUid) async {
    employeeReads++;
    return employeeData;
  }

  @override
  Future<Map<String, dynamic>?> attendance(String documentId) async {
    attendanceReads++;
    lastAttendanceId = documentId;
    return attendanceData;
  }
}

class _FakeNfcChecker implements NfcAvailabilityChecker {
  _FakeNfcChecker(this.availability);
  final NfcAvailability availability;
  @override
  Future<NfcAvailability> checkAvailability() async => availability;
}

class _FakeNfcReader implements NfcTagReader {
  void Function(Uint8List? uid)? onTag;
  int stops = 0;

  @override
  Future<void> start({required void Function(Uint8List? uid) onTag}) async {
    this.onTag = onTag;
  }

  void discover(List<int> uid) => onTag!(Uint8List.fromList(uid));

  @override
  Future<void> stop() async {
    stops++;
    onTag = null;
  }
}
