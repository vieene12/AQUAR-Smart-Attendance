import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/payroll/domain/work_time_calculator.dart';
import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';

const service = AttendanceStatisticsService();

DateTime instant(String date, int hour, [int minute = 0, int second = 0]) {
  final parts = date.split('-').map(int.parse).toList();
  return DateTime.utc(parts[0], parts[1], parts[2], hour - 7, minute, second);
}

StatisticsAttendance entry(
  String uid,
  String date, {
  String status = 'completed',
  String method = 'biometric',
  int? revision,
  DateTime? checkIn,
  DateTime? checkOut,
  bool noCheckOut = false,
}) => StatisticsAttendance(
  WorkAttendance(
    employeeUid: uid,
    workDate: date,
    status: status,
    method: method,
    checkInAt: checkIn ?? instant(date, 8),
    checkOutAt: noCheckOut ? null : checkOut ?? instant(date, 17),
  ),
  manualRevision: revision,
);

void main() {
  test('tuần Việt Nam từ thứ Hai đến Chủ Nhật qua ranh giới năm', () {
    final period = AttendanceStatisticsPeriod.containing(
      AttendancePeriodKind.week,
      DateTime.utc(2026, 12, 27, 18), // 01:00 Monday in Vietnam.
    );
    expect(period.startDate, '2026-12-28');
    expect(period.endDate, '2027-01-03');
    final result = service.summarize([
      entry('a', '2026-12-27'),
      entry('a', '2026-12-28'),
      entry('a', '2027-01-03'),
      entry('a', '2027-01-04'),
    ], period);
    expect(result.enterprise.completedRecords, 2);
    expect(result.enterprise.totalMinutes, 960);
  });

  test('tháng, quý, năm chọn theo múi giờ Việt Nam', () {
    final selected = DateTime.utc(2026, 3, 31, 18); // 01:00 Apr 1 in Vietnam.
    final expected = {
      AttendancePeriodKind.month: ('2026-04-01', '2026-04-30', 1),
      AttendancePeriodKind.quarter: ('2026-04-01', '2026-06-30', 2),
      AttendancePeriodKind.year: ('2026-01-01', '2026-12-31', 4),
    };
    final records = [
      entry('a', '2026-03-31'),
      entry('a', '2026-04-01'),
      entry('a', '2026-06-30'),
      entry('a', '2026-07-01'),
    ];
    for (final item in expected.entries) {
      final period = AttendanceStatisticsPeriod.containing(item.key, selected);
      expect(
        (period.startDate, period.endDate),
        (item.value.$1, item.value.$2),
      );
      expect(
        service.summarize(records, period).enterprise.completedRecords,
        item.value.$3,
      );
    }
  });

  test(
    'doanh nghiệp và từng UID, trạng thái, phương thức và điều chỉnh manual',
    () {
      final period = AttendanceStatisticsPeriod.containing(
        AttendancePeriodKind.month,
        instant('2026-10-15', 12),
      );
      final result = service.summarize([
        entry('a', '2026-10-05'),
        entry(
          'a',
          '2026-10-06',
          method: 'nfc',
          revision: 1,
          checkIn: instant('2026-10-06', 9),
          checkOut: instant('2026-10-06', 17),
        ),
        entry(
          'a',
          '2026-10-07',
          status: 'working',
          method: 'nfc',
          noCheckOut: true,
        ),
        entry('b', '2026-10-05', method: 'manual', revision: 1),
      ], period);
      final all = result.enterprise;
      expect(all.completedRecords, 3);
      expect(all.workingRecords, 1);
      expect(all.totalMinutes, 480 + 420 + 480);
      expect(all.attendanceDays, 4);
      expect(
        (all.biometricRecords, all.nfcRecords, all.manualRecords),
        (1, 2, 1),
      );
      expect(all.manuallyAdjustedRecords, 2);
      expect(result.byEmployeeUid['a']!.attendanceDays, 3);
      expect(result.byEmployeeUid['a']!.totalMinutes, 900);
      expect(result.byEmployeeUid['b']!.totalMinutes, 480);
    },
  );

  test('bản sao không cộng trùng; bản ghi xung đột cùng ngày bị loại', () {
    final period = AttendanceStatisticsPeriod.containing(
      AttendancePeriodKind.week,
      instant('2026-10-05', 12),
    );
    final copy = entry('a', '2026-10-05');
    final conflicting = entry('a', '2026-10-06', method: 'nfc');
    final result = service.summarize([
      copy,
      copy,
      conflicting,
      entry(
        'a',
        '2026-10-06',
        status: 'working',
        method: 'nfc',
        noCheckOut: true,
      ),
      entry('b', '2026-10-05'),
    ], period);
    expect(result.enterprise.completedRecords, 2);
    expect(result.enterprise.workingRecords, 0);
    expect(result.enterprise.attendanceDays, 2);
    expect(result.enterprise.totalMinutes, 960);
    expect(result.enterprise.invalidRecords, 1);
    expect(result.byEmployeeUid['a']!.invalidRecords, 1);
  });

  test('thiếu dữ liệu, ngày sai và trạng thái không nhất quán không được tính công', () {
    final period = AttendanceStatisticsPeriod.containing(
      AttendancePeriodKind.month,
      instant('2026-10-15', 12),
    );
    final malformed = [
      entry('a', '2026-10-05', noCheckOut: true),
      entry('a', '2026-10-06', status: 'working'),
      entry('a', '2026-10-07', method: 'unknown'),
      entry('a', '2026-10-08', revision: -1),
      entry('a', '2026-10-09', checkOut: instant('2026-10-09', 7)),
      entry('a', '2026-10-10', checkIn: instant('2026-10-11', 8)),
      entry('a', '2026-10-32'),
      entry('', '2026-10-11'),
    ];
    final result = service.summarize(malformed, period);
    expect(result.enterprise.completedRecords, 0);
    expect(result.enterprise.workingRecords, 0);
    expect(result.enterprise.totalMinutes, 0);
    expect(result.enterprise.attendanceDays, 0);
    expect(result.enterprise.invalidRecords, 6);
    expect(service.summarize([], period).byEmployeeUid, isEmpty);
    expect(service.summarize([], period).enterprise.totalMinutes, 0);
  });

  test('cộng thời lượng trước khi lấy phút như WorkTimeCalculator', () {
    final period = AttendanceStatisticsPeriod.containing(
      AttendancePeriodKind.week,
      instant('2026-10-05', 12),
    );
    final result = service.summarize([
      entry('a', '2026-10-05', checkOut: instant('2026-10-05', 8, 0, 30)),
      entry('a', '2026-10-06', checkOut: instant('2026-10-06', 8, 0, 30)),
    ], period);
    expect(result.enterprise.totalMinutes, 1);
    expect(result.byEmployeeUid['a']!.totalMinutes, 1);
  });
}
