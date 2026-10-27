import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/home/presentation/role_home_screens.dart';
import 'package:smart_attendance/features/payroll/data/payroll_repository.dart';
import 'package:smart_attendance/features/payroll/domain/work_time_calculator.dart';
import 'package:smart_attendance/features/payroll/presentation/payroll_screen.dart';

const _manager = UserProfile(
  uid: 'manager-1',
  displayName: 'Quản lý',
  role: UserRole.manager,
);
const _admin = UserProfile(
  uid: 'admin-1',
  displayName: 'Admin',
  role: UserRole.admin,
);
const _employee = UserProfile(
  uid: 'employee-1',
  displayName: 'NV',
  role: UserRole.employee,
);

void main() {
  testWidgets('Admin và Manager mở Bảng lương từ trang chủ', (tester) async {
    for (final profile in [_admin, _manager]) {
      final repository = _FakePayrollRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: profile.role == UserRole.admin
              ? AdminHomeScreen(
                  profile: profile,
                  onSignOut: () {},
                  payrollRepository: repository,
                )
              : ManagerHomeScreen(
                  profile: profile,
                  onSignOut: () {},
                  payrollRepository: repository,
                ),
        ),
      );
      await tester.ensureVisible(find.text('Bảng lương').last);
      await tester.tap(find.text('Bảng lương').last);
      await tester.pumpAndSettle();
      expect(find.byType(PayrollScreen), findsOneWidget);
      expect(repository.loadCalls, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('tuần hiện tại, tính tổng từ dữ liệu giả và xem chi tiết', (
    tester,
  ) async {
    final repository = _FakePayrollRepository()
      ..data = PayrollData(
        employees: const [
          PayrollEmployee(uid: 'e1', name: 'Nguyễn A', hourlyRate: 30000),
        ],
        attendance: [
          _record('2026-10-05', 8, 17),
          _record('2026-10-06', 8, 17, status: 'working', checkOut: false),
        ],
      );
    await _pump(tester, repository);
    expect(repository.start, '2026-10-05');
    expect(repository.end, '2026-10-11');
    expect(find.textContaining('8 giờ 0 phút'), findsOneWidget);
    expect(find.textContaining('240000 ₫'), findsOneWidget);
    expect(find.textContaining('Cảnh báo: 1 bản ghi'), findsOneWidget);
    await tester.tap(find.text('Nguyễn A'));
    await tester.pumpAndSettle();
    expect(find.textContaining('480 phút'), findsOneWidget);
    expect(
      find.textContaining('Không tính lương (Chưa hoàn thành)'),
      findsOneWidget,
    );
  });

  testWidgets('chuyển sang tháng và kỳ không có chấm công', (tester) async {
    final repository = _FakePayrollRepository()
      ..data = const PayrollData(
        employees: [
          PayrollEmployee(uid: 'e1', name: 'Nguyễn A', hourlyRate: 30000),
        ],
        attendance: [],
      );
    await _pump(tester, repository);
    await tester.tap(find.text('Tháng'));
    await tester.pumpAndSettle();
    expect(repository.start, '2026-10-01');
    expect(repository.end, '2026-10-31');
    expect(find.text('Kỳ này chưa có dữ liệu chấm công.'), findsOneWidget);
    await tester.tap(find.byTooltip('Kỳ trước'));
    await tester.pumpAndSettle();
    expect(repository.start, '2026-09-01');
    expect(repository.end, '2026-09-30');
  });

  testWidgets('đơn giá thiếu không hiển thị tiền lương bằng 0', (tester) async {
    final repository = _FakePayrollRepository()
      ..data = PayrollData(
        employees: const [PayrollEmployee(uid: 'e1', name: 'Nguyễn A')],
        attendance: [_record('2026-10-05', 8, 17)],
      );
    await _pump(tester, repository);
    expect(
      find.textContaining('Lương tạm tính: Chưa có đơn giá hợp lệ'),
      findsOneWidget,
    );
  });

  testWidgets('từ chối Employee và tài khoản không active', (tester) async {
    final repository = _FakePayrollRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: PayrollScreen(
          profile: _employee,
          repository: repository,
          initialDate: DateTime(2026, 10, 11),
        ),
      ),
    );
    expect(find.text('Không có quyền xem bảng lương.'), findsOneWidget);
    expect(repository.loadCalls, 0);
    repository.allowed = false;
    await _pump(tester, repository);
    expect(find.text('Không có quyền xem bảng lương.'), findsOneWidget);
    expect(repository.loadCalls, 0);
  });

  testWidgets('lỗi quyền và lỗi mạng hiển thị thử lại', (tester) async {
    final repository = _FakePayrollRepository()
      ..failure = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    await _pump(tester, repository);
    expect(find.text('Không có quyền xem bảng lương.'), findsOneWidget);
    repository.failure = StateError('offline');
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(
      find.text('Không tải được bảng lương. Kiểm tra kết nối và thử lại.'),
      findsOneWidget,
    );
    repository.failure = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có nhân viên.'), findsOneWidget);
  });

  testWidgets('hiển thị loading khi đang đọc kỳ', (tester) async {
    final pending = Completer<PayrollData>();
    final repository = _FakePayrollRepository()..pending = pending;
    await tester.pumpWidget(
      MaterialApp(
        home: PayrollScreen(
          profile: _manager,
          repository: repository,
          initialDate: DateTime(2026, 10, 11),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(const PayrollData(employees: [], attendance: []));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có nhân viên.'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  _FakePayrollRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PayrollScreen(
        profile: _manager,
        repository: repository,
        initialDate: DateTime(2026, 10, 11),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

WorkAttendance _record(
  String date,
  int inHour,
  int outHour, {
  String status = 'completed',
  bool checkOut = true,
}) {
  final day = DateTime.parse(date);
  return WorkAttendance(
    employeeUid: 'e1',
    workDate: date,
    status: status,
    method: 'manual',
    checkInAt: DateTime.utc(day.year, day.month, day.day, inHour - 7),
    checkOutAt: checkOut
        ? DateTime.utc(day.year, day.month, day.day, outHour - 7)
        : null,
  );
}

class _FakePayrollRepository implements PayrollRepository {
  bool allowed = true;
  Object? failure;
  Completer<PayrollData>? pending;
  PayrollData data = const PayrollData(employees: [], attendance: []);
  int loadCalls = 0;
  String? start;
  String? end;

  @override
  Future<bool> canAccess(UserProfile profile) async => allowed;

  @override
  Future<PayrollData> loadPeriod(
    UserProfile profile,
    String startDate,
    String endDate,
  ) async {
    loadCalls++;
    start = startDate;
    end = endDate;
    if (failure != null) throw failure!;
    if (pending != null) return pending!.future;
    return data;
  }
}
