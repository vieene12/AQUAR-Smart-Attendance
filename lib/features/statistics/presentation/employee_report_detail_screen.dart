import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:smart_attendance/features/statistics/data/report_dispatch_repository.dart';
import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';

class EmployeeReportDetailScreen extends StatefulWidget {
  const EmployeeReportDetailScreen({
    required this.person,
    required this.kind,
    required this.date,
    required this.repository,
    required this.fileExporter,
    super.key,
  });

  final ReportRecipient person;
  final AttendancePeriodKind kind;
  final DateTime date;
  final ReportDispatchRepository repository;
  final ReportFileExporter fileExporter;

  @override
  State<EmployeeReportDetailScreen> createState() =>
      _EmployeeReportDetailScreenState();
}

class _EmployeeReportDetailScreenState
    extends State<EmployeeReportDetailScreen> {
  late final Future<ReportEmployeeDetail> _detail;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _detail = widget.repository.detail(
      employeeUid: widget.person.uid,
      kind: widget.kind,
      date: widget.date,
    );
  }

  String _money(int? value) => value == null
      ? 'Chưa thiết lập đơn giá giờ'
      : '${value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')} ₫';

  String _hours(int minutes) =>
      '${minutes ~/ 60} giờ ${(minutes % 60).toString().padLeft(2, '0')} phút';

  String _message(Object error) =>
      error is FirebaseFunctionsException && error.message?.isNotEmpty == true
      ? error.message!
      : 'Không xử lý được báo cáo. Vui lòng thử lại.';

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ReportPdf> _pdf() => widget.repository.preview(
    employeeUid: widget.person.uid,
    kind: widget.kind,
    date: widget.date,
  );

  Future<void> _preview() => _run(() async {
    final pdf = await _pdf();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(pdf.fileName)),
          body: PdfPreview(
            build: (_) async => pdf.bytes,
            pdfFileName: pdf.fileName,
          ),
        ),
      ),
    );
  });

  Future<void> _print() => _run(() async {
    final pdf = await _pdf();
    await Printing.layoutPdf(
      onLayout: (_) async => pdf.bytes,
      name: pdf.fileName,
    );
  });

  Future<void> _export() => _run(() async {
    final pdf = await _pdf();
    final saved = await widget.fileExporter.save(pdf.fileName, pdf.bytes);
    if (saved && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Đã lưu ${pdf.fileName}')));
    }
  });

  Future<void> _send() => _run(() async {
    final results = await widget.repository.send(
      recipients: [widget.person],
      kind: widget.kind,
      date: widget.date,
    );
    if (!mounted) return;
    final result = results.single;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          result.success ? 'Gửi email thành công' : 'Gửi email thất bại',
        ),
        content: Text('${result.name}: ${result.message}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  });

  Widget _attendance(ReportEmployeeDetail detail) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _info('Kỳ báo cáo', detail.period),
      _info('Số ngày có chấm công', '${detail.data['workDays'] ?? 0}'),
      _info('Tổng số ca', '${detail.data['shifts'] ?? 0}'),
      _info(
        'Check-in / Check-out',
        '${detail.data['checkIns'] ?? 0} / ${detail.data['checkOuts'] ?? 0}',
      ),
      _info(
        'Đi trễ / Về sớm',
        '${detail.data['late'] ?? 0} / ${detail.data['early'] ?? 0}',
      ),
      const SizedBox(height: 12),
      Text(
        'Chi tiết từng ngày',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      if (detail.days.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Không có dữ liệu chấm công trong kỳ.'),
          ),
        ),
      for (final day in detail.days)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${day['workDate']} · ${detail.data['shift'] ?? 'Chưa thiết lập ca'}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text('Check-in: ${day['checkIn']}'),
                Text('Check-out: ${day['checkOut']}'),
                Text(
                  'Giờ hợp lệ: ${day['paidMinutes'] is int ? _hours(day['paidMinutes'] as int) : 'Chưa tính'}',
                ),
                Text(
                  'Trạng thái: ${day['status']}${day['late'] == true ? ' · Đi trễ' : ''}${day['early'] == true ? ' · Về sớm' : ''}',
                ),
                if (day['duplicateDate'] == true)
                  const Text('Trùng ngày, không tính lương'),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _payroll(ReportEmployeeDetail detail) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Card.filled(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bảng lương', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _info('Họ tên', detail.name),
              _info('Mã nhân viên', detail.code),
              _info('Kỳ lương', detail.period),
              _info('Đơn giá giờ', _money(detail.hourlyRate)),
              _info('Tổng giờ làm hợp lệ', _hours(detail.totalMinutes)),
              _info('Số ca/ngày công hợp lệ', '${detail.payableDays}'),
              const Divider(),
              _info('Tổng lương', _money(detail.totalSalary)),
            ],
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Chỉ các ca đã check-out và hợp lệ mới được tính lương. Giờ nghỉ trưa 12:00–13:00 được trừ theo quy tắc hiện tại.',
        ),
      ),
    ],
  );

  Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text('$label: $value'),
  );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.person.name),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Chấm công'),
            Tab(text: 'Bảng lương'),
          ],
        ),
      ),
      body: FutureBuilder<ReportEmployeeDetail>(
        future: _detail,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(_message(snapshot.error!)));
          }
          final detail = snapshot.data!;
          return TabBarView(children: [_attendance(detail), _payroll(detail)]);
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _preview,
                    child: const Text('Xem PDF'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _print,
                    child: const Text('In'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _export,
                    child: const Text('Xuất PDF'),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _send,
                    child: const Text('Gửi email'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
