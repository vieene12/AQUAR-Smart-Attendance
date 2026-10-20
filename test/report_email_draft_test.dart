import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';
import 'package:smart_attendance/features/statistics/domain/report_email_draft.dart';

void main() {
  test('tiêu đề, nội dung tiếng Việt chứa tên và kỳ báo cáo', () {
    for (final (kind, label) in [
      (AttendancePeriodKind.week, 'tuần'),
      (AttendancePeriodKind.month, 'tháng'),
      (AttendancePeriodKind.quarter, 'quý'),
      (AttendancePeriodKind.year, 'năm'),
    ]) {
      final period = AttendanceStatisticsPeriod.containing(
        kind,
        DateTime.utc(2026, 10, 15, 12),
      );
      final draft = ReportEmailDraft.forEmployee(
        registeredEmail: '  nhan.vien@example.com  ',
        employeeName: 'Nguyễn Văn A',
        period: period,
      );
      expect(draft.recipient, 'nhan.vien@example.com');
      expect(draft.subject, contains('Nguyễn Văn A'));
      expect(draft.subject, contains(label));
      expect(draft.subject, contains(period.startDate));
      expect(draft.subject, contains(period.endDate));
      expect(draft.body, contains('Kính gửi Nguyễn Văn A'));
      expect(draft.body, contains(period.startDate));
      expect(draft.body, contains('Đính kèm'));
    }
  });

  test('từ chối email thiếu, sai định dạng và ký tự điều khiển', () {
    final period = AttendanceStatisticsPeriod.containing(
      AttendancePeriodKind.week,
      DateTime.utc(2026, 10, 15, 12),
    );
    for (final email in [
      '',
      'not-an-email',
      'a@example.com\nBcc:other@example.com',
      'a,b@example.com',
      'a..b@example.com',
    ]) {
      expect(
        () => ReportEmailDraft.forEmployee(
          registeredEmail: email,
          employeeName: 'A',
          period: period,
        ),
        throwsA(isA<InvalidReportEmailException>()),
      );
    }
  });
}
