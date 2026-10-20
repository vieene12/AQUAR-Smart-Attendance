import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/payroll/domain/work_time_calculator.dart';

const calculator = WorkTimeCalculator();

void main() {
  test('đi muộn, về sớm và làm nửa ngày chỉ trừ phần trùng nghỉ trưa', () {
    expect(
      calculator.calculateDay(_day('2026-10-05', 9, 30, 18, 0)).fullMinutes,
      450,
    );
    expect(
      calculator.calculateDay(_day('2026-10-06', 8, 0, 12, 30)).fullMinutes,
      240,
    );
    expect(
      calculator.calculateDay(_day('2026-10-07', 12, 30, 16, 30)).fullMinutes,
      210,
    );
    expect(
      calculator.calculateDay(_day('2026-10-08', 8, 0, 11, 0)).fullMinutes,
      180,
    );
    expect(
      calculator.calculateDay(_day('2026-10-09', 13, 0, 17, 0)).fullMinutes,
      240,
    );
    expect(
      calculator.calculateDay(_day('2026-10-10', 12, 0, 13, 0)).fullMinutes,
      0,
    );
  });

  test(
    'bản ghi manual và bản ghi đã điều chỉnh vẫn tính khi completed hợp lệ',
    () {
      final manual = _day('2026-10-05', 8, 0, 17, 0, method: 'manual');
      final adjusted = _day('2026-10-06', 8, 30, 16, 30, method: 'nfc');
      expect(calculator.calculateDay(manual).fullMinutes, 480);
      expect(calculator.calculateDay(adjusted).fullMinutes, 420);
    },
  );

  test('thiếu giờ ra, chưa hoàn thành, giờ đảo, ca qua đêm và dữ liệu sai không tính', () {
    final valid = _day('2026-10-05', 8, 0, 17, 0);
    final invalid = [
      WorkAttendance(
        employeeUid: valid.employeeUid,
        workDate: valid.workDate,
        status: 'completed',
        method: valid.method,
        checkInAt: valid.checkInAt,
        checkOutAt: null,
      ),
      WorkAttendance(
        employeeUid: valid.employeeUid,
        workDate: valid.workDate,
        status: 'working',
        method: valid.method,
        checkInAt: valid.checkInAt,
        checkOutAt: valid.checkOutAt,
      ),
      _day('2026-10-06', 17, 0, 8, 0),
      WorkAttendance(
        employeeUid: 'employee-1',
        workDate: '2026-10-07',
        status: 'completed',
        method: 'manual',
        checkInAt: _instant('2026-10-07', 22, 0),
        checkOutAt: _instant('2026-10-08', 6, 0),
      ),
      WorkAttendance(
        employeeUid: 'employee-1',
        workDate: '2026-10-32',
        status: 'completed',
        method: 'manual',
        checkInAt: valid.checkInAt,
        checkOutAt: valid.checkOutAt,
      ),
      WorkAttendance(
        employeeUid: 'employee-1',
        workDate: '2026-10-05',
        status: 'completed',
        method: 'unknown',
        checkInAt: valid.checkInAt,
        checkOutAt: valid.checkOutAt,
      ),
      WorkAttendance(
        employeeUid: 'employee-1',
        workDate: '2026-10-06',
        status: 'completed',
        method: 'biometric',
        checkInAt: valid.checkInAt,
        checkOutAt: valid.checkOutAt,
      ),
    ];
    expect(invalid.map((entry) => calculator.calculateDay(entry).exclusion), [
      WorkExclusion.missingTime,
      WorkExclusion.incomplete,
      WorkExclusion.reversedTime,
      WorkExclusion.outsideWorkDate,
      WorkExclusion.invalidDate,
      WorkExclusion.invalidMethod,
      WorkExclusion.outsideWorkDate,
    ]);
    expect(
      invalid.every((entry) => !calculator.calculateDay(entry).isPayable),
      isTrue,
    );
  });

  test('tuần thứ Hai–Chủ Nhật, tháng và ranh giới năm theo ngày Việt Nam', () {
    final records = [
      _day('2026-10-04', 8, 0, 17, 0), // Sunday, preceding week.
      _day('2026-10-05', 8, 0, 17, 0), // Monday.
      _day('2026-10-11', 8, 0, 12, 0), // Sunday.
      _day('2026-10-12', 8, 0, 17, 0), // Following week.
      _day('2026-09-30', 8, 0, 17, 0),
      _day('2026-10-05', 8, 0, 17, 0, employeeUid: 'other'),
    ];
    final week = calculator.summarizeWeek(
      records,
      'employee-1',
      DateTime(2026, 10, 11),
    );
    expect(week.startDate, '2026-10-05');
    expect(week.endDate, '2026-10-11');
    expect(week.totalMinutes, 720);
    expect(week.payableDays, 2);

    final month = calculator.summarizeMonth(records, 'employee-1', 2026, 10);
    expect(month.startDate, '2026-10-01');
    expect(month.endDate, '2026-10-31');
    expect(month.totalMinutes, 1680);
    expect(month.payableDays, 4);

    final yearBoundary = calculator.summarizeWeek(
      [_day('2026-12-31', 8, 0, 17, 0), _day('2027-01-01', 8, 0, 17, 0)],
      'employee-1',
      DateTime(2027, 1, 1),
    );
    expect(yearBoundary.startDate, '2026-12-28');
    expect(yearBoundary.endDate, '2027-01-03');
    expect(yearBoundary.totalMinutes, 960);
  });

  test('bản ghi trùng ngày không được cộng hai lần', () {
    final sameDay = _day('2026-10-05', 8, 0, 17, 0);
    final week = calculator.summarizeWeek(
      [sameDay, sameDay, _day('2026-10-06', 8, 0, 12, 0)],
      'employee-1',
      DateTime(2026, 10, 5),
    );
    expect(week.totalMinutes, 240);
    expect(week.excludedRecords, 2);
    expect(week.days.first.exclusion, WorkExclusion.duplicateDate);
  });

  test('cộng thời lượng trước khi lấy phút, tính tiền số nguyên và làm tròn 0,5 lên', () {
    final halfMinuteDays = [
      _day('2026-10-05', 8, 0, 8, 0, outSecond: 30),
      _day('2026-10-06', 8, 0, 8, 0, outSecond: 30),
    ];
    final week = calculator.summarizeWeek(
      halfMinuteDays,
      'employee-1',
      DateTime(2026, 10, 5),
    );
    expect(week.days.map((day) => day.fullMinutes), [0, 0]);
    expect(week.totalMinutes, 1);
    expect(calculator.calculateSalaryVnd(2, 20), 1); // 40/60 VND, once.
    expect(calculator.calculateSalaryVnd(3, 10), 1); // Exactly 0.5 VND.
    expect(calculator.calculateSalaryVnd(week.totalMinutes, 120), 2);
    expect(calculator.calculateSalaryVnd(480, 30000), 240000);
  });

  test('hourlyRate thiếu, sai kiểu, âm bị từ chối; 0 hợp lệ', () {
    for (final rate in [null, '30000', 30000.5, -1]) {
      expect(
        () => calculator.calculateSalaryVnd(60, rate),
        throwsA(isA<InvalidHourlyRateException>()),
      );
    }
    expect(calculator.calculateSalaryVnd(60, 0), 0);
    expect(() => calculator.calculateSalaryVnd(-1, 30000), throwsArgumentError);
  });
}

WorkAttendance _day(
  String date,
  int inHour,
  int inMinute,
  int outHour,
  int outMinute, {
  int outSecond = 0,
  String method = 'biometric',
  String employeeUid = 'employee-1',
}) => WorkAttendance(
  employeeUid: employeeUid,
  workDate: date,
  status: 'completed',
  method: method,
  checkInAt: _instant(date, inHour, inMinute),
  checkOutAt: _instant(date, outHour, outMinute, outSecond),
);

DateTime _instant(String date, int hour, int minute, [int second = 0]) {
  final year = int.parse(date.substring(0, 4));
  final month = int.parse(date.substring(5, 7));
  final day = int.parse(date.substring(8, 10));
  return DateTime.utc(year, month, day, hour - 7, minute, second);
}
