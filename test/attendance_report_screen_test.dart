import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/home/presentation/role_home_screens.dart';
import 'package:smart_attendance/features/payroll/domain/work_time_calculator.dart';
import 'package:smart_attendance/features/statistics/data/attendance_report_repository.dart';
import 'package:smart_attendance/features/statistics/data/report_email_api_client.dart';
import 'package:smart_attendance/features/statistics/data/report_email_repository.dart';
import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';
import 'package:smart_attendance/features/statistics/domain/employee_attendance_pdf.dart';
import 'package:smart_attendance/features/statistics/presentation/attendance_report_screen.dart';

const admin = UserProfile(
  uid: 'admin',
  displayName: 'Admin',
  role: UserRole.admin,
);
const manager = UserProfile(
  uid: 'manager',
  displayName: 'Manager',
  role: UserRole.manager,
);
const employee = UserProfile(
  uid: 'employee',
  displayName: 'Employee',
  role: UserRole.employee,
);

class FakeReportRepository implements AttendanceReportRepository {
  AttendanceReportData data = const AttendanceReportData(
    records: [],
    employeeNames: {},
  );
  Object? failure;
  Completer<AttendanceReportData>? pending;
  int calls = 0;
  String? start;
  String? end;
  UserProfile? profile;

  @override
  Future<AttendanceReportData> loadPeriod(
    UserProfile user,
    String from,
    String to,
  ) async {
    calls++;
    profile = user;
    start = from;
    end = to;
    if (failure != null) throw failure!;
    return pending?.future ?? data;
  }
}

class FakePdfGenerator extends EmployeeAttendancePdfGenerator {
  int calls = 0;
  String? name;
  String? email;
  String? uid;

  @override
  Future<EmployeeAttendancePdf> generate({
    required String employeeUid,
    required String employeeName,
    required String employeeEmail,
    required AttendanceStatisticsPeriod period,
    required Iterable<StatisticsAttendance> records,
    required DateTime exportedAt,
    required ByteData fontData,
  }) async {
    calls++;
    uid = employeeUid;
    name = employeeName;
    email = employeeEmail;
    return EmployeeAttendancePdf(
      bytes: Uint8List.fromList([37, 80, 68, 70]),
      fileName: 'report.pdf',
    );
  }
}

class FakeReportEmailRepository implements ReportEmailRepositoryContract {
  int calls = 0;
  String? employeeUid;
  String? periodKind;
  String? anchorDate;
  Object? failure;
  Completer<ReportEmailAccepted>? pending;

  @override
  Future<ReportEmailAccepted> sendReport({
    required String employeeUid,
    required String periodKind,
    required String anchorDate,
  }) async {
    calls++;
    this.employeeUid = employeeUid;
    this.periodKind = periodKind;
    this.anchorDate = anchorDate;
    if (failure != null) throw failure!;
    return pending?.future ?? accepted(employeeUid);
  }
}

ReportEmailAccepted accepted(String employeeUid) => ReportEmailAccepted(
  requestId: 'request-id',
  employeeUid: employeeUid,
  periodKind: 'week',
  startDate: '2026-10-12',
  endDate: '2026-10-18',
  maskedRecipient: 'a***@example.com',
  acceptedAtUtc: DateTime.utc(2026, 10, 15),
);

StatisticsAttendance record(
  String uid,
  String date, {
  String method = 'biometric',
  bool working = false,
  int? revision,
}) {
  final day = DateTime.parse(date);
  return StatisticsAttendance(
    WorkAttendance(
      employeeUid: uid,
      workDate: date,
      status: working ? 'working' : 'completed',
      method: method,
      checkInAt: DateTime.utc(day.year, day.month, day.day, 1),
      checkOutAt: working
          ? null
          : DateTime.utc(day.year, day.month, day.day, 10),
    ),
    manualRevision: revision,
  );
}

Future<void> pumpReport(
  WidgetTester tester,
  FakeReportRepository repository, {
  UserProfile profile = admin,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AttendanceReportScreen(
        profile: profile,
        repository: repository,
        initialDate: DateTime.utc(2026, 10, 15, 12),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Admin và Manager mở Báo cáo thống kê từ trang chủ', (
    tester,
  ) async {
    for (final profile in [admin, manager]) {
      final repository = FakeReportRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: profile.role == UserRole.admin
              ? AdminHomeScreen(
                  profile: profile,
                  onSignOut: () {},
                  attendanceReportRepository: repository,
                )
              : ManagerHomeScreen(
                  profile: profile,
                  onSignOut: () {},
                  attendanceReportRepository: repository,
                ),
        ),
      );
      await tester.ensureVisible(find.text('Báo cáo thống kê').last);
      await tester.tap(find.text('Báo cáo thống kê').last);
      await tester.pumpAndSettle();
      expect(find.byType(AttendanceReportScreen), findsOneWidget);
      expect(repository.profile, profile);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('đổi tuần, tháng, quý, năm và kỳ trước/sau', (tester) async {
    final repository = FakeReportRepository();
    await pumpReport(tester, repository);
    expect((repository.start, repository.end), ('2026-10-12', '2026-10-18'));
    await tester.tap(find.byTooltip('Kỳ trước'));
    await tester.pumpAndSettle();
    expect((repository.start, repository.end), ('2026-10-05', '2026-10-11'));
    await tester.tap(find.byTooltip('Kỳ sau'));
    await tester.pumpAndSettle();
    expect((repository.start, repository.end), ('2026-10-12', '2026-10-18'));
    for (final (label, dates) in [
      ('Tháng', ('2026-10-01', '2026-10-31')),
      ('Quý', ('2026-10-01', '2026-12-31')),
      ('Năm', ('2026-01-01', '2026-12-31')),
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect((repository.start, repository.end), dates);
    }
  });

  testWidgets('tổng hợp, biểu đồ, bảng nhân viên và màn hình chi tiết', (
    tester,
  ) async {
    final repository = FakeReportRepository()
      ..data = AttendanceReportData(
        employeeNames: const {'a': 'Nguyễn A', 'b': 'Trần B'},
        records: [
          record('a', '2026-10-12'),
          record('a', '2026-10-13', method: 'nfc', revision: 1),
          record('b', '2026-10-12', method: 'manual', revision: 1),
          record('b', '2026-10-14', working: true),
        ],
      );
    await pumpReport(tester, repository);
    expect(find.text('3'), findsWidgets); // Completed and method counts.
    expect(find.text('24 giờ 0 phút'), findsOneWidget);
    expect(find.text('Bản ghi điều chỉnh thủ công'), findsOneWidget);
    expect(find.textContaining('không cộng thêm vào biểu đồ'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Nguyễn A'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Nguyễn A'), findsOneWidget);
    await tester.tap(find.text('Nguyễn A'));
    await tester.pumpAndSettle();
    expect(find.text('UID: a'), findsOneWidget);
    expect(find.text('16 giờ 0 phút'), findsOneWidget);
    expect(find.text('Phân bố phương thức'), findsOneWidget);
  });

  testWidgets('kỳ rỗng, bản ghi xung đột và dữ liệu không hợp lệ', (
    tester,
  ) async {
    final repository = FakeReportRepository();
    await pumpReport(tester, repository);
    expect(find.text('Kỳ này chưa có dữ liệu chấm công.'), findsOneWidget);
    repository.data = AttendanceReportData(
      employeeNames: const {'a': 'Nguyễn A'},
      records: [
        record('a', '2026-10-12'),
        record('a', '2026-10-12', method: 'nfc'),
      ],
    );
    await tester.tap(find.byTooltip('Kỳ sau'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kỳ trước'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('1 ngày có bản ghi xung đột'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('1 ngày có bản ghi xung đột'), findsOneWidget);
    expect(find.text('0 giờ 0 phút'), findsWidgets);
    expect(find.text('Nguyễn A'), findsOneWidget);
    await tester.tap(find.text('Nguyễn A'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
  });

  testWidgets('loading, quyền, lỗi mạng và thử lại', (tester) async {
    final repository = FakeReportRepository()
      ..pending = Completer<AttendanceReportData>();
    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceReportScreen(
          profile: manager,
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
    expect(find.text('Không có quyền xem báo cáo thống kê.'), findsOneWidget);
    repository.failure = StateError('offline');
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kiểm tra kết nối'), findsOneWidget);
  });

  testWidgets('Employee không gọi repository báo cáo', (tester) async {
    final repository = FakeReportRepository();
    await pumpReport(tester, repository, profile: employee);
    expect(repository.calls, 0);
    expect(find.text('Không có quyền xem báo cáo thống kê.'), findsOneWidget);
  });

  testWidgets('báo cáo hiển thị ở chế độ tối', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: AttendanceReportScreen(
          profile: admin,
          repository: FakeReportRepository(),
          initialDate: DateTime.utc(2026, 10, 15, 12),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Phân bố phương thức'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('xuất PDF đọc lại quyền, dùng email và chặn nhấn liên tục', (
    tester,
  ) async {
    final repository = FakeReportRepository()
      ..data = AttendanceReportData(
        employeeNames: const {'a': 'Nguyễn A'},
        employeeEmails: const {'a': 'a@example.com'},
        records: [record('a', '2026-10-12')],
      );
    final generator = FakePdfGenerator();
    EmployeeAttendancePdf? previewed;
    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceReportScreen(
          profile: admin,
          repository: repository,
          pdfGenerator: generator,
          previewHandler: (_, pdf) async {
            previewed = pdf;
          },
          initialDate: DateTime.utc(2026, 10, 15, 12),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Nguyễn A'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Nguyễn A'));
    await tester.pumpAndSettle();
    repository.pending = Completer<AttendanceReportData>();
    await tester.tap(find.text('Xuất PDF'));
    await tester.pump();
    expect(repository.calls, 2);
    expect(find.text('Đang tạo PDF…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    repository.pending!.complete(repository.data);
    await tester.pumpAndSettle();
    expect(generator.calls, 1);
    expect(
      (generator.uid, generator.name, generator.email),
      ('a', 'Nguyễn A', 'a@example.com'),
    );
    expect(previewed?.fileName, 'report.pdf');
  });

  testWidgets('quyền xuất bị từ chối sau khi mở chi tiết', (tester) async {
    final repository = FakeReportRepository()
      ..data = AttendanceReportData(
        employeeNames: const {'a': 'Nguyễn A'},
        records: [record('a', '2026-10-12')],
      );
    final generator = FakePdfGenerator();
    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceReportScreen(
          profile: manager,
          repository: repository,
          pdfGenerator: generator,
          previewHandler: (_, _) async {},
          initialDate: DateTime.utc(2026, 10, 15, 12),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Nguyễn A'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Nguyễn A'));
    await tester.pumpAndSettle();
    repository.failure = const AttendanceReportAccessException();
    await tester.tap(find.text('Xuất PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Không có quyền xuất báo cáo.'), findsOneWidget);
    expect(generator.calls, 0);
  });

  testWidgets('Admin mở ô Email từ trang chủ thay vì placeholder', (
    tester,
  ) async {
    final repository = FakeReportRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminHomeScreen(
          profile: admin,
          onSignOut: () {},
          attendanceReportRepository: repository,
          reportEmailRepository: FakeReportEmailRepository(),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Gửi email'));
    await tester.tap(find.text('Gửi email'));
    await tester.pumpAndSettle();

    expect(find.byType(AttendanceReportScreen), findsOneWidget);
    expect(find.text('Đang phát triển'), findsNothing);
    expect(repository.profile, admin);
  });

  for (final profile in [admin, manager]) {
    testWidgets('${profile.role.name} gửi REST, có loading và accepted', (
      tester,
    ) async {
      final repository = FakeReportRepository()
        ..data = AttendanceReportData(
          employeeNames: const {'a': 'Nguyễn A'},
          employeeEmails: const {'a': 'khong-duoc-gui@example.com'},
          records: [record('a', '2026-10-12')],
        );
      final emailRepository = FakeReportEmailRepository()
        ..pending = Completer<ReportEmailAccepted>();
      final generator = FakePdfGenerator();
      await tester.pumpWidget(
        MaterialApp(
          home: AttendanceReportScreen(
            profile: profile,
            repository: repository,
            reportEmailRepository: emailRepository,
            pdfGenerator: generator,
            initialDate: DateTime.utc(2026, 10, 15, 12),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Nguyễn A'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Nguyễn A'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gửi báo cáo qua email'));
      await tester.pump();
      await tester.tap(find.text('Đang gửi yêu cầu…'));
      await tester.pump();

      expect(emailRepository.calls, 1);
      expect(
        (
          emailRepository.employeeUid,
          emailRepository.periodKind,
          emailRepository.anchorDate,
        ),
        ('a', 'week', '2026-10-12'),
      );
      expect(generator.calls, 0);
      expect(repository.calls, 1);
      emailRepository.pending!.complete(accepted('a'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Hệ thống đã tiếp nhận yêu cầu gửi email'),
        findsOneWidget,
      );
      expect(find.textContaining('đã nhận thư'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
    });
  }

  for (final failure in [
    ReportEmailApiFailure.network,
    ReportEmailApiFailure.unavailable,
    ReportEmailApiFailure.conflict,
  ]) {
    testWidgets('$failure khóa gửi lại để tránh email trùng', (tester) async {
      final repository = FakeReportRepository()
        ..data = AttendanceReportData(
          employeeNames: const {'a': 'Nguyễn A'},
          records: [record('a', '2026-10-12')],
        );
      final emailRepository = FakeReportEmailRepository()
        ..failure = ReportEmailUncertainException(
          ReportEmailApiException(failure),
        );
      await tester.pumpWidget(
        MaterialApp(
          home: AttendanceReportScreen(
            profile: admin,
            repository: repository,
            reportEmailRepository: emailRepository,
            initialDate: DateTime.utc(2026, 10, 15, 12),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Nguyễn A'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Nguyễn A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi báo cáo qua email'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Không gửi lại yêu cầu mới'), findsOneWidget);
      expect(emailRepository.calls, 1);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
    });
  }

  testWidgets('lỗi 422 hiển thị rõ và không dùng PDF phía Flutter', (
    tester,
  ) async {
    final repository = FakeReportRepository()
      ..data = AttendanceReportData(
        employeeNames: const {'a': 'Nguyễn A'},
        records: [record('a', '2026-10-12')],
      );
    final emailRepository = FakeReportEmailRepository()
      ..failure = const ReportEmailApiException(
        ReportEmailApiFailure.unprocessable,
        statusCode: 422,
      );
    final generator = FakePdfGenerator();
    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceReportScreen(
          profile: manager,
          repository: repository,
          reportEmailRepository: emailRepository,
          pdfGenerator: generator,
          initialDate: DateTime.utc(2026, 10, 15, 12),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Nguyễn A'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Nguyễn A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gửi báo cáo qua email'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Email đăng ký hoặc dữ liệu báo cáo'),
      findsOneWidget,
    );
    expect(generator.calls, 0);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
  });
}
