import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/home/presentation/role_home_screens.dart';
import 'package:smart_attendance/features/payroll/domain/work_time_calculator.dart';
import 'package:smart_attendance/features/statistics/data/attendance_report_repository.dart';
import 'package:smart_attendance/features/statistics/data/report_email_composer.dart';
import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';
import 'package:smart_attendance/features/statistics/domain/employee_attendance_pdf.dart';
import 'package:smart_attendance/features/statistics/domain/report_email_draft.dart';
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

class FakeEmailComposer implements ReportEmailComposer {
  int calls = 0;
  ReportEmailDraft? draft;
  EmployeeAttendancePdf? pdf;
  Object? failure;
  Completer<void>? pending;

  @override
  Future<void> openDraft(
    ReportEmailDraft value,
    EmployeeAttendancePdf file,
  ) async {
    calls++;
    draft = value;
    pdf = file;
    if (failure != null) throw failure!;
    if (pending != null) await pending!.future;
  }
}

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

  testWidgets(
    'soạn email dùng địa chỉ Firestore mới, PDF hiện có và không đánh dấu đã gửi',
    (tester) async {
      final repository = FakeReportRepository()
        ..data = AttendanceReportData(
          employeeNames: const {'a': 'Nguyễn A'},
          employeeEmails: const {'a': 'old@example.com'},
          records: [record('a', '2026-10-12')],
        );
      final generator = FakePdfGenerator();
      final composer = FakeEmailComposer();
      await tester.pumpWidget(
        MaterialApp(
          home: AttendanceReportScreen(
            profile: manager,
            repository: repository,
            pdfGenerator: generator,
            emailComposer: composer,
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
      repository.data = AttendanceReportData(
        employeeNames: const {'a': 'Nguyễn Văn A'},
        employeeEmails: const {'a': 'new@example.com'},
        records: [record('a', '2026-10-12')],
      );
      composer.pending = Completer<void>();
      await tester.tap(find.text('Gửi báo cáo qua email'));
      await tester.pump();
      expect(repository.calls, 2);
      expect(find.text('Đang soạn email…'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(generator.calls, 1);
      expect(
        (generator.uid, generator.name, generator.email),
        ('a', 'Nguyễn Văn A', 'new@example.com'),
      );
      expect(composer.calls, 1);
      expect(composer.draft?.recipient, 'new@example.com');
      expect(composer.draft?.subject, contains('Nguyễn Văn A'));
      expect(composer.draft?.body, contains('2026-10-12'));
      expect(composer.pdf?.fileName, 'report.pdf');
      composer.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Chưa xác nhận email đã gửi'), findsOneWidget);
      expect(find.text('Chia sẻ PDF thủ công'), findsOneWidget);
      repository.failure = const AttendanceReportAccessException();
      await tester.drag(find.byType(ListView).last, const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chia sẻ PDF thủ công'));
      await tester.pumpAndSettle();
      expect(find.text('Không có quyền chia sẻ báo cáo.'), findsOneWidget);
      expect(find.text('Chia sẻ PDF thủ công'), findsNothing);
    },
  );

  testWidgets('email sai không tạo PDF; thiếu ứng dụng có chia sẻ thủ công', (
    tester,
  ) async {
    final repository = FakeReportRepository()
      ..data = AttendanceReportData(
        employeeNames: const {'a': 'Nguyễn A'},
        employeeEmails: const {'a': 'invalid-email'},
        records: [record('a', '2026-10-12')],
      );
    final generator = FakePdfGenerator();
    final composer = FakeEmailComposer();
    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceReportScreen(
          profile: admin,
          repository: repository,
          pdfGenerator: generator,
          emailComposer: composer,
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
    expect(find.textContaining('thiếu hoặc không hợp lệ'), findsOneWidget);
    expect(generator.calls, 0);
    expect(composer.calls, 0);
    repository.data = AttendanceReportData(
      employeeNames: const {'a': 'Nguyễn A'},
      employeeEmails: const {'a': 'a@example.com'},
      records: [record('a', '2026-10-12')],
    );
    composer.failure = PlatformException(code: 'no_email_app');
    await tester.tap(find.text('Gửi báo cáo qua email'));
    await tester.pumpAndSettle();
    expect(generator.calls, 1);
    expect(find.textContaining('Không có ứng dụng email'), findsOneWidget);
    expect(find.text('Chia sẻ PDF thủ công'), findsOneWidget);
  });

  testWidgets('mất quyền sau khi mở chi tiết không soạn email hoặc giữ PDF', (
    tester,
  ) async {
    final repository = FakeReportRepository()
      ..data = AttendanceReportData(
        employeeNames: const {'a': 'Nguyễn A'},
        employeeEmails: const {'a': 'a@example.com'},
        records: [record('a', '2026-10-12')],
      );
    final generator = FakePdfGenerator();
    final composer = FakeEmailComposer();
    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceReportScreen(
          profile: manager,
          repository: repository,
          pdfGenerator: generator,
          emailComposer: composer,
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
    await tester.tap(find.text('Gửi báo cáo qua email'));
    await tester.pumpAndSettle();
    expect(find.text('Không có quyền soạn email báo cáo.'), findsOneWidget);
    expect(generator.calls, 0);
    expect(composer.calls, 0);
    expect(find.text('Chia sẻ PDF thủ công'), findsNothing);
  });
}
