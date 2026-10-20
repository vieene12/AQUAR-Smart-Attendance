/// Pure Dart payroll calculations. Calendar dates and lunch are interpreted in
/// Vietnam time (UTC+07:00), regardless of the device time zone.
class WorkAttendance {
  const WorkAttendance({
    required this.employeeUid,
    required this.workDate,
    required this.status,
    required this.method,
    required this.checkInAt,
    required this.checkOutAt,
  });

  final String employeeUid;
  final String? workDate;
  final String? status;
  final String? method;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
}

enum WorkExclusion {
  invalidDate,
  incomplete,
  invalidMethod,
  missingTime,
  reversedTime,
  outsideWorkDate,
  duplicateDate,
}

class WorkDayResult {
  const WorkDayResult._(this.attendance, this.paidDuration, this.exclusion);

  final WorkAttendance attendance;
  final Duration? paidDuration;
  final WorkExclusion? exclusion;

  bool get isPayable => paidDuration != null;

  /// Full minutes for display. Period totals floor only after adding durations.
  int get fullMinutes => paidDuration?.inMinutes ?? 0;
}

class WorkPeriodSummary {
  const WorkPeriodSummary({
    required this.startDate,
    required this.endDate,
    required this.days,
  });

  final String startDate;
  final String endDate;
  final List<WorkDayResult> days;

  Duration get totalDuration => days.fold(
    Duration.zero,
    (sum, day) => sum + (day.paidDuration ?? Duration.zero),
  );

  /// Floors subminute time once for the whole period.
  int get totalMinutes => totalDuration.inMinutes;
  int get payableDays => days.where((day) => day.isPayable).length;
  int get excludedRecords => days.where((day) => !day.isPayable).length;
}

class InvalidHourlyRateException implements Exception {
  const InvalidHourlyRateException();
}

class WorkTimeCalculator {
  const WorkTimeCalculator();

  WorkDayResult calculateDay(WorkAttendance attendance) {
    final date = _parseWorkDate(attendance.workDate);
    if (date == null) {
      return WorkDayResult._(attendance, null, WorkExclusion.invalidDate);
    }
    if (attendance.status != 'completed') {
      return WorkDayResult._(attendance, null, WorkExclusion.incomplete);
    }
    if (!const {'biometric', 'nfc', 'manual'}.contains(attendance.method)) {
      return WorkDayResult._(attendance, null, WorkExclusion.invalidMethod);
    }
    final checkIn = attendance.checkInAt;
    final checkOut = attendance.checkOutAt;
    if (checkIn == null || checkOut == null) {
      return WorkDayResult._(attendance, null, WorkExclusion.missingTime);
    }
    if (!checkOut.isAfter(checkIn)) {
      return WorkDayResult._(attendance, null, WorkExclusion.reversedTime);
    }
    if (_vietnamWorkDate(checkIn) != attendance.workDate ||
        _vietnamWorkDate(checkOut) != attendance.workDate) {
      return WorkDayResult._(attendance, null, WorkExclusion.outsideWorkDate);
    }

    // 12:00–13:00 in Vietnam is 05:00–06:00 UTC on the same calendar date.
    final lunchStart = DateTime.utc(date.year, date.month, date.day, 5);
    final lunchEnd = DateTime.utc(date.year, date.month, date.day, 6);
    final overlapStart = checkIn.isAfter(lunchStart) ? checkIn : lunchStart;
    final overlapEnd = checkOut.isBefore(lunchEnd) ? checkOut : lunchEnd;
    final lunchOverlap = overlapEnd.isAfter(overlapStart)
        ? overlapEnd.difference(overlapStart)
        : Duration.zero;
    return WorkDayResult._(
      attendance,
      checkOut.difference(checkIn) - lunchOverlap,
      null,
    );
  }

  /// [vietnamCalendarDate] is a calendar selection: only its year/month/day
  /// are used. A week runs from Monday through Sunday in Vietnam.
  WorkPeriodSummary summarizeWeek(
    Iterable<WorkAttendance> records,
    String employeeUid,
    DateTime vietnamCalendarDate,
  ) {
    final date = DateTime.utc(
      vietnamCalendarDate.year,
      vietnamCalendarDate.month,
      vietnamCalendarDate.day,
    );
    final monday = date.subtract(
      Duration(days: date.weekday - DateTime.monday),
    );
    return _summarize(
      records,
      employeeUid,
      monday,
      monday.add(const Duration(days: 6)),
    );
  }

  WorkPeriodSummary summarizeMonth(
    Iterable<WorkAttendance> records,
    String employeeUid,
    int year,
    int month,
  ) {
    if (year < 1 || month < 1 || month > 12) {
      throw ArgumentError('Tháng/năm không hợp lệ.');
    }
    return _summarize(
      records,
      employeeUid,
      DateTime.utc(year, month),
      DateTime.utc(year, month + 1, 0),
    );
  }

  /// Returns whole VND, rounded half up (0.5 VND rounds to 1 VND). A missing,
  /// non-integer, or negative hourly rate is rejected rather than treated as 0.
  /// Zero is a valid configured rate.
  int calculateSalaryVnd(int totalMinutes, Object? hourlyRate) {
    if (hourlyRate is! int || hourlyRate < 0) {
      throw const InvalidHourlyRateException();
    }
    if (totalMinutes < 0) {
      throw ArgumentError.value(totalMinutes, 'totalMinutes');
    }
    final numerator = BigInt.from(totalMinutes) * BigInt.from(hourlyRate);
    final salary = (numerator + BigInt.from(30)) ~/ BigInt.from(60);
    if (salary > BigInt.from(0x7fffffffffffffff)) {
      throw RangeError('Tiền lương vượt giới hạn số nguyên.');
    }
    return salary.toInt();
  }

  WorkPeriodSummary _summarize(
    Iterable<WorkAttendance> records,
    String employeeUid,
    DateTime start,
    DateTime end,
  ) {
    final grouped = <String, List<WorkAttendance>>{};
    for (final record in records) {
      if (record.employeeUid != employeeUid) continue;
      final date = _parseWorkDate(record.workDate);
      if (date == null || date.isBefore(start) || date.isAfter(end)) continue;
      grouped.putIfAbsent(record.workDate!, () => []).add(record);
    }
    final results = <WorkDayResult>[];
    for (final date in grouped.keys.toList()..sort()) {
      final entries = grouped[date]!;
      if (entries.length > 1) {
        results.addAll(
          entries.map(
            (entry) =>
                WorkDayResult._(entry, null, WorkExclusion.duplicateDate),
          ),
        );
      } else {
        results.add(calculateDay(entries.single));
      }
    }
    return WorkPeriodSummary(
      startDate: _formatDate(start),
      endDate: _formatDate(end),
      days: List.unmodifiable(results),
    );
  }

  DateTime? _parseWorkDate(String? value) {
    if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(5, 7));
    final day = int.parse(value.substring(8, 10));
    if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  String _vietnamWorkDate(DateTime instant) =>
      _formatDate(instant.toUtc().add(const Duration(hours: 7)));

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
