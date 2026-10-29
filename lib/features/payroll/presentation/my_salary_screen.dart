import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/payroll/data/my_salary_repository.dart';
import 'package:smart_attendance/features/payroll/domain/work_time_calculator.dart';

enum MySalaryPeriod { week, month }

class MySalaryScreen extends StatefulWidget {
  const MySalaryScreen({
    required this.profile,
    this.repository,
    this.initialDate,
    this.showSalary = true,
    super.key,
  });

  final UserProfile profile;
  final MySalaryRepository? repository;
  final DateTime? initialDate;
  final bool showSalary;

  @override
  State<MySalaryScreen> createState() => _MySalaryScreenState();
}

class _MySalaryScreenState extends State<MySalaryScreen> {
  static const _calculator = WorkTimeCalculator();
  late final MySalaryRepository _repository;
  late DateTime _date;
  MySalaryPeriod _period = MySalaryPeriod.week;
  MySalaryData? _data;
  bool _loading = true;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirestoreMySalaryRepository();
    final now =
        widget.initialDate ??
        DateTime.now().toUtc().add(const Duration(hours: 7));
    _date = DateTime.utc(now.year, now.month, now.day);
    if (widget.profile.role == UserRole.employee) {
      _load();
    } else {
      _loading = false;
      _error = _accessError;
    }
  }

  String get _accessError => widget.showSalary
      ? 'Không có quyền xem lương tạm tính.'
      : 'Không có quyền xem giờ làm.';

  String get _loadError => widget.showSalary
      ? 'Không tải được lương tạm tính. Kiểm tra kết nối và thử lại.'
      : 'Không tải được giờ làm. Kiểm tra kết nối và thử lại.';

  String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  (String, String) get _range {
    if (_period == MySalaryPeriod.month) {
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
      final (start, end) = _range;
      final data = await _repository.loadPeriod(start, end);
      if (!mounted || request != _request) return;
      if (data.uid != widget.profile.uid) throw const MySalaryAccessException();
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error =
            error is MySalaryAccessException ||
                (error is FirebaseException &&
                    error.code == 'permission-denied')
            ? _accessError
            : _loadError;
      });
    }
  }

  void _move(int direction) {
    setState(() {
      _date = _period == MySalaryPeriod.week
          ? _date.add(Duration(days: direction * 7))
          : DateTime.utc(_date.year, _date.month + direction);
    });
    _load();
  }

  Future<void> _chooseDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: widget.showSalary
          ? 'Chọn kỳ lương tạm tính'
          : 'Chọn kỳ giờ làm',
    );
    if (!mounted || chosen == null) return;
    setState(() => _date = DateTime.utc(chosen.year, chosen.month, chosen.day));
    _load();
  }

  String _hours(int minutes) => '${minutes ~/ 60} giờ ${minutes % 60} phút';
  String _time(DateTime? value) {
    if (value == null) return '—';
    final vn = value.toUtc().add(const Duration(hours: 7));
    return '${vn.hour.toString().padLeft(2, '0')}:${vn.minute.toString().padLeft(2, '0')}';
  }

  String _method(String? value) => switch (value) {
    'biometric' => 'Sinh trắc học',
    'nfc' => 'NFC',
    'nfc_mobile' => 'NFC trên điện thoại',
    'manual' => 'Thủ công',
    _ => 'Không xác định',
  };

  String _exclusion(WorkExclusion? value) => switch (value) {
    WorkExclusion.incomplete || WorkExclusion.missingTime => 'Chưa hoàn thành',
    WorkExclusion.duplicateDate => 'Trùng ngày',
    _ => 'Dữ liệu không hợp lệ',
  };

  @override
  Widget build(BuildContext context) {
    final (start, end) = _range;
    final data = _data;
    final summary = data == null
        ? null
        : _period == MySalaryPeriod.week
        ? _calculator.summarizeWeek(data.attendance, data.uid, _date)
        : _calculator.summarizeMonth(
            data.attendance,
            data.uid,
            _date.year,
            _date.month,
          );
    int? salary;
    if (summary != null && widget.showSalary) {
      try {
        salary = _calculator.calculateSalaryVnd(
          summary.totalMinutes,
          data!.hourlyRate,
        );
      } on InvalidHourlyRateException {
        // Keep hours visible, but do not show a misleading salary.
      } on RangeError {
        // An unreasonably large rate cannot be represented as whole VND.
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.showSalary ? 'Lương của tôi' : 'Giờ làm của tôi'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.showSalary
                ? 'Lương tạm tính · Chưa phải bảng lương đã chốt.'
                : 'Tổng hợp giờ làm từ các bản ghi chấm công hợp lệ.',
          ),
          const SizedBox(height: 12),
          SegmentedButton<MySalaryPeriod>(
            segments: const [
              ButtonSegment(value: MySalaryPeriod.week, label: Text('Tuần')),
              ButtonSegment(value: MySalaryPeriod.month, label: Text('Tháng')),
            ],
            selected: {_period},
            onSelectionChanged: (value) {
              setState(() => _period = value.first);
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
                child: TextButton(
                  onPressed: _chooseDate,
                  child: Text('$start – $end', textAlign: TextAlign.center),
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
            if (widget.profile.role == UserRole.employee)
              TextButton(onPressed: _load, child: const Text('Thử lại')),
          ] else if (summary != null) ...[
            Text('Tổng giờ công hợp lệ: ${_hours(summary.totalMinutes)}'),
            if (widget.showSalary) ...[
              Text(
                'Đơn giá theo giờ: ${data!.hourlyRate is int && (data.hourlyRate as int) >= 0 ? '${data.hourlyRate} ₫/giờ' : 'Chưa có đơn giá hợp lệ'}',
              ),
              Text(
                'Lương tạm tính: ${salary == null ? 'Chưa có đơn giá hợp lệ' : '$salary ₫'}',
              ),
            ],
            Text(
              'Bản ghi chưa hoàn thành hoặc không hợp lệ: ${summary.excludedRecords}',
            ),
            const SizedBox(height: 12),
            if (summary.days.isEmpty)
              const Text('Kỳ này chưa có dữ liệu chấm công.'),
            for (final day in summary.days)
              Card(
                child: ListTile(
                  title: Text(day.attendance.workDate ?? 'Ngày không hợp lệ'),
                  subtitle: Text(
                    'Vào: ${_time(day.attendance.checkInAt)} · Ra: ${_time(day.attendance.checkOutAt)}\n'
                    'Giờ công: ${day.isPayable ? _hours(day.fullMinutes) : '0 giờ 0 phút'} · '
                    '${_method(day.attendance.method)}'
                    '${day.isPayable ? '' : '\n${_exclusion(day.exclusion)}${widget.showSalary ? ' · Không tính lương' : ''}'}',
                  ),
                  isThreeLine: true,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
