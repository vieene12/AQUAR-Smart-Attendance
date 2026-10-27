import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/statistics/data/report_dispatch_repository.dart';
import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';
import 'package:smart_attendance/features/statistics/presentation/report_dispatch_screen.dart';
import 'package:smart_attendance/features/home/presentation/role_home_screens.dart';

const admin = UserProfile(
  uid: 'admin',
  displayName: 'Admin',
  role: UserRole.admin,
);
const recipients = [
  ReportRecipient(
    uid: 'a',
    name: 'Nguyễn Văn A',
    code: 'NV001',
    email: 'a@example.com',
  ),
  ReportRecipient(
    uid: 'b',
    name: 'Trần Văn B',
    code: 'NV002',
    email: 'b@example.com',
  ),
  ReportRecipient(uid: 'c', name: 'Lê Văn C', code: 'NV003'),
];

class FakeRepository implements ReportDispatchRepository {
  FakeRepository({this.people = recipients, this.missingRate = false});
  final List<ReportRecipient> people;
  final bool missingRate;
  List<ReportRecipient> lastSent = const [];
  int previews = 0;
  int exports = 0;

  @override
  Future<ReportEmployeeDetail> detail({
    required String employeeUid,
    required AttendancePeriodKind kind,
    required DateTime date,
  }) async => ReportEmployeeDetail({
    'name': 'Nguyễn Văn A',
    'employeeCode': 'NV001',
    'startDate': '2026-10-01',
    'endDate': '2026-10-31',
    'hourlyRate': missingRate ? null : 60000,
    'totalMinutes': 475,
    'totalSalary': missingRate ? null : 475000,
    'payableDays': 1,
    'days': [
      {
        'workDate': '2026-10-26',
        'checkIn': '08:05',
        'checkOut': 'Chưa check-out',
        'paidMinutes': null,
        'status': 'Đang làm việc',
      },
    ],
  });

  @override
  Future<ReportExportResult> export({
    required List<ReportRecipient> recipients,
    required AttendancePeriodKind kind,
    required DateTime date,
    required void Function(int done, int total) onProgress,
  }) async {
    exports++;
    onProgress(recipients.length, recipients.length);
    return ReportExportResult(
      fileName: 'BaoCao.zip',
      bytes: Uint8List.fromList([80, 75, 3, 4]),
      failures: const [],
    );
  }

  @override
  Future<List<ReportRecipient>> listRecipients(UserProfile profile) async =>
      people;

  @override
  Future<ReportPdf> preview({
    required String employeeUid,
    required AttendancePeriodKind kind,
    required DateTime date,
  }) async {
    previews++;
    return ReportPdf(fileName: 'test.pdf', bytes: Uint8List(0));
  }

  @override
  Future<List<ReportSendResult>> send({
    required List<ReportRecipient> recipients,
    required AttendancePeriodKind kind,
    required DateTime date,
    void Function(int done, int total)? onProgress,
  }) async {
    lastSent = recipients;
    onProgress?.call(recipients.length, recipients.length);
    return [
      for (final person in recipients)
        ReportSendResult(
          uid: person.uid,
          name: person.name,
          success: person.uid != 'c',
          message: person.uid == 'c'
              ? 'Nhân viên chưa đăng ký email.'
              : 'Thành công',
        ),
    ];
  }
}

class FakeFileExporter extends ReportFileExporter {
  int saves = 0;
  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    saves++;
    return true;
  }
}

class CountingObserver extends NavigatorObserver {
  int pushes = 0;
  final pushedRoutes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    pushedRoutes.add(route);
    super.didPush(route, previousRoute);
  }
}

void main() {
  testWidgets('Admin và Quản lý mở mục Gửi email thật từ trang chủ', (
    tester,
  ) async {
    for (final profile in [
      admin,
      const UserProfile(
        uid: 'manager',
        displayName: 'Quản lý',
        role: UserRole.manager,
      ),
    ]) {
      final repository = FakeRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: profile.role == UserRole.admin
              ? AdminHomeScreen(
                  profile: profile,
                  onSignOut: () {},
                  reportDispatchRepository: repository,
                )
              : ManagerHomeScreen(
                  profile: profile,
                  onSignOut: () {},
                  reportDispatchRepository: repository,
                ),
        ),
      );
      await tester.ensureVisible(
        find.text('Gửi báo cáo chấm công và bảng lương'),
      );
      await tester.tap(find.text('Gửi báo cáo chấm công và bảng lương'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportDispatchScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('chọn một, nhiều, tất cả và hiện kết quả từng nhân viên', (
    tester,
  ) async {
    final repository = FakeRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ReportDispatchScreen(profile: admin, repository: repository),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Đã chọn: 0 nhân viên'), findsOneWidget);
    await tester.tap(find.text('Chọn tất cả'));
    await tester.pump();
    expect(find.text('Đã chọn: 3 nhân viên'), findsOneWidget);
    await tester.tap(find.text('Gửi email'));
    await tester.pump();
    await tester.pump();
    expect(repository.lastSent.map((person) => person.uid), ['a', 'b', 'c']);
    expect(find.text('Đã gửi thành công 2/3 nhân viên'), findsOneWidget);
    expect(
      find.text('Lê Văn C – Nhân viên chưa đăng ký email.'),
      findsOneWidget,
    );
  });

  testWidgets('chỉ một nhân viên có xem chi tiết; chọn nhiều vẫn ở một route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: ReportDispatchScreen(
          profile: admin,
          repository: FakeRepository(),
          initialEmployeeUid: 'a',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Đã chọn: 1 nhân viên'), findsOneWidget);
    expect(find.text('Xem chi tiết'), findsOneWidget);
    await tester.tap(find.text('Chọn tất cả'));
    await tester.pump();
    expect(find.text('Xem chi tiết'), findsNothing);
    expect(find.byType(ReportDispatchScreen), findsOneWidget);
    expect(find.byType(Navigator), findsOneWidget);
  });

  testWidgets(
    'xuất nhiều nhân viên chỉ lưu một ZIP và không mở từng màn hình',
    (tester) async {
      final repository = FakeRepository();
      final exporter = FakeFileExporter();
      await tester.pumpWidget(
        MaterialApp(
          home: ReportDispatchScreen(
            profile: admin,
            repository: repository,
            fileExporter: exporter,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Chọn tất cả'));
      await tester.pump();
      await tester.tap(find.text('Xuất file'));
      await tester.pump();
      await tester.pump();
      expect(repository.exports, 1);
      expect(exporter.saves, 1);
      expect(find.byType(ReportDispatchScreen), findsOneWidget);
    },
  );

  testWidgets('chọn 100 nhân viên, gửi và xuất không tạo route nhân viên', (tester) async {
    final people = [
      for (var i = 0; i < 100; i++)
        ReportRecipient(uid: 'e$i', name: 'Nhân viên $i', code: 'NV$i'),
    ];
    final repository = FakeRepository(people: people);
    final observer = CountingObserver();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: ReportDispatchScreen(
        profile: admin, repository: repository, fileExporter: FakeFileExporter(),
      ),
    ));
    await tester.pump();
    await tester.pump();
    final initialPushes = observer.pushes;
    await tester.tap(find.text('Chọn tất cả'));
    await tester.pump();
    expect(find.text('Đã chọn: 100 nhân viên'), findsOneWidget);
    await tester.tap(find.text('Xuất file'));
    await tester.pump();
    await tester.pump();
    expect(observer.pushes, initialPushes);
    await tester.tap(find.text('Gửi email'));
    await tester.pump();
    await tester.pump();
    expect(observer.pushes, initialPushes + 1);
    expect(observer.pushedRoutes.last, isA<DialogRoute<dynamic>>());
  });

  testWidgets('chi tiết một nhân viên hiển thị bảng lương và chưa check-out', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReportDispatchScreen(
          profile: admin,
          repository: FakeRepository(),
          initialEmployeeUid: 'a',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Xem chi tiết'));
    await tester.pumpAndSettle();
    expect(find.text('Check-out: Chưa check-out'), findsOneWidget);
    await tester.tap(find.text('Bảng lương'));
    await tester.pumpAndSettle();
    expect(find.text('Đơn giá giờ: 60.000 ₫'), findsOneWidget);
    expect(find.text('Tổng lương: 475.000 ₫'), findsOneWidget);
  });

  testWidgets('thiếu hourlyRate hiển thị rõ thay vì số tiền giả', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReportDispatchScreen(
      profile: admin,
      repository: FakeRepository(missingRate: true),
      initialEmployeeUid: 'a',
    )));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Xem chi tiết'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bảng lương'));
    await tester.pumpAndSettle();
    expect(find.text('Đơn giá giờ: Chưa thiết lập đơn giá giờ'), findsOneWidget);
    expect(find.text('Tổng lương: Chưa thiết lập đơn giá giờ'), findsOneWidget);
  });
}
