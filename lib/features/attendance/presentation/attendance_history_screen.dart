import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';

enum _HistoryFilter { all, month, range }

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({
    required this.employeeId,
    super.key,
    this.repository,
  });

  final String employeeId;
  final AttendanceRepository? repository;

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  late final AttendanceRepository _repository;
  _HistoryFilter _filter = _HistoryFilter.all;
  DateTime? _startDate;
  DateTime? _endDate;
  List<AttendanceRecord> _records = const [];
  bool _loading = true;
  String? _error;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirestoreAttendanceRepository();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final serial = ++_requestSerial;
    setState(() {
      _loading = true;
      _error = null;
      _records = const [];
    });
    try {
      final records = await _repository.loadHistory(
        widget.employeeId,
        startDate: _startDate,
        endDate: _endDate,
      );
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _loading = false;
        _error = _errorMessage(error);
      });
    }
  }

  Future<void> _chooseMonth() async {
    final today = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: _startDate ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Chọn một ngày trong tháng cần xem',
    );
    if (!mounted || chosen == null) return;
    setState(() {
      _filter = _HistoryFilter.month;
      _startDate = DateTime(chosen.year, chosen.month);
      _endDate = DateTime(chosen.year, chosen.month + 1, 0);
    });
    await _load();
  }

  Future<void> _chooseRange() async {
    final today = DateTime.now();
    final chosen = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange:
          _filter == _HistoryFilter.range &&
              _startDate != null &&
              _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : DateTimeRange(start: today, end: today),
      helpText: 'Chọn khoảng ngày làm việc',
    );
    if (!mounted || chosen == null) return;
    setState(() {
      _filter = _HistoryFilter.range;
      _startDate = chosen.start;
      _endDate = chosen.end;
    });
    await _load();
  }

  void _showAll() {
    if (_filter == _HistoryFilter.all) return;
    setState(() {
      _filter = _HistoryFilter.all;
      _startDate = null;
      _endDate = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text('Tất cả'),
              selected: _filter == _HistoryFilter.all,
              onSelected: (_) => _showAll(),
            ),
            FilterChip(
              label: const Text('Theo tháng'),
              selected: _filter == _HistoryFilter.month,
              onSelected: (_) => _chooseMonth(),
            ),
            FilterChip(
              label: const Text('Khoảng ngày'),
              selected: _filter == _HistoryFilter.range,
              onSelected: (_) => _chooseRange(),
            ),
          ],
        ),
        if (_startDate != null && _endDate != null) ...[
          const SizedBox(height: 8),
          Text(
            'Từ ${_formatCalendarDate(_startDate!)} đến ${_formatCalendarDate(_endDate!)}',
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 16),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_error != null)
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.error_outline, color: colors.error, size: 40),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          )
        else if (_records.isEmpty)
          const Card.filled(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Không có bản ghi chấm công trong thời gian đã chọn.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ..._records.map(_recordCard),
      ],
    );
  }

  Widget _recordCard(AttendanceRecord record) {
    final theme = Theme.of(context);
    final completed = record.checkOutAt != null;
    final dateParts = record.workDate.split('-');
    final dateLabel = '${dateParts[2]}/${dateParts[1]}/${dateParts[0]}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Ngày làm: $dateLabel',
                  style: theme.textTheme.titleMedium,
                ),
                Chip(label: Text(completed ? 'Đã kết thúc' : 'Đang làm việc')),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                Text('Check-in: ${_formatTime(record.checkInAt)}'),
                Text(
                  'Check-out: ${completed ? _formatTime(record.checkOutAt!) : 'Chưa có'}',
                ),
                Text(
                  'Tổng giờ làm: ${completed ? _formatDuration(record.workedDuration!) : 'Chưa có'}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _errorMessage(Object error) {
    if (error is AttendanceUnauthorizedException ||
        error is FirebaseException && error.code == 'permission-denied') {
      return 'Không có quyền xem lịch sử chấm công.';
    }
    if (error is FirebaseException && error.code == 'failed-precondition') {
      return 'Truy vấn cần Firestore index. Hãy tạo index theo hướng dẫn triển khai.';
    }
    if (error is FirebaseException &&
        [
          'unavailable',
          'deadline-exceeded',
          'network-request-failed',
        ].contains(error.code)) {
      return 'Không thể kết nối Firestore. Vui lòng thử lại.';
    }
    return 'Không thể tải lịch sử chấm công. Vui lòng thử lại.';
  }

  String _formatTime(DateTime instant) {
    final local = vietnamWallTime(instant);
    return '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}:${_twoDigits(local.second)}';
  }

  String _formatDuration(Duration duration) =>
      '${duration.inHours} giờ ${_twoDigits(duration.inMinutes.remainder(60))} phút '
      '${_twoDigits(duration.inSeconds.remainder(60))} giây';

  String _formatCalendarDate(DateTime date) =>
      '${_twoDigits(date.day)}/${_twoDigits(date.month)}/${date.year}';

  String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
