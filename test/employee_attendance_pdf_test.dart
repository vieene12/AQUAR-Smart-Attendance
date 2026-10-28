import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/payroll/domain/work_time_calculator.dart';
import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';
import 'package:smart_attendance/features/statistics/domain/employee_attendance_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final period = AttendanceStatisticsPeriod.containing(
    AttendancePeriodKind.week,
    DateTime.utc(2026, 10, 15, 12),
  );

  StatisticsAttendance record(
    String uid,
    String date, {
    bool working = false,
    String method = 'biometric',
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
    );
  }

  test(
    'tạo PDF tiếng Việt từ font asset và chỉ dữ liệu nhân viên đã chọn',
    () async {
      final font = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final report = await const EmployeeAttendancePdfGenerator().generate(
        employeeUid: 'employee-a',
        employeeName: 'Nguyễn Văn A',
        employeeEmail: 'a@example.com',
        period: period,
        records: [
          record('employee-a', '2026-10-12'),
          record('employee-a', '2026-10-13', working: true),
          record('employee-b', '2026-10-14'),
        ],
        exportedAt: DateTime.utc(2026, 10, 15, 12),
        fontData: font,
      );
      expect(report.bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(report.bytes.take(5)), '%PDF-');
      expect(
        report.fileName,
        startsWith('bao_cao_cham_cong_week_2026-10-12_2026-10-18_'),
      );
      expect(report.fileName, endsWith('.pdf'));
      expect(report.fileName, isNot(contains('employee-a')));
      expect(report.fileName, isNot(contains('Nguyễn')));
    },
  );

  test('không tạo PDF khi không có ngày hợp lệ hoặc font thiếu', () async {
    final font = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final generator = const EmployeeAttendancePdfGenerator();
    expect(
      () => generator.generate(
        employeeUid: 'employee-a',
        employeeName: 'A',
        employeeEmail: '',
        period: period,
        records: [record('employee-b', '2026-10-12')],
        exportedAt: DateTime.utc(2026, 10, 15),
        fontData: font,
      ),
      throwsA(isA<EmptyEmployeePdfException>()),
    );
    expect(
      () => generator.generate(
        employeeUid: 'employee-a',
        employeeName: 'A',
        employeeEmail: '',
        period: period,
        records: [record('employee-a', '2026-10-12')],
        exportedAt: DateTime.utc(2026, 10, 15),
        fontData: ByteData(0),
      ),
      throwsA(isA<EmployeePdfFontException>()),
    );
  });

  test('tạo PDF cho kỳ chỉ có chấm công NFC mobile', () async {
    final font = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final report = await const EmployeeAttendancePdfGenerator().generate(
      employeeUid: 'employee-a',
      employeeName: 'Nguyễn Văn A',
      employeeEmail: 'a@example.com',
      period: period,
      records: [record('employee-a', '2026-10-12', method: 'nfc_mobile')],
      exportedAt: DateTime.utc(2026, 10, 15, 12),
      fontData: font,
    );

    expect(report.bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(report.bytes.take(5)), '%PDF-');
  });
}
