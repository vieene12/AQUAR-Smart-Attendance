import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/home/presentation/role_home_screens.dart';
import 'package:smart_attendance/features/payroll/domain/work_time_calculator.dart';
import 'package:smart_attendance/features/statistics/data/my_attendance_report_repository.dart';
import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';
import 'package:smart_attendance/features/statistics/presentation/my_attendance_report_screen.dart';

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

class FakeMyReportRepository implements MyAttendanceReportRepository {
  MyAttendanceReportData data = const MyAttendanceReportData(
    uid: 'mine',
    records: [],
  );
  Object? failure;
  Completer<MyAttendanceReportData>? pending;
  int calls = 0;
  String? start;
  String? end;

  @override
  Future<MyAttendanceReportData> loadPeriod(String from, String to) async {
    calls++;
    start = from;
    end = to;
    if (failure != null) throw failure!;
    return pending?.future ?? data;
  }
}

StatisticsAttendance record(
  String uid,
  String date, {
  String status = 'completed',
  String method = 'biometric',
  bool checkout = true,
  int? revision,
}) {
  final day = DateTime.parse(date);
  return StatisticsAttendance(
    WorkAttendance(
      employeeUid: uid,
      workDate: date,
      status: status,
      method: method,
      checkInAt: DateTime.utc(day.year, day.month, day.day, 1),
      checkOutAt: checkout
          ? DateTime.utc(day.year, day.month, day.day, 10)
          : null,
    ),
    manualRevision: revision,
  );
}

Future<void> pumpReport(
  WidgetTester tester,
  FakeMyReportRepository repository, {
  UserProfile profile = employee,
  DateTime? date,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MyAttendanceReportScreen(
        profile: profile,
        repository: repository,
        initialDate: date ?? DateTime.utc(2026, 10, 15, 12),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Employee mở Báo cáo của tôi từ trang chủ', (tester) async {
    final repository = FakeMyReportRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: EmployeeHomeScreen(
          profile: employee,
          onSignOut: () {},
          myAttendanceReportRepository: repository,
        ),
      ),
    );
    await tester.ensureVisible(find.text('Báo cáo của tôi').last);
    await tester.tap(find.text('Báo cáo của tôi').last);
    await tester.pumpAndSettle();
    expect(find.byType(MyAttendanceReportScreen), findsOneWidget);
    expect(repository.calls, 1);
  });

  testWidgets('kỳ tuần Việt Nam, tháng, quý, năm và chuyển kỳ', (tester) async {
    final repository = FakeMyReportRepository();
    await pumpReport(
      tester,
      repository,
      date: DateTime.utc(2026, 10, 11, 18),
    ); // Monday 01:00 in Vietnam.
    expect((repository.start, repository.end), ('2026-10-12', '2026-10-18'));
    await tester.tap(find.byTooltip('Kỳ trước'));
    await tester.pumpAndSettle();
    expect((repository.start, repository.end), ('2026-10-05', '2026-10-11'));
    await tester.tap(find.byTooltip('Kỳ sau'));
    await tester.pumpAndSettle();
    for (final (label, range) in [
      ('Tháng', ('2026-10-01', '2026-10-31')),
      ('Quý', ('2026-10-01', '2026-12-31')),
      ('Năm', ('2026-01-01', '2026-12-31')),
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect((repository.start, repository.end), range);
    }
  });

  testWidgets('tổng thống kê và chi tiết chỉ gồm UID của mình', (tester) async {
    final repository = FakeMyReportRepository()
      ..data = MyAttendanceReportData(
        uid: 'mine',
        records: [
          record('mine', '2026-10-12'),
          record(
            'mine',
            '2026-10-13',
            status: 'working',
            method: 'nfc_mobile',
            checkout: false,
          ),
          record('mine', '2026-10-14', method: 'manual', revision: 1),
          record('other', '2026-10-15'),
        ],
      );
    await pumpReport(tester, repository);
    expect(find.text('Tổng giờ công hợp lệ: 16 giờ 0 phút'), findsOneWidget);
    expect(find.text('Số ngày có chấm công: 3'), findsOneWidget);
    expect(find.text('Completed: 2'), findsOneWidget);
    expect(find.text('Working / chưa Check-out: 1'), findsOneWidget);
    expect(find.text('Biometric: 1 · NFC: 1 · Manual: 1'), findsOneWidget);
    expect(find.text('Bản ghi có điều chỉnh thủ công: 1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('2026-10-13'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('Thiếu giờ chấm công / Check-out'),
      findsOneWidget,
    );
    expect(find.textContaining('NFC mobile'), findsOneWidget);
    expect(find.text('2026-10-15'), findsNothing);
  });

  testWidgets('rỗng, thiếu dữ liệu và xung đột có thông báo', (tester) async {
    final repository = FakeMyReportRepository();
    await pumpReport(tester, repository);
    expect(find.text('Kỳ này chưa có dữ liệu chấm công.'), findsOneWidget);
    repository.data = MyAttendanceReportData(
      uid: 'mine',
      records: [
        record('mine', '2026-10-12', checkout: false),
        record('mine', '2026-10-13'),
        record('mine', '2026-10-13', method: 'nfc'),
      ],
    );
    await tester.tap(find.byTooltip('Kỳ trước'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kỳ sau'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('2 ngày có dữ liệu thiếu, xung đột'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('2026-10-13').first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Nhiều bản ghi cùng ngày'), findsWidgets);
    expect(find.text('Tổng giờ công hợp lệ: 0 giờ 0 phút'), findsOneWidget);
  });

  testWidgets('loading, lỗi quyền và lỗi mạng', (tester) async {
    final repository = FakeMyReportRepository()
      ..pending = Completer<MyAttendanceReportData>();
    await tester.pumpWidget(
      MaterialApp(
        home: MyAttendanceReportScreen(
          profile: employee,
          repository: repository,
          initialDate: DateTime.utc(2026, 10, 15, 12),
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
    expect(find.text('Không có quyền xem báo cáo của tôi.'), findsOneWidget);
    repository.failure = StateError('offline');
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kiểm tra kết nối'), findsOneWidget);
  });

  testWidgets('role khác và UID khác bị từ chối', (tester) async {
    final repository = FakeMyReportRepository();
    await pumpReport(tester, repository, profile: manager);
    expect(repository.calls, 0);
    expect(find.text('Không có quyền xem báo cáo của tôi.'), findsOneWidget);
    repository.data = const MyAttendanceReportData(uid: 'other', records: []);
    await pumpReport(tester, repository);
    expect(find.text('Không có quyền xem báo cáo của tôi.'), findsOneWidget);
  });

  testWidgets('báo cáo hiển thị ở chế độ tối', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: MyAttendanceReportScreen(
          profile: employee,
          repository: FakeMyReportRepository(),
          initialDate: DateTime.utc(2026, 10, 15, 12),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Báo cáo của tôi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
