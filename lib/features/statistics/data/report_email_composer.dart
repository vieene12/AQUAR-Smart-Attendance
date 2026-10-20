import 'package:flutter/services.dart';
import 'package:smart_attendance/features/statistics/domain/employee_attendance_pdf.dart';
import 'package:smart_attendance/features/statistics/domain/report_email_draft.dart';

abstract class ReportEmailComposer {
  /// Opens a draft. Completion never means that the message was sent.
  Future<void> openDraft(ReportEmailDraft draft, EmployeeAttendancePdf pdf);
}

class AndroidReportEmailComposer implements ReportEmailComposer {
  const AndroidReportEmailComposer();

  static const _channel = MethodChannel('smart_attendance/report_email');

  @override
  Future<void> openDraft(
    ReportEmailDraft draft,
    EmployeeAttendancePdf pdf,
  ) async {
    await _channel.invokeMethod<void>('openDraft', {
      'recipient': draft.recipient,
      'subject': draft.subject,
      'body': draft.body,
      'fileName': pdf.fileName,
      'pdfBytes': pdf.bytes,
    });
  }
}
