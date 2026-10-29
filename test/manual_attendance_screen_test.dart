import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/home/presentation/role_home_screens.dart';
import 'package:smart_attendance/features/manual_attendance/data/manual_attendance_repository.dart';
import 'package:smart_attendance/features/manual_attendance/data/manual_attendance_writer.dart';
import 'package:smart_attendance/features/manual_attendance/presentation/manual_attendance_screen.dart';

const _manager = UserProfile(
  uid: 'manager-1',
  displayName: 'Quản lý',
  role: UserRole.manager,
);
final _date = DateTime(2026, 10, 11);

void main() {
  testWidgets('Manager mở mục Chấm công thủ công từ trang chủ', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ManagerHomeScreen(
          profile: _manager,
          onSignOut: () {},
          manualAttendanceRepository: _FakeRepository(),
        ),
      ),
    );
    expect(find.text('Nhân viên phụ trách'), findsNothing);
    await tester.ensureVisible(find.text('Chấm công thủ công'));
    await tester.tap(find.text('Chấm công thủ công'));
    await tester.pumpAndSettle();
    expect(find.byType(ManualAttendanceScreen), findsOneWidget);
  });

  testWidgets('tìm tên và xem giờ, trạng thái, phương thức của bản ghi', (
    tester,
  ) async {
    final repository = _FakeRepository()
      ..record = ManualAttendanceRecord(
        checkInAt: DateTime.utc(2026, 10, 11, 2, 15),
        checkOutAt: DateTime.utc(2026, 10, 11, 10, 30),
        status: 'completed',
        method: 'nfc_mobile',
        checkOutMethod: 'nfc_mobile',
      );
    await _pumpScreen(tester, repository);
    await tester.enterText(find.byType(TextField).first, 'nguyễn');
    await tester.pump();
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('Trần Văn B'), findsNothing);
    await tester.tap(find.text('Nguyễn Văn A'));
    await tester.pumpAndSettle();
    expect(repository.lastEmployee, 'employee-1');
    expect(repository.lastDate, _date);
    expect(find.text('Trạng thái: Đã kết thúc'), findsOneWidget);
    expect(find.text('Check-in: 09:15'), findsOneWidget);
    expect(find.text('Check-out: 17:30'), findsOneWidget);
    expect(
      find.text('Phương thức vào: Thẻ NFC trên điện thoại'),
      findsOneWidget,
    );
    expect(
      find.text('Phương thức ra: Thẻ NFC trên điện thoại'),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Lý do điều chỉnh'), findsOneWidget);
    expect(find.text('Lưu chấm công'), findsOneWidget);
  });

  testWidgets('ngày chưa có bản ghi vẫn nhập được form', (tester) async {
    final repository = _FakeRepository();
    await _pumpScreen(tester, repository);
    await tester.tap(find.text('Nguyễn Văn A'));
    await tester.pumpAndSettle();
    expect(find.text('Trạng thái: Chưa có bản ghi'), findsOneWidget);
    expect(find.text('Check-in: Chưa có'), findsOneWidget);
    expect(find.text('Check-out: Chưa có'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Giờ vào (HH:mm)').first,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Giờ vào (HH:mm)'),
      '08:30',
    );
    await tester.scrollUntilVisible(
      find.text('Giờ ra (HH:mm)').first,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Giờ ra (HH:mm)'),
      '17:00',
    );
    await tester.scrollUntilVisible(
      find.text('Lý do điều chỉnh').first,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Lý do điều chỉnh'),
      'Quên quét thẻ',
    );
    expect(repository.loadCalls, 1);
    expect(find.text('Quên quét thẻ'), findsOneWidget);
    expect(find.text('Lưu chấm công'), findsOneWidget);
  });

  testWidgets(
    'ô giờ mở bộ chọn thời gian trên bàn phím không có dấu hai chấm',
    (tester) async {
      await _pumpScreen(tester, _FakeRepository());
      await tester.tap(find.text('Nguyễn Văn A'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('Chọn giờ vào'),
        150,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.byTooltip('Chọn giờ vào'));
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(find.text('Chọn giờ vào'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('thiếu Check-out hiện giờ ra trống và phương thức manual', (
    tester,
  ) async {
    final repository = _FakeRepository()
      ..record = ManualAttendanceRecord(
        checkInAt: DateTime.utc(2026, 10, 11, 1),
        status: 'working',
        method: 'manual',
      );
    await _pumpScreen(tester, repository);
    await tester.tap(find.text('Nguyễn Văn A'));
    await tester.pumpAndSettle();
    expect(find.text('Trạng thái: Đang làm việc'), findsOneWidget);
    expect(find.text('Check-out: Chưa có'), findsOneWidget);
    expect(find.text('Phương thức vào: Thủ công (manual)'), findsOneWidget);
    expect(find.text('Phương thức ra: Chưa có'), findsOneWidget);
  });

  testWidgets('đổi ngày tải lại bản ghi đúng ngày được chọn', (tester) async {
    final repository = _FakeRepository();
    await _pumpScreen(tester, repository);
    await tester.tap(find.text('Nguyễn Văn A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ngày: 11/10/2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(repository.lastDate, DateTime(2026, 10, 12));
    expect(repository.loadCalls, 2);
    expect(find.text('Ngày: 12/10/2026'), findsOneWidget);
  });

  testWidgets('loading, danh sách rỗng và lỗi mạng có thử lại', (tester) async {
    final pending = Completer<List<ManualEmployee>>();
    final repository = _FakeRepository()..employeeResult = pending.future;
    await _pumpScreen(tester, repository, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('Chưa có nhân viên.'), findsOneWidget);
    repository.employeeError = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpScreen(tester, repository);
    expect(find.textContaining('Không thể kết nối Firestore'), findsOneWidget);
    repository.employeeError = null;
    repository.employeeResult = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
  });

  testWidgets('lỗi quyền khi đọc bản ghi có thông báo và thử lại', (
    tester,
  ) async {
    final repository = _FakeRepository()
      ..recordError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    await _pumpScreen(tester, repository);
    await tester.tap(find.text('Nguyễn Văn A'));
    await tester.pumpAndSettle();
    expect(find.text('Không có quyền đọc dữ liệu chấm công.'), findsOneWidget);
    expect(find.text('Thử lại bản ghi'), findsOneWidget);
    repository.recordError = null;
    await tester.tap(find.text('Thử lại bản ghi'));
    await tester.pumpAndSettle();
    expect(find.text('Trạng thái: Chưa có bản ghi'), findsOneWidget);
  });

  testWidgets('Employee và Manager không active bị từ chối', (tester) async {
    final employeeRepository = _FakeRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualAttendanceScreen(
          profile: const UserProfile(
            uid: 'employee-1',
            displayName: 'Nhân viên',
            role: UserRole.employee,
          ),
          repository: employeeRepository,
          initialDate: _date,
        ),
      ),
    );
    expect(
      find.text('Bạn không có quyền xem chấm công thủ công.'),
      findsOneWidget,
    );
    expect(employeeRepository.accessCalls, 0);

    final locked = _FakeRepository()..allowed = false;
    await _pumpScreen(tester, locked);
    expect(
      find.text('Bạn không có quyền xem chấm công thủ công.'),
      findsOneWidget,
    );
    expect(locked.employeeCalls, 0);
  });

  testWidgets('lưu cần lý do, khóa nhấn lặp và tải lại sau khi ghi', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final pending = Completer<void>();
    final writer = _FakeWriter()
      ..onSave = (change) async {
        await pending.future;
        repository.record = ManualAttendanceRecord(
          checkInAt: change.checkInAt,
          checkOutAt: change.checkOutAt,
          method: 'manual',
          status: 'working',
          manualRevision: 1,
        );
      };
    await _pumpScreen(tester, repository, writer: writer);
    await tester.tap(find.text('Nguyễn Văn A'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Giờ vào (HH:mm)'),
      '08:30',
    );
    await tester.ensureVisible(find.text('Lưu chấm công'));
    await tester.tap(find.text('Lưu chấm công'));
    await tester.pump();
    expect(find.textContaining('Nhập lý do điều chỉnh'), findsOneWidget);
    expect(writer.calls, 0);

    await tester.enterText(
      find.widgetWithText(TextField, 'Lý do điều chỉnh'),
      'Quên chấm công',
    );
    await tester.ensureVisible(find.text('Lưu chấm công'));
    await tester.tap(find.text('Lưu chấm công'));
    await tester.pump();
    expect(writer.calls, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Lưu chấm công'),
          )
          .onPressed,
      isNull,
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(repository.loadCalls, 2);
    expect(find.text('Đã lưu chấm công và tải lại bản ghi.'), findsOneWidget);
    expect(find.text('Trạng thái: Đang làm việc'), findsOneWidget);
  });

  testWidgets('lỗi quyền khi lưu không báo thành công', (tester) async {
    final writer = _FakeWriter()
      ..error = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    await _pumpScreen(tester, _FakeRepository(), writer: writer);
    await tester.tap(find.text('Nguyễn Văn A'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Giờ vào (HH:mm)'),
      '08:30',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Lý do điều chỉnh'),
      'Quên chấm công',
    );
    await tester.ensureVisible(find.text('Lưu chấm công'));
    await tester.tap(find.text('Lưu chấm công'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không có quyền lưu chấm công'), findsOneWidget);
    expect(find.textContaining('Đã lưu chấm công'), findsNothing);
  });

  testWidgets('bổ sung giờ ra không làm tròn giây của giờ vào gốc', (
    tester,
  ) async {
    final original = DateTime.utc(2026, 10, 11, 1, 15, 42);
    final repository = _FakeRepository()
      ..record = ManualAttendanceRecord(
        checkInAt: original,
        status: 'working',
        method: 'biometric',
      );
    final writer = _FakeWriter();
    await _pumpScreen(tester, repository, writer: writer);
    await tester.tap(find.text('Nguyễn Văn A'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Giờ ra (HH:mm)'),
      '17:00',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Lý do điều chỉnh'),
      'Bổ sung giờ ra',
    );
    await tester.ensureVisible(find.text('Lưu chấm công'));
    await tester.tap(find.text('Lưu chấm công'));
    await tester.pumpAndSettle();
    expect(writer.lastChange?.checkInAt, original);
    expect(writer.lastChange?.checkOutAt, DateTime.utc(2026, 10, 11, 10));
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeRepository repository, {
  bool settle = true,
  ManualAttendanceWriter? writer,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ManualAttendanceScreen(
        profile: _manager,
        repository: repository,
        writer: writer,
        initialDate: _date,
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

class _FakeWriter implements ManualAttendanceWriter {
  Future<void> Function(ManualAttendanceChange)? onSave;
  Object? error;
  int calls = 0;
  ManualAttendanceChange? lastChange;

  @override
  Future<void> save(ManualAttendanceChange change) async {
    calls++;
    lastChange = change;
    if (error != null) throw error!;
    if (onSave != null) await onSave!(change);
  }
}

class _FakeRepository implements ManualAttendanceRepository {
  bool allowed = true;
  int accessCalls = 0;
  int employeeCalls = 0;
  int loadCalls = 0;
  String? lastEmployee;
  DateTime? lastDate;
  Future<List<ManualEmployee>>? employeeResult;
  Object? employeeError;
  ManualAttendanceRecord? record;
  Object? recordError;

  @override
  Future<bool> canAccess(UserProfile profile) async {
    accessCalls++;
    return allowed;
  }

  @override
  Future<List<ManualEmployee>> loadEmployees() {
    employeeCalls++;
    if (employeeError != null) return Future.error(employeeError!);
    return employeeResult ??
        Future.value(const [
          ManualEmployee(uid: 'employee-1', name: 'Nguyễn Văn A'),
          ManualEmployee(uid: 'employee-2', name: 'Trần Văn B'),
        ]);
  }

  @override
  Future<ManualAttendanceRecord?> loadRecord(
    String employeeUid,
    DateTime date,
  ) async {
    loadCalls++;
    lastEmployee = employeeUid;
    lastDate = date;
    if (recordError != null) throw recordError!;
    return record;
  }
}
