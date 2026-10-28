import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';
import 'package:smart_attendance/features/attendance/data/manager_attendance_history_repository.dart';
import 'package:smart_attendance/features/attendance/presentation/manager_attendance_history_screen.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/home/presentation/role_home_screens.dart';

const manager = UserProfile(
  uid: 'manager-1',
  displayName: 'Quản lý',
  role: UserRole.manager,
);

void main() {
  testWidgets('Manager mở Lịch sử từ trang chủ thay vì placeholder', (
    tester,
  ) async {
    final repository = _FakeManagerHistoryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ManagerHomeScreen(
          profile: manager,
          onSignOut: () {},
          managerAttendanceHistoryRepository: repository,
        ),
      ),
    );

    await tester.ensureVisible(
      find.text('Xem lịch sử chấm công theo nhân viên'),
    );
    await tester.tap(find.text('Xem lịch sử chấm công theo nhân viên'));
    await tester.pumpAndSettle();

    expect(find.byType(ManagerAttendanceHistoryScreen), findsOneWidget);
    expect(find.text('Đang phát triển'), findsNothing);
    expect(repository.accessCalls, 1);
    expect(repository.employeeCalls, 1);
  });

  testWidgets('chọn Employee tải và hiển thị lịch sử', (tester) async {
    final repository = _FakeManagerHistoryRepository()
      ..records = [
        AttendanceRecord(
          employeeId: 'employee-1',
          workDate: '2026-10-29',
          checkInAt: DateTime.utc(2026, 10, 29, 1),
          checkOutAt: DateTime.utc(2026, 10, 29, 10),
          method: 'nfc_mobile',
        ),
      ];
    await _pumpScreen(tester, repository);

    await tester.tap(find.text('Chọn nhân viên'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhân viên thử nghiệm').last);
    await tester.pump();
    await tester.pump();

    expect(repository.lastEmployeeUid, 'employee-1');
    expect(find.text('Ngày làm: 29/10/2026'), findsOneWidget);
    expect(find.text('Đã hoàn thành ca'), findsOneWidget);
  });

  testWidgets('từ chối role khác và hỗ trợ thử lại lỗi tải danh sách', (
    tester,
  ) async {
    final denied = _FakeManagerHistoryRepository()..allowed = false;
    await _pumpScreen(tester, denied);
    expect(
      find.text('Bạn không có quyền xem lịch sử nhân viên.'),
      findsOneWidget,
    );
    expect(denied.employeeCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    final failed = _FakeManagerHistoryRepository()
      ..failure = StateError('offline');
    await _pumpScreen(tester, failed);
    expect(find.textContaining('Không thể tải danh sách'), findsOneWidget);
    failed.failure = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn nhân viên'), findsOneWidget);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeManagerHistoryRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ManagerAttendanceHistoryScreen(
        profile: manager,
        repository: repository,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeManagerHistoryRepository
    implements ManagerAttendanceHistoryRepository {
  bool allowed = true;
  Object? failure;
  int accessCalls = 0;
  int employeeCalls = 0;
  String? lastEmployeeUid;
  List<AttendanceRecord> records = const [];

  @override
  Future<bool> canAccess(UserProfile profile) async {
    accessCalls++;
    if (failure != null) throw failure!;
    return allowed;
  }

  @override
  Future<List<ManagerHistoryEmployee>> loadEmployees() async {
    employeeCalls++;
    if (failure != null) throw failure!;
    return const [
      ManagerHistoryEmployee(uid: 'employee-1', name: 'Nhân viên thử nghiệm'),
    ];
  }

  @override
  Future<List<AttendanceRecord>> loadHistory(
    String employeeUid, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    lastEmployeeUid = employeeUid;
    if (failure != null) throw failure!;
    return records;
  }
}
