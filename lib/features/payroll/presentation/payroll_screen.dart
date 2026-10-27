import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/payroll/data/payroll_repository.dart';
import 'package:smart_attendance/features/payroll/domain/work_time_calculator.dart';

enum PayrollPeriodKind { week, month }

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({
    required this.profile,
    this.repository,
    this.initialDate,
    super.key,
  });

  final UserProfile profile;
  final PayrollRepository? repository;
  final DateTime? initialDate;

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  static const _calculator = WorkTimeCalculator();
  late final PayrollRepository _repository;
  late DateTime _date;
  PayrollPeriodKind _kind = PayrollPeriodKind.week;
  PayrollData? _data;
  bool _loading = true;
  bool _denied = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirestorePayrollRepository();
    final now =
        widget.initialDate ??
        DateTime.now().toUtc().add(const Duration(hours: 7));
    _date = DateTime.utc(now.year, now.month, now.day);
    if (widget.profile.role == UserRole.admin ||
        widget.profile.role == UserRole.manager) {
      _load();
    } else {
      _loading = false;
      _denied = true;
    }
  }

  String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  (String, String) get _range {
    if (_kind == PayrollPeriodKind.month) {
      return (
        _day(DateTime.utc(_date.year, _date.month)),
        _day(DateTime.utc(_date.year, _date.month + 1, 0)),
      );
    }
    final monday = _date.subtract(
      Duration(days: _date.weekday - DateTime.monday),
    );
    return (_day(monday), _day(monday.add(const Duration(days: 6))));
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
    });
    try {
      final allowed = await _repository.canAccess(widget.profile);
      if (!mounted || request != _request) return;
      if (!allowed) {
        setState(() {
          _denied = true;
          _loading = false;
        });
        return;
      }
      final (start, end) = _range;
      final data = await _repository.loadPeriod(widget.profile, start, end);
      if (!mounted || request != _request) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = _errorText(error);
        _loading = false;
      });
    }
  }

  String _errorText(Object error) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'Không có quyền xem bảng lương.';
    }
    return 'Không tải được bảng lương. Kiểm tra kết nối và thử lại.';
  }

  void _move(int direction) {
    setState(() {
      _date = _kind == PayrollPeriodKind.week
          ? _date.add(Duration(days: 7 * direction))
          : DateTime.utc(_date.year, _date.month + direction, 1);
    });
    _load();
  }

  Future<void> _chooseDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Chọn kỳ lương',
    );
    if (!mounted || chosen == null) return;
    setState(() => _date = DateTime.utc(chosen.year, chosen.month, chosen.day));
    _load();
  }

  WorkPeriodSummary _summary(PayrollData data, PayrollEmployee employee) =>
      _kind == PayrollPeriodKind.week
      ? _calculator.summarizeWeek(data.attendance, employee.uid, _date)
      : _calculator.summarizeMonth(
          data.attendance,
          employee.uid,
          _date.year,
          _date.month,
        );

  int? _salary(int minutes, int? rate) {
    try {
      return _calculator.calculateSalaryVnd(minutes, rate);
    } on InvalidHourlyRateException {
      return null;
    }
  }

  String _money(int? value) =>
      value == null ? 'Chưa có đơn giá hợp lệ' : '$value ₫';
  String _rate(int? value) =>
      value == null || value < 0 ? 'Chưa có đơn giá hợp lệ' : '$value ₫';
  String _hours(int minutes) => '${minutes ~/ 60} giờ ${minutes % 60} phút';
  String _time(DateTime? time) {
    if (time == null) return '—';
    final vn = time.toUtc().add(const Duration(hours: 7));
    return '${vn.hour.toString().padLeft(2, '0')}:${vn.minute.toString().padLeft(2, '0')}';
  }

  void _showDetail(PayrollEmployee employee, WorkPeriodSummary summary) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(employee.name)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Kỳ ${summary.startDate} – ${summary.endDate}'),
              Text(
                'Tổng: ${_hours(summary.totalMinutes)} · ${_money(_salary(summary.totalMinutes, employee.hourlyRate))}',
              ),
              const Text(
                'Tổng lương tính từ tổng phút của kỳ; tiền từng ngày chỉ để tham khảo.',
              ),
              if (summary.excludedRecords > 0)
                Text(
                  'Cảnh báo: ${summary.excludedRecords} bản ghi chưa hoàn thành hoặc không hợp lệ, không tính lương.',
                ),
              if (summary.days.isEmpty)
                const Text('Kỳ này chưa có dữ liệu chấm công.'),
              for (final day in summary.days)
                Card(
                  child: ListTile(
                    title: Text(day.attendance.workDate ?? 'Ngày không hợp lệ'),
                    subtitle: Text(
                      'Vào: ${_time(day.attendance.checkInAt)} · Ra: ${_time(day.attendance.checkOutAt)}\n'
                      '${day.isPayable ? '${day.fullMinutes} phút · ${_money(_salary(day.fullMinutes, employee.hourlyRate))}' : 'Không tính lương (${_exclusion(day.exclusion)})'}',
                    ),
                    isThreeLine: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _exclusion(WorkExclusion? reason) => switch (reason) {
    WorkExclusion.incomplete || WorkExclusion.missingTime => 'Chưa hoàn thành',
    WorkExclusion.duplicateDate => 'Trùng ngày',
    _ => 'Dữ liệu không hợp lệ',
  };

  @override
  Widget build(BuildContext context) {
    final (start, end) = _range;
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('Bảng lương')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<PayrollPeriodKind>(
            segments: const [
              ButtonSegment(value: PayrollPeriodKind.week, label: Text('Tuần')),
              ButtonSegment(
                value: PayrollPeriodKind.month,
                label: Text('Tháng'),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (value) {
              setState(() => _kind = value.first);
              _load();
            },
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => _move(-1),
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Kỳ trước',
              ),
              Expanded(
                child: TextButton(
                  onPressed: _chooseDate,
                  child: Text('$start – $end', textAlign: TextAlign.center),
                ),
              ),
              IconButton(
                onPressed: () => _move(1),
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Kỳ sau',
              ),
            ],
          ),
          if (_denied)
            const Text('Không có quyền xem bảng lương.')
          else if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null) ...[
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('Thử lại')),
          ] else if (data != null) ...[
            if (data.employees.isEmpty) const Text('Chưa có nhân viên.'),
            if (data.attendance.isEmpty && data.employees.isNotEmpty)
              const Text('Kỳ này chưa có dữ liệu chấm công.'),
            for (final employee in data.employees)
              Builder(
                builder: (context) {
                  final summary = _summary(data, employee);
                  return Card(
                    child: ListTile(
                      title: Text(employee.name),
                      subtitle: Text(
                        '${_hours(summary.totalMinutes)} · Đơn giá: ${_rate(employee.hourlyRate)} /giờ\n'
                        'Lương tạm tính: ${_money(_salary(summary.totalMinutes, employee.hourlyRate))}'
                        '${summary.excludedRecords > 0 ? '\nCảnh báo: ${summary.excludedRecords} bản ghi chưa hoàn thành/không hợp lệ' : ''}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showDetail(employee, summary),
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}
