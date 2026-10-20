import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/statistics/data/my_attendance_report_repository.dart';
import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';

class MyAttendanceReportScreen extends StatefulWidget {
  const MyAttendanceReportScreen({
    required this.profile,
    this.repository,
    this.initialDate,
    super.key,
  });

  final UserProfile profile;
  final MyAttendanceReportRepository? repository;
  final DateTime? initialDate;

  @override
  State<MyAttendanceReportScreen> createState() =>
      _MyAttendanceReportScreenState();
}

class _MyAttendanceReportScreenState extends State<MyAttendanceReportScreen> {
  static const _statistics = AttendanceStatisticsService();
  late final MyAttendanceReportRepository _repository;
  late DateTime _selectedInstant;
  AttendancePeriodKind _kind = AttendancePeriodKind.week;
  MyAttendanceReportData? _data;
  bool _loading = true;
  String? _error;
  int _request = 0;

  AttendanceStatisticsPeriod get _period =>
      AttendanceStatisticsPeriod.containing(_kind, _selectedInstant);

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirestoreMyAttendanceReportRepository();
    _selectedInstant = widget.initialDate ?? DateTime.now();
    if (widget.profile.role == UserRole.employee) {
      _load();
    } else {
      _loading = false;
      _error = 'Không có quyền xem báo cáo của tôi.';
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
        period.startDate,
        period.endDate,
      );
      if (!mounted || request != _request) return;
      if (data.uid != widget.profile.uid) {
        throw const MyAttendanceReportAccessException();
      }
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error =
            error is MyAttendanceReportAccessException ||
                (error is FirebaseException &&
                    error.code == 'permission-denied')
            ? 'Không có quyền xem báo cáo của tôi.'
            : 'Không tải được báo cáo. Kiểm tra kết nối và thử lại.';
      });
    }
  }

  void _move(int direction) {
    final period = _period;
    setState(
      () => _selectedInstant = direction < 0
          ? period.start.subtract(const Duration(days: 1))
          : period.end.add(const Duration(days: 1)),
    );
    _load();
  }

  String _hours(int minutes) => '${minutes ~/ 60} giờ ${minutes % 60} phút';

  String _time(DateTime? value) {
    if (value == null) return '—';
    final vietnam = value.toUtc().add(const Duration(hours: 7));
    return '${vietnam.hour.toString().padLeft(2, '0')}:${vietnam.minute.toString().padLeft(2, '0')}';
  }

  String _method(String? value) => switch (value) {
    'biometric' => 'Biometric',
    'nfc' => 'NFC',
    'manual' => 'Manual',
    _ => 'Không rõ phương thức',
  };

  String _status(String? value) => switch (value) {
    'completed' => 'Completed',
    'working' => 'Working',
    _ => 'Trạng thái không hợp lệ',
  };

  @override
  Widget build(BuildContext context) {
    final period = _period;
    final data = _data;
    // Keep both the summary and the daily list scoped to the authenticated UID.
    final records =
        data?.records.where((entry) {
          final attendance = entry.attendance;
          return attendance.employeeUid == data.uid &&
              attendance.workDate != null &&
              period.contains(attendance.workDate!);
        }).toList() ??
        [];
    records.sort(
      (a, b) => b.attendance.workDate!.compareTo(a.attendance.workDate!),
    );
    final stats = data == null
        ? null
        : _statistics.summarize(records, period).enterprise;
    final dayCounts = <String, int>{};
    for (final entry in records) {
      final date = entry.attendance.workDate!;
      dayCounts[date] = (dayCounts[date] ?? 0) + 1;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Báo cáo của tôi')),
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
            if (widget.profile.role == UserRole.employee)
              TextButton(onPressed: _load, child: const Text('Thử lại')),
          ] else if (stats != null) ...[
            if (records.isEmpty)
              const Text('Kỳ này chưa có dữ liệu chấm công.'),
            Text('Tổng giờ công hợp lệ: ${_hours(stats.totalMinutes)}'),
            Text('Số ngày có chấm công: ${stats.attendanceDays}'),
            Text('Completed: ${stats.completedRecords}'),
            Text('Working / chưa Check-out: ${stats.workingRecords}'),
            const SizedBox(height: 8),
            Text(
              'Phương thức chấm công',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Biometric: ${stats.biometricRecords} · NFC: ${stats.nfcRecords} · Manual: ${stats.manualRecords}',
            ),
            Text(
              'Bản ghi có điều chỉnh thủ công: ${stats.manuallyAdjustedRecords}',
            ),
            const Text(
              'Điều chỉnh thủ công được đếm riêng, không cộng thêm vào phương thức.',
            ),
            if (stats.invalidRecords > 0)
              Text(
                '${stats.invalidRecords} ngày có dữ liệu thiếu, xung đột hoặc không hợp lệ; không tính vào tổng.',
              ),
            const SizedBox(height: 16),
            Text(
              'Chi tiết theo ngày',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final entry in records)
              Card(
                child: ListTile(
                  title: Text(entry.attendance.workDate!),
                  subtitle: Text(
                    'Vào: ${_time(entry.attendance.checkInAt)} · Ra: ${_time(entry.attendance.checkOutAt)}\n'
                    '${_status(entry.attendance.status)} · ${_method(entry.attendance.method)}'
                    '${entry.manualRevision != null && entry.manualRevision! > 0 ? ' · Có điều chỉnh thủ công' : ''}'
                    '${entry.attendance.checkInAt == null || entry.attendance.checkOutAt == null ? '\nThiếu giờ chấm công / Check-out' : ''}'
                    '${dayCounts[entry.attendance.workDate!]! > 1 ? '\nNhiều bản ghi cùng ngày; cần kiểm tra xung đột' : ''}',
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
