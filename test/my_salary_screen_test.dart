import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/home/presentation/role_home_screens.dart';
import 'package:smart_attendance/features/payroll/data/my_salary_repository.dart';
import 'package:smart_attendance/features/payroll/domain/work_time_calculator.dart';
import 'package:smart_attendance/features/payroll/presentation/my_salary_screen.dart';

const employee = UserProfile(
  uid: 'mine',
  displayName: 'Nhân viên',
  role: UserRole.employee,
);
const manager = UserProfile(
  uid: 'manager',
  displayName: 'Quản lý',
  role: UserRole.manager,
);

class FakeMySalaryRepository implements MySalaryRepository {
  MySalaryData data = const MySalaryData(
    uid: 'mine',
    hourlyRate: 30000,
    attendance: [],
  );
  Object? failure;
  Completer<MySalaryData>? pending;
  int calls = 0;
  String? start;
  String? end;

  @override
  Future<MySalaryData> loadPeriod(String startDate, String endDate) async {
    calls++;
    start = startDate;
    end = endDate;
    if (failure != null) throw failure!;
    return pending?.future ?? data;
  }
}

WorkAttendance record(
  String date, {
  bool checkedOut = true,
  String method = 'manual',
}) => WorkAttendance(
  employeeUid: 'mine',
  workDate: date,
  status: checkedOut ? 'completed' : 'working',
  method: method,
  checkInAt: DateTime.utc(2026, 10, int.parse(date.substring(8)), 1),
  checkOutAt: checkedOut
      ? DateTime.utc(2026, 10, int.parse(date.substring(8)), 10)
      : null,
);

Future<void> pumpScreen(
  WidgetTester tester,
  FakeMySalaryRepository repository, {
  UserProfile profile = employee,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MySalaryScreen(
        profile: profile,
        repository: repository,
        initialDate: DateTime.utc(2026, 10, 15),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Employee mở Lương của tôi từ trang chủ', (tester) async {
    final repository = FakeMySalaryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: EmployeeHomeScreen(
          profile: employee,
          onSignOut: () {},
          mySalaryRepository: repository,
        ),
      ),
    );
    await tester.ensureVisible(find.text('Lương của tôi').last);
    await tester.tap(find.text('Lương của tôi').last);
    await tester.pumpAndSettle();
    expect(find.byType(MySalaryScreen), findsOneWidget);
    expect(repository.calls, 1);
  });

  testWidgets('Employee mở Giờ làm từ trang chủ và không hiển thị tiền lương', (
    tester,
  ) async {
    final repository = FakeMySalaryRepository()
      ..data = MySalaryData(
        uid: 'mine',
        hourlyRate: 30000,
        attendance: [record('2026-10-29', method: 'nfc_mobile')],
      );
    await tester.pumpWidget(
      MaterialApp(
        home: EmployeeHomeScreen(
          profile: employee,
          onSignOut: () {},
          mySalaryRepository: repository,
        ),
      ),
    );

    await tester.ensureVisible(find.text('Giờ làm').last);
    await tester.tap(find.text('Giờ làm').last);
    await tester.pumpAndSettle();

    expect(find.text('Giờ làm của tôi'), findsOneWidget);
    expect(find.text('Tổng giờ công hợp lệ: 8 giờ 0 phút'), findsOneWidget);
    expect(find.textContaining('NFC trên điện thoại'), findsOneWidget);
    expect(find.textContaining('Đơn giá theo giờ'), findsNothing);
    expect(find.textContaining('Lương tạm tính'), findsNothing);
    expect(repository.calls, 1);
  });

  testWidgets('tính tuần hợp lệ, thiếu Check-out và chi tiết phương thức', (
    tester,
  ) async {
    final repository = FakeMySalaryRepository()
      ..data = MySalaryData(
        uid: 'mine',
        hourlyRate: 30000,
        attendance: [
          record('2026-10-12', method: 'nfc_mobile'),
          record('2026-10-13', checkedOut: false),
        ],
      );
    await pumpScreen(tester, repository);
    expect(repository.start, '2026-10-12');
    expect(repository.end, '2026-10-18');
    expect(find.text('Tổng giờ công hợp lệ: 8 giờ 0 phút'), findsOneWidget);
    expect(find.text('Lương tạm tính: 240000 ₫'), findsOneWidget);
    expect(
      find.text('Bản ghi chưa hoàn thành hoặc không hợp lệ: 1'),
      findsOneWidget,
    );
    expect(find.textContaining('Vào: 08:00 · Ra: 17:00'), findsOneWidget);
    expect(
      find.textContaining('Chưa hoàn thành · Không tính lương'),
      findsOneWidget,
    );
    expect(find.textContaining('NFC trên điện thoại'), findsOneWidget);
    expect(find.textContaining('Thủ công'), findsOneWidget);
  });

  testWidgets('tháng rỗng và đơn giá sai không tạo tiền lương', (tester) async {
    final repository = FakeMySalaryRepository()
      ..data = const MySalaryData(uid: 'mine', hourlyRate: -1, attendance: []);
    await pumpScreen(tester, repository);
    await tester.tap(find.text('Tháng'));
    await tester.pumpAndSettle();
    expect(repository.start, '2026-10-01');
    expect(repository.end, '2026-10-31');
    expect(find.text('Kỳ này chưa có dữ liệu chấm công.'), findsOneWidget);
    expect(find.text('Lương tạm tính: Chưa có đơn giá hợp lệ'), findsOneWidget);
  });

  testWidgets('giới hạn quyền theo role và UID', (tester) async {
    final repository = FakeMySalaryRepository();
    await pumpScreen(tester, repository, profile: manager);
    expect(repository.calls, 0);
    expect(find.text('Không có quyền xem lương tạm tính.'), findsOneWidget);
    await pumpScreen(tester, repository);
    repository.data = const MySalaryData(
      uid: 'someone-else',
      hourlyRate: 100,
      attendance: [],
    );
    await tester.tap(find.byTooltip('Kỳ trước'));
    await tester.pumpAndSettle();
    expect(find.text('Không có quyền xem lương tạm tính.'), findsOneWidget);
  });

  testWidgets('loading, lỗi quyền và lỗi mạng', (tester) async {
    final repository = FakeMySalaryRepository()
      ..pending = Completer<MySalaryData>();
    await tester.pumpWidget(
      MaterialApp(
        home: MySalaryScreen(
          profile: employee,
          repository: repository,
          initialDate: DateTime.utc(2026, 10, 15),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.pending!.complete(repository.data);
    await tester.pumpAndSettle();
    repository.pending = null;
    repository.failure = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    await tester.tap(find.byTooltip('Kỳ trước'));
    await tester.pumpAndSettle();
    expect(find.text('Không có quyền xem lương tạm tính.'), findsOneWidget);
    repository.failure = StateError('offline');
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kiểm tra kết nối'), findsOneWidget);
  });
}
