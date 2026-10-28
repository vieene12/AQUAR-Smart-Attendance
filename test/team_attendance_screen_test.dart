import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';
import 'package:smart_attendance/features/attendance/data/team_attendance_repository.dart';
import 'package:smart_attendance/features/attendance/presentation/team_attendance_history_screen.dart';
import 'package:smart_attendance/features/attendance/presentation/team_on_shift_screen.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';

const manager = UserProfile(
  uid: 'manager',
  displayName: 'Quản lý',
  role: UserRole.manager,
);
const employee = TeamEmployee(
  uid: 'employee',
  name: 'Nguyễn Văn A',
  code: 'NV01',
  position: 'Kỹ thuật viên',
  shiftStart: '08:00',
  shiftEnd: '17:00',
);

class FakeTeamRepository implements TeamAttendanceRepository {
  List<TeamAttendanceEntry> entries = [];
  bool? workingTodayOnly;
  DateTime? startDate;
  DateTime? endDate;

  @override
  Future<List<TeamAttendanceEntry>> load(
    UserProfile profile, {
    DateTime? startDate,
    DateTime? endDate,
    bool workingTodayOnly = false,
  }) async {
    this.workingTodayOnly = workingTodayOnly;
    this.startDate = startDate;
    this.endDate = endDate;
    return entries;
  }
}

void main() {
  test('hồ sơ cũ chưa phân công vẫn hiện, hồ sơ thuộc quản lý khác bị ẩn', () {
    expect(canManagerViewEmployee(manager, null), isTrue);
    expect(canManagerViewEmployee(manager, ''), isTrue);
    expect(canManagerViewEmployee(manager, 'manager'), isTrue);
    expect(canManagerViewEmployee(manager, 'manager-khac'), isFalse);
  });

  test('đi trễ được tính theo giờ ca tại Việt Nam', () {
    final onTime = TeamAttendanceEntry(
      employee: employee,
      record: AttendanceRecord(
        employeeId: 'employee',
        workDate: '2026-10-26',
        checkInAt: DateTime.utc(2026, 10, 26, 1),
      ),
    );
    final late = TeamAttendanceEntry(
      employee: employee,
      record: AttendanceRecord(
        employeeId: 'employee',
        workDate: '2026-10-26',
        checkInAt: DateTime.utc(2026, 10, 26, 1, 5),
      ),
    );
    expect(onTime.isLate, isFalse);
    expect(late.isLate, isTrue);
  });

  testWidgets('nhân viên phụ trách hiển thị thông tin ca, không có avatar', (
    tester,
  ) async {
    final repository = FakeTeamRepository()
      ..entries = [
        TeamAttendanceEntry(
          employee: employee,
          record: AttendanceRecord(
            employeeId: 'employee',
            workDate: '2026-10-26',
            checkInAt: DateTime.utc(2026, 10, 26, 1, 5),
          ),
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeamOnShiftScreen(profile: manager, repository: repository),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(repository.workingTodayOnly, isTrue);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('Mã nhân viên: NV01'), findsOneWidget);
    expect(find.text('Chức vụ: Kỹ thuật viên'), findsOneWidget);
    expect(find.text('Ca làm việc: 08:00 - 17:00'), findsOneWidget);
    expect(find.text('Đi trễ'), findsOneWidget);
    expect(find.byType(CircleAvatar), findsNothing);
  });

  testWidgets(
    'lịch sử hiển thị giờ ra, thời lượng và trạng thái đúng trong chế độ tối',
    (tester) async {
      final repository = FakeTeamRepository()
        ..entries = [
          TeamAttendanceEntry(
            employee: employee,
            record: AttendanceRecord(
              employeeId: 'employee',
              workDate: '2026-10-26',
              checkInAt: DateTime.utc(2026, 10, 26, 1),
            ),
          ),
          TeamAttendanceEntry(
            employee: employee,
            record: AttendanceRecord(
              employeeId: 'employee',
              workDate: '2026-10-25',
              checkInAt: DateTime.utc(2026, 10, 25, 1),
              checkOutAt: DateTime.utc(2026, 10, 25, 9),
            ),
          ),
        ];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              child: TeamAttendanceHistoryScreen(
                profile: manager,
                repository: repository,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Check-out: Chưa check-out'), findsOneWidget);
      expect(find.text('Đang làm việc'), findsOneWidget);
      expect(find.text('Check-out: 16:00'), findsOneWidget);
      expect(
        find.text('Tổng thời gian làm việc: 8 giờ 00 phút'),
        findsOneWidget,
      );
      expect(find.text('Đã hoàn thành ca'), findsOneWidget);
      await tester.tap(find.text('Tuần này'));
      await tester.pump();
      expect(repository.startDate, isNotNull);
      expect(repository.endDate, isNotNull);
    },
  );
}
