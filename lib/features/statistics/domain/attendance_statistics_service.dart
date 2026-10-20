import 'package:smart_attendance/features/payroll/domain/work_time_calculator.dart';

enum AttendancePeriodKind { week, month, quarter, year }

/// A selected instant determines its period using Vietnam time (UTC+07:00).
class AttendanceStatisticsPeriod {
  AttendanceStatisticsPeriod.containing(this.kind, DateTime instant)
    : _vietnamDate = instant.toUtc().add(const Duration(hours: 7));

  final AttendancePeriodKind kind;
  final DateTime _vietnamDate;

  late final DateTime start = _start();
  late final DateTime end = _end();

  String get startDate => _format(start);
  String get endDate => _format(end);

  bool contains(String date) =>
      date.compareTo(startDate) >= 0 && date.compareTo(endDate) <= 0;

  DateTime _start() {
    final day = DateTime.utc(
      _vietnamDate.year,
      _vietnamDate.month,
      _vietnamDate.day,
    );
    return switch (kind) {
      AttendancePeriodKind.week => day.subtract(
        Duration(days: day.weekday - DateTime.monday),
      ),
      AttendancePeriodKind.month => DateTime.utc(day.year, day.month),
      AttendancePeriodKind.quarter => DateTime.utc(
        day.year,
        ((day.month - 1) ~/ 3) * 3 + 1,
      ),
      AttendancePeriodKind.year => DateTime.utc(day.year),
    };
  }

  DateTime _end() => switch (kind) {
    AttendancePeriodKind.week => start.add(const Duration(days: 6)),
    AttendancePeriodKind.month => DateTime.utc(start.year, start.month + 1, 0),
    AttendancePeriodKind.quarter => DateTime.utc(
      start.year,
      start.month + 3,
      0,
    ),
    AttendancePeriodKind.year => DateTime.utc(start.year, 12, 31),
  };

  static String _format(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// [manualRevision] is the current attendance document's manualRevision field.
/// A manually created record has method `manual` and a positive revision.
class StatisticsAttendance {
  const StatisticsAttendance(this.attendance, {this.manualRevision});

  final WorkAttendance attendance;
  final int? manualRevision;
}

class AttendanceStatistics {
  const AttendanceStatistics({
    required this.completedRecords,
    required this.workingRecords,
    required this.totalMinutes,
    required this.attendanceDays,
    required this.biometricRecords,
    required this.nfcRecords,
    required this.manualRecords,
    required this.manuallyAdjustedRecords,
    required this.invalidRecords,
  });

  final int completedRecords;
  final int workingRecords;
  final int totalMinutes;
  final int attendanceDays;
  final int biometricRecords;
  final int nfcRecords;
  final int manualRecords;
  final int manuallyAdjustedRecords;
  final int invalidRecords;
}

class AttendanceStatisticsResult {
  const AttendanceStatisticsResult({
    required this.period,
    required this.enterprise,
    required this.byEmployeeUid,
  });

  final AttendanceStatisticsPeriod period;
  final AttendanceStatistics enterprise;
  final Map<String, AttendanceStatistics> byEmployeeUid;
}

/// Computes statistics from current attendance documents, without reading or
/// writing a database. Missing dates/UIDs cannot be assigned to a period and
/// are ignored; malformed records with a valid UID/date count as invalid.
class AttendanceStatisticsService {
  const AttendanceStatisticsService();

  static const _calculator = WorkTimeCalculator();

  AttendanceStatisticsResult summarize(
    Iterable<StatisticsAttendance> records,
    AttendanceStatisticsPeriod period,
  ) {
    final byDay = <String, List<StatisticsAttendance>>{};
    for (final record in records) {
      final attendance = record.attendance;
      final date = attendance.workDate;
      if (attendance.employeeUid.isEmpty ||
          date == null ||
          !_validDate(date) ||
          !period.contains(date)) {
        continue;
      }
      byDay
          .putIfAbsent('${attendance.employeeUid}\u0000$date', () => [])
          .add(record);
    }

    final accumulators = <String, _Accumulator>{};
    final enterprise = _Accumulator();
    for (final entries in byDay.values) {
      final uid = entries.first.attendance.employeeUid;
      final employee = accumulators.putIfAbsent(uid, _Accumulator.new);
      // An identical repeated input is one document. Conflicting versions of
      // the same employee/day are ambiguous and contribute no work or method.
      final unique = <StatisticsAttendance>[];
      for (final entry in entries) {
        if (!unique.any((other) => _sameRecord(other, entry))) {
          unique.add(entry);
        }
      }
      if (unique.length != 1) {
        employee.invalidRecords++;
        enterprise.invalidRecords++;
        continue;
      }
      final record = unique.single;
      final attendance = record.attendance;
      final validRevision =
          record.manualRevision == null || record.manualRevision! > 0;
      final method = attendance.method;
      final validMethod =
          method == 'biometric' || method == 'nfc' || method == 'manual';
      final checkIn = attendance.checkInAt;
      final validCheckIn =
          checkIn != null &&
          AttendanceStatisticsPeriod._format(
                checkIn.toUtc().add(const Duration(hours: 7)),
              ) ==
              attendance.workDate;
      final completed = attendance.status == 'completed'
          ? _calculator.calculateDay(attendance)
          : null;
      final isCompleted = validRevision && completed?.isPayable == true;
      final isWorking =
          validRevision &&
          attendance.status == 'working' &&
          validMethod &&
          validCheckIn &&
          attendance.checkOutAt == null;
      if (!isCompleted && !isWorking) {
        employee.invalidRecords++;
        enterprise.invalidRecords++;
        continue;
      }
      for (final target in [employee, enterprise]) {
        target.attendanceDays++;
        if (isCompleted) {
          target.completedRecords++;
          target.duration += completed!.paidDuration!;
        } else {
          target.workingRecords++;
        }
        switch (method) {
          case 'biometric':
            target.biometricRecords++;
          case 'nfc':
            target.nfcRecords++;
          case 'manual':
            target.manualRecords++;
        }
        if (record.manualRevision != null) target.manuallyAdjustedRecords++;
      }
    }

    return AttendanceStatisticsResult(
      period: period,
      enterprise: enterprise.freeze(),
      byEmployeeUid: Map.unmodifiable({
        for (final entry in accumulators.entries)
          entry.key: entry.value.freeze(),
      }),
    );
  }

  bool _validDate(String date) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return false;
    final year = int.parse(date.substring(0, 4));
    final month = int.parse(date.substring(5, 7));
    final day = int.parse(date.substring(8, 10));
    if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) {
      return false;
    }
    final parsed = DateTime.utc(year, month, day);
    return AttendanceStatisticsPeriod._format(parsed) == date;
  }

  bool _sameRecord(StatisticsAttendance a, StatisticsAttendance b) {
    final x = a.attendance;
    final y = b.attendance;
    return a.manualRevision == b.manualRevision &&
        x.employeeUid == y.employeeUid &&
        x.workDate == y.workDate &&
        x.status == y.status &&
        x.method == y.method &&
        x.checkInAt == y.checkInAt &&
        x.checkOutAt == y.checkOutAt;
  }
}

class _Accumulator {
  int completedRecords = 0;
  int workingRecords = 0;
  Duration duration = Duration.zero;
  int attendanceDays = 0;
  int biometricRecords = 0;
  int nfcRecords = 0;
  int manualRecords = 0;
  int manuallyAdjustedRecords = 0;
  int invalidRecords = 0;

  AttendanceStatistics freeze() => AttendanceStatistics(
    completedRecords: completedRecords,
    workingRecords: workingRecords,
    totalMinutes: duration.inMinutes,
    attendanceDays: attendanceDays,
    biometricRecords: biometricRecords,
    nfcRecords: nfcRecords,
    manualRecords: manualRecords,
    manuallyAdjustedRecords: manuallyAdjustedRecords,
    invalidRecords: invalidRecords,
  );
}
