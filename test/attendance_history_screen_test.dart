import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';
import 'package:smart_attendance/features/attendance/presentation/attendance_history_screen.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/home/presentation/role_home_screens.dart';

void main() {
  testWidgets('mở lịch sử từ trang chủ Employee', (tester) async {
    final repository = _FakeHistoryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: EmployeeHomeScreen(
          profile: const UserProfile(
            uid: 'employee-1',
            displayName: 'Nhân viên',
            role: UserRole.employee,
          ),
          onSignOut: () {},
          attendanceRepository: repository,
        ),
      ),
    );
    await tester.ensureVisible(find.text('Xem các lần chấm công đã ghi nhận'));
    await tester.tap(find.text('Xem các lần chấm công đã ghi nhận'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(AttendanceHistoryScreen), findsOneWidget);
    expect(repository.calls, 1);
    expect(repository.lastEmployeeId, 'employee-1');
  });

  testWidgets('hiển thị bản ghi hoàn tất và đang làm việc', (tester) async {
    final repository = _FakeHistoryRepository()
      ..records = [
        AttendanceRecord(
          employeeId: 'employee-1',
          workDate: '2026-10-10',
          checkInAt: DateTime.utc(2026, 10, 10, 2),
        ),
        AttendanceRecord(
          employeeId: 'employee-1',
          workDate: '2026-10-09',
          checkInAt: DateTime.utc(2026, 10, 9, 2),
          checkOutAt: DateTime.utc(2026, 10, 9, 10, 30),
        ),
      ];
    await _pumpHistory(tester, repository);
    expect(find.text('Ngày làm: 10/10/2026'), findsOneWidget);
    expect(find.text('Ngày làm: 09/10/2026'), findsOneWidget);
    expect(find.text('Đang làm việc'), findsOneWidget);
    expect(find.text('Đã kết thúc'), findsOneWidget);
    expect(find.text('Check-out: Chưa có'), findsOneWidget);
    expect(find.text('Tổng giờ làm: Chưa có'), findsOneWidget);
    expect(find.text('Tổng giờ làm: 8 giờ 30 phút 00 giây'), findsOneWidget);
  });

  testWidgets('hiển thị loading rồi danh sách trống', (tester) async {
    final pending = Completer<List<AttendanceRecord>>();
    final repository = _FakeHistoryRepository()..pending = pending;
    await _pumpHistory(tester, repository, finishLoad: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete([]);
    await tester.pump();
    expect(
      find.text('Không có bản ghi chấm công trong thời gian đã chọn.'),
      findsOneWidget,
    );
  });

  testWidgets('lỗi quyền có thể thử lại', (tester) async {
    final repository = _FakeHistoryRepository()
      ..error = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    await _pumpHistory(tester, repository);
    expect(find.text('Không có quyền xem lịch sử chấm công.'), findsOneWidget);
    repository.error = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pump();
    expect(repository.calls, 2);
    expect(
      find.text('Không có bản ghi chấm công trong thời gian đã chọn.'),
      findsOneWidget,
    );
  });

  testWidgets('lọc theo tháng truyền đủ ngày đầu và cuối tháng', (
    tester,
  ) async {
    final repository = _FakeHistoryRepository();
    await _pumpHistory(tester, repository);
    await tester.tap(find.text('Theo tháng'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump();
    final today = DateTime.now();
    expect(repository.lastStartDate, DateTime(today.year, today.month));
    expect(repository.lastEndDate, DateTime(today.year, today.month + 1, 0));
  });

  test('ngày lọc dùng ngày lịch, không phụ thuộc múi giờ thiết bị', () {
    expect(workDateFromCalendarDate(DateTime(2026, 10, 9)), '2026-10-09');
  });
}

Future<void> _pumpHistory(
  WidgetTester tester,
  _FakeHistoryRepository repository, {
  bool finishLoad = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AttendanceHistoryScreen(
            employeeId: 'employee-1',
            repository: repository,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  if (finishLoad) await tester.pump();
}

class _FakeHistoryRepository implements AttendanceRepository {
  List<AttendanceRecord> records = [];
  Completer<List<AttendanceRecord>>? pending;
  Object? error;
  int calls = 0;
  String? lastEmployeeId;
  DateTime? lastStartDate;
  DateTime? lastEndDate;

  @override
  Future<List<AttendanceRecord>> loadHistory(
    String employeeId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    calls++;
    lastEmployeeId = employeeId;
    lastStartDate = startDate;
    lastEndDate = endDate;
    if (error != null) throw error!;
    return pending?.future ?? records;
  }

  @override
  Future<AttendanceRecord?> loadToday(String employeeId) async => null;

  @override
  Future<AttendanceRecord> checkIn(
    String employeeId, {
    String method = 'biometric',
    String? cardUid,
  }) async => throw UnimplementedError();

  @override
  Future<AttendanceRecord> checkOut(
    String employeeId, {
    String? cardUid,
  }) async => throw UnimplementedError();
}
