import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';

class EmptyEmployeePdfException implements Exception {
  const EmptyEmployeePdfException();
}

class EmployeePdfFontException implements Exception {
  const EmployeePdfFontException();
}

class EmployeeAttendancePdf {
  const EmployeeAttendancePdf({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

/// Builds one employee's report from attendance already loaded for the period.
/// Work totals are supplied by AttendanceStatisticsService.
class EmployeeAttendancePdfGenerator {
  const EmployeeAttendancePdfGenerator();

  static const _statistics = AttendanceStatisticsService();

  Future<EmployeeAttendancePdf> generate({
    required String employeeUid,
    required String employeeName,
    required String employeeEmail,
    required AttendanceStatisticsPeriod period,
    required Iterable<StatisticsAttendance> records,
    required DateTime exportedAt,
    required ByteData fontData,
  }) async {
    if (fontData.lengthInBytes == 0) throw const EmployeePdfFontException();
    final ownRecords =
        records
            .where(
              (entry) =>
                  entry.attendance.employeeUid == employeeUid &&
                  entry.attendance.workDate != null &&
                  period.contains(entry.attendance.workDate!),
            )
            .toList()
          ..sort(
            (a, b) => a.attendance.workDate!.compareTo(b.attendance.workDate!),
          );
    final stats = _statistics.summarize(ownRecords, period).enterprise;
    if (stats.attendanceDays == 0) throw const EmptyEmployeePdfException();

    late final pw.Font font;
    try {
      font = pw.Font.ttf(fontData);
    } catch (_) {
      throw const EmployeePdfFontException();
    }
    final document = pw.Document();
    final vietnamTime = exportedAt.toUtc().add(const Duration(hours: 7));
    final label = switch (period.kind) {
      AttendancePeriodKind.week => 'Tuần',
      AttendancePeriodKind.month => 'Tháng',
      AttendancePeriodKind.quarter => 'Quý',
      AttendancePeriodKind.year => 'Năm',
    };
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font),
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(
            'BÁO CÁO CHẤM CÔNG CÁ NHÂN',
            style: pw.TextStyle(font: font, fontSize: 18),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Nhân viên: $employeeName'),
          pw.Text(
            'Email đăng ký: ${employeeEmail.trim().isEmpty ? 'Chưa có email đăng ký' : employeeEmail}',
          ),
          pw.Text(
            'Kỳ báo cáo: $label, ${period.startDate} – ${period.endDate}',
          ),
          pw.Text('Ngày xuất (giờ Việt Nam): ${_dateTime(vietnamTime)}'),
          pw.SizedBox(height: 12),
          pw.Text('Số ngày có chấm công: ${stats.attendanceDays}'),
          pw.Text('Completed: ${stats.completedRecords}'),
          pw.Text('Working / chưa Check-out: ${stats.workingRecords}'),
          pw.Text(
            'Tổng giờ công hợp lệ: ${stats.totalMinutes ~/ 60} giờ ${stats.totalMinutes % 60} phút',
          ),
          if (stats.invalidRecords > 0)
            pw.Text(
              '${stats.invalidRecords} ngày có dữ liệu xung đột hoặc không hợp lệ; không tính vào tổng.',
            ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Chi tiết chấm công',
            style: pw.TextStyle(font: font, fontSize: 13),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Ngày',
              'Giờ vào',
              'Giờ ra',
              'Trạng thái',
              'Phương thức',
              'Điều chỉnh',
            ],
            data: [
              for (final entry in ownRecords)
                [
                  entry.attendance.workDate!,
                  _time(entry.attendance.checkInAt),
                  _time(entry.attendance.checkOutAt),
                  _status(entry.attendance.status),
                  _method(entry.attendance.method),
                  entry.manualRevision != null && entry.manualRevision! > 0
                      ? 'Có'
                      : 'Không',
                ],
            ],
            cellStyle: pw.TextStyle(font: font, fontSize: 8),
            headerStyle: pw.TextStyle(font: font, fontSize: 8),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Bản ghi có điều chỉnh thủ công: ${stats.manuallyAdjustedRecords}.',
          ),
        ],
      ),
    );
    final code = exportedAt.toUtc().microsecondsSinceEpoch.toString();
    final fileName =
        'bao_cao_cham_cong_${period.kind.name}_${period.startDate}_${period.endDate}_$code.pdf';
    return EmployeeAttendancePdf(
      bytes: await document.save(),
      fileName: fileName,
    );
  }

  static String _time(DateTime? instant) {
    if (instant == null) return '—';
    final vietnam = instant.toUtc().add(const Duration(hours: 7));
    return '${vietnam.hour.toString().padLeft(2, '0')}:${vietnam.minute.toString().padLeft(2, '0')}';
  }

  static String _dateTime(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  static String _status(String? value) => switch (value) {
    'completed' => 'Completed',
    'working' => 'Working',
    _ => 'Không hợp lệ',
  };

  static String _method(String? value) => switch (value) {
    'biometric' => 'Biometric',
    'nfc' => 'NFC',
    'nfc_mobile' => 'NFC mobile',
    'manual' => 'Manual',
    _ => 'Không hợp lệ',
  };
}
