import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';

class InvalidReportEmailException implements Exception {
  const InvalidReportEmailException();
}

class ReportEmailDraft {
  const ReportEmailDraft({
    required this.recipient,
    required this.subject,
    required this.body,
  });

  final String recipient;
  final String subject;
  final String body;

  static final _emailPattern = RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
  );

  factory ReportEmailDraft.forEmployee({
    required String registeredEmail,
    required String employeeName,
    required AttendanceStatisticsPeriod period,
  }) {
    final recipient = registeredEmail.trim();
    if (!_emailPattern.hasMatch(recipient) ||
        recipient.contains('..') ||
        recipient.length > 254) {
      throw const InvalidReportEmailException();
    }
    final name = employeeName.trim();
    final periodName = switch (period.kind) {
      AttendancePeriodKind.week => 'tuần',
      AttendancePeriodKind.month => 'tháng',
      AttendancePeriodKind.quarter => 'quý',
      AttendancePeriodKind.year => 'năm',
    };
    final periodText = '$periodName ${period.startDate} – ${period.endDate}';
    return ReportEmailDraft(
      recipient: recipient,
      subject: 'Báo cáo chấm công của $name - $periodText',
      body:
          'Kính gửi $name,\n\n'
          'Đính kèm là báo cáo chấm công của bạn cho kỳ $periodText.\n'
          'Vui lòng kiểm tra nội dung báo cáo PDF.\n\n'
          'Trân trọng,\nAquar Smart Attendance',
    );
  }
}
