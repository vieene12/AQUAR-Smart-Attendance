import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/statistics/data/attendance_report_repository.dart';
import 'package:smart_attendance/features/statistics/data/report_email_api_client.dart';
import 'package:smart_attendance/features/statistics/data/report_email_repository.dart';
import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';
import 'package:smart_attendance/features/statistics/domain/employee_attendance_pdf.dart';

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({
    required this.profile,
    this.repository,
    this.initialDate,
    this.pdfGenerator,
    this.previewHandler,
    this.reportEmailRepository,
    super.key,
  });

  final UserProfile profile;
  final AttendanceReportRepository? repository;
  final DateTime? initialDate;
  final EmployeeAttendancePdfGenerator? pdfGenerator;
  final Future<void> Function(BuildContext, EmployeeAttendancePdf)?
  previewHandler;
  final ReportEmailRepositoryContract? reportEmailRepository;

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  static const _statistics = AttendanceStatisticsService();
  late final AttendanceReportRepository _repository;
  late final ReportEmailRepositoryContract _reportEmailRepository;
  late DateTime _selectedInstant;
  AttendancePeriodKind _kind = AttendancePeriodKind.week;
  AttendanceReportData? _data;
  bool _loading = true;
  String? _error;
  int _request = 0;

  EmployeeAttendancePdfGenerator get _pdfGenerator =>
      widget.pdfGenerator ?? const EmployeeAttendancePdfGenerator();
  AttendanceStatisticsPeriod get _period =>
      AttendanceStatisticsPeriod.containing(_kind, _selectedInstant);

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirestoreAttendanceReportRepository();
    _reportEmailRepository =
        widget.reportEmailRepository ?? ReportEmailRepository();
    _selectedInstant = widget.initialDate ?? DateTime.now();
    if (widget.profile.role == UserRole.admin ||
        widget.profile.role == UserRole.manager) {
      _load();
    } else {
      _loading = false;
      _error = 'Không có quyền xem báo cáo thống kê.';
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    final period = _period;
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
    });
    try {
      final data = await _repository.loadPeriod(
        widget.profile,
        period.startDate,
        period.endDate,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error =
            error is AttendanceReportAccessException ||
                (error is FirebaseException &&
                    error.code == 'permission-denied')
            ? 'Không có quyền xem báo cáo thống kê.'
            : 'Không tải được báo cáo. Kiểm tra kết nối và thử lại.';
      });
    }
  }

  void _move(int direction) {
    final period = _period;
    // The period boundaries are Vietnam calendar dates represented in UTC.
    final date = direction < 0
        ? period.start.subtract(const Duration(days: 1))
        : period.end.add(const Duration(days: 1));
    setState(() => _selectedInstant = date);
    _load();
  }

  String _hours(int minutes) => '${minutes ~/ 60} giờ ${minutes % 60} phút';

  Widget _summary(AttendanceStatistics stats) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      _metric('Completed', '${stats.completedRecords}'),
      _metric('Working / chưa Check-out', '${stats.workingRecords}'),
      _metric('Giờ công hợp lệ', _hours(stats.totalMinutes)),
      _metric('Ngày có chấm công', '${stats.attendanceDays}'),
      _metric(
        'Bản ghi điều chỉnh thủ công',
        '${stats.manuallyAdjustedRecords}',
      ),
    ],
  );

  Widget _metric(String label, String value) => SizedBox(
    width: 180,
    child: Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 5),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    ),
  );

  Widget _methodChart(AttendanceStatistics stats) {
    final total =
        stats.biometricRecords + stats.nfcRecords + stats.manualRecords;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Phân bố phương thức',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _bar('Biometric', stats.biometricRecords, total, colors.primary),
        _bar('NFC', stats.nfcRecords, total, colors.tertiary),
        _bar('Manual', stats.manualRecords, total, colors.secondary),
        const Text(
          'Bản ghi điều chỉnh thủ công được đếm riêng, không cộng thêm vào biểu đồ.',
        ),
      ],
    );
  }

  Widget _bar(String label, int value, int total, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : value / total,
            color: color,
            minHeight: 12,
          ),
        ),
        SizedBox(width: 46, child: Text(' $value', textAlign: TextAlign.end)),
      ],
    ),
  );

  Future<EmployeeAttendancePdf> _buildEmployeePdf({
    required String uid,
    required String name,
    required String email,
    required AttendanceStatisticsPeriod period,
    required Iterable<StatisticsAttendance> records,
  }) async {
    late final ByteData fontData;
    try {
      fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    } catch (_) {
      throw const EmployeePdfFontException();
    }
    return _pdfGenerator.generate(
      employeeUid: uid,
      employeeName: name,
      employeeEmail: email,
      period: period,
      records: records,
      exportedAt: DateTime.now(),
      fontData: fontData,
    );
  }

  void _showEmployee(String uid, String name, AttendanceStatistics stats) {
    final period = _period;
    var busy = false;
    String? busyLabel;
    String? actionMessage;
    var emailRequestLocked = false;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatefulBuilder(
          builder: (detailContext, updateDetail) {
            Future<void> export() async {
              if (busy) return;
              updateDetail(() {
                busy = true;
                busyLabel = 'Đang tạo PDF…';
                actionMessage = null;
              });
              try {
                if (widget.profile.role != UserRole.admin &&
                    widget.profile.role != UserRole.manager) {
                  throw const AttendanceReportAccessException();
                }
                // Re-read through the repository: it checks the current account
                // on the server before returning fresh attendance and email.
                final fresh = await _repository.loadPeriod(
                  widget.profile,
                  period.startDate,
                  period.endDate,
                );
                if (!detailContext.mounted) return;
                final pdf = await _buildEmployeePdf(
                  uid: uid,
                  name: fresh.employeeNames[uid] ?? name,
                  email: fresh.employeeEmails[uid] ?? '',
                  period: period,
                  records: fresh.records,
                );
                if (!detailContext.mounted) return;
                if (widget.previewHandler != null) {
                  await widget.previewHandler!(detailContext, pdf);
                } else {
                  await Navigator.of(detailContext).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: const Text('Xem trước PDF'),
                          actions: [
                            IconButton(
                              tooltip: 'Lưu hoặc chia sẻ PDF',
                              icon: const Icon(Icons.share_outlined),
                              onPressed: () => Printing.sharePdf(
                                bytes: pdf.bytes,
                                filename: pdf.fileName,
                              ),
                            ),
                          ],
                        ),
                        body: PdfPreview(
                          build: (_) async => pdf.bytes,
                          pdfFileName: pdf.fileName,
                          canChangeOrientation: false,
                          canChangePageFormat: false,
                        ),
                      ),
                    ),
                  );
                }
              } catch (error) {
                if (!detailContext.mounted) return;
                updateDetail(() {
                  actionMessage =
                      error is AttendanceReportAccessException ||
                          (error is FirebaseException &&
                              error.code == 'permission-denied')
                      ? 'Không có quyền xuất báo cáo.'
                      : error is EmptyEmployeePdfException
                      ? 'Không có dữ liệu chấm công hợp lệ để xuất PDF.'
                      : error is EmployeePdfFontException
                      ? 'Không tải được font tiếng Việt cho PDF.'
                      : 'Không tạo được PDF. Kiểm tra kết nối và thử lại.';
                });
              } finally {
                if (detailContext.mounted) {
                  updateDetail(() {
                    busy = false;
                    busyLabel = null;
                  });
                }
              }
            }

            Future<void> sendEmail() async {
              if (busy || emailRequestLocked) return;
              updateDetail(() {
                busy = true;
                busyLabel = 'Đang gửi yêu cầu…';
                actionMessage = null;
              });
              try {
                if (widget.profile.role != UserRole.admin &&
                    widget.profile.role != UserRole.manager) {
                  throw const AttendanceReportAccessException();
                }
                await _reportEmailRepository.sendReport(
                  employeeUid: uid,
                  periodKind: period.kind.name,
                  anchorDate: period.startDate,
                );
                if (!detailContext.mounted) return;
                updateDetail(() {
                  emailRequestLocked = true;
                  actionMessage = 'Hệ thống đã tiếp nhận yêu cầu gửi email. Trạng thái này chưa xác nhận người nhận đã nhận thư.';
                });
              } catch (error) {
                if (!detailContext.mounted) return;
                updateDetail(() {
                  if (error is ReportEmailUncertainException) {
                    emailRequestLocked = true;
                    actionMessage = 'Chưa xác định được kết quả gửi. Không gửi lại yêu cầu mới để tránh email trùng; hãy kiểm tra sau.';
                  } else if (error is ReportEmailApiException) {
                    actionMessage = error.userMessage;
                  } else if (error is AttendanceReportAccessException) {
                    actionMessage = 'Không có quyền gửi báo cáo qua email.';
                  } else {
                    actionMessage = 'Không gửi được yêu cầu báo cáo. Vui lòng kiểm tra kết nối.';
                  }
                });
              } finally {
                if (detailContext.mounted) {
                  updateDetail(() {
                    busy = false;
                    busyLabel = null;
                  });
                }
              }
            }

            return Scaffold(
              appBar: AppBar(title: Text(name)),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('UID: $uid'),
                  Text('Kỳ ${period.startDate} – ${period.endDate}'),
                  const SizedBox(height: 12),
                  _summary(stats),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: busy || stats.attendanceDays == 0
                        ? null
                        : export,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(
                      busyLabel == 'Đang tạo PDF…'
                          ? 'Đang tạo PDF…'
                          : 'Xuất PDF',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed:
                        busy || stats.attendanceDays == 0 || emailRequestLocked
                        ? null
                        : sendEmail,
                    icon: const Icon(Icons.email_outlined),
                    label: Text(
                      busyLabel == 'Đang gửi yêu cầu…'
                          ? 'Đang gửi yêu cầu…'
                          : 'Gửi báo cáo qua email',
                    ),
                  ),
                  if (actionMessage != null) Text(actionMessage!),
                  const SizedBox(height: 20),
                  _methodChart(stats),
                  if (stats.invalidRecords > 0)
                    Text(
                      '${stats.invalidRecords} ngày có bản ghi xung đột hoặc không hợp lệ; không tính vào các tổng.',
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final period = _period;
    final data = _data;
    final report = data == null
        ? null
        : _statistics.summarize(data.records, period);
    final rows = report?.byEmployeeUid.entries.toList()
      ?..sort((a, b) {
        final aName = data!.employeeNames[a.key] ?? a.key;
        final bName = data.employeeNames[b.key] ?? b.key;
        return aName.compareTo(bName);
      });
    return Scaffold(
      appBar: AppBar(title: const Text('Báo cáo thống kê')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<AttendancePeriodKind>(
            segments: const [
              ButtonSegment(
                value: AttendancePeriodKind.week,
                label: Text('Tuần'),
              ),
              ButtonSegment(
                value: AttendancePeriodKind.month,
                label: Text('Tháng'),
              ),
              ButtonSegment(
                value: AttendancePeriodKind.quarter,
                label: Text('Quý'),
              ),
              ButtonSegment(
                value: AttendancePeriodKind.year,
                label: Text('Năm'),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (selected) {
              setState(() => _kind = selected.first);
              _load();
            },
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => _move(-1),
                tooltip: 'Kỳ trước',
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${period.startDate} – ${period.endDate}',
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                onPressed: () => _move(1),
                tooltip: 'Kỳ sau',
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null) ...[
            Text(_error!),
            if (widget.profile.role != UserRole.employee)
              TextButton(onPressed: _load, child: const Text('Thử lại')),
          ] else if (report != null) ...[
            if (data!.records.isEmpty)
              const Text('Kỳ này chưa có dữ liệu chấm công.'),
            _summary(report.enterprise),
            const SizedBox(height: 20),
            _methodChart(report.enterprise),
            if (report.enterprise.invalidRecords > 0)
              Text(
                '${report.enterprise.invalidRecords} ngày có bản ghi xung đột hoặc không hợp lệ; không tính vào các tổng.',
              ),
            const SizedBox(height: 20),
            Text(
              'Theo nhân viên',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (rows!.isEmpty && data.records.isNotEmpty)
              const Text('Không có bản ghi hợp lệ để thống kê theo nhân viên.'),
            if (rows.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Nhân viên')),
                    DataColumn(label: Text('Completed')),
                    DataColumn(label: Text('Working')),
                    DataColumn(label: Text('Giờ công')),
                    DataColumn(label: Text('Ngày')),
                    DataColumn(label: Text('Điều chỉnh manual')),
                  ],
                  rows: [
                    for (final item in rows)
                      DataRow(
                        onSelectChanged: (_) => _showEmployee(
                          item.key,
                          data.employeeNames[item.key] ?? item.key,
                          item.value,
                        ),
                        cells: [
                          DataCell(
                            Text(data.employeeNames[item.key] ?? item.key),
                          ),
                          DataCell(Text('${item.value.completedRecords}')),
                          DataCell(Text('${item.value.workingRecords}')),
                          DataCell(Text(_hours(item.value.totalMinutes))),
                          DataCell(Text('${item.value.attendanceDays}')),
                          DataCell(
                            Text('${item.value.manuallyAdjustedRecords}'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
