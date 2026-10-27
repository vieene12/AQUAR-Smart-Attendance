import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';
import 'package:smart_attendance/features/attendance/data/team_attendance_repository.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';

enum _Period { today, week, month }

class TeamAttendanceHistoryScreen extends StatefulWidget {
  const TeamAttendanceHistoryScreen({
    required this.profile,
    this.repository,
    super.key,
  });

  final UserProfile profile;
  final TeamAttendanceRepository? repository;

  @override
  State<TeamAttendanceHistoryScreen> createState() =>
      _TeamAttendanceHistoryScreenState();
}

class _TeamAttendanceHistoryScreenState
    extends State<TeamAttendanceHistoryScreen> {
  late final TeamAttendanceRepository _repository;
  _Period _period = _Period.today;
  bool _loading = true;
  String? _error;
  List<TeamAttendanceEntry> _entries = const [];
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirestoreTeamAttendanceRepository();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final serial = ++_serial;
    setState(() {
      _loading = true;
      _error = null;
    });
    final today = vietnamWallTime(DateTime.now());
    final date = DateTime(today.year, today.month, today.day);
    final start = switch (_period) {
      _Period.today => date,
      _Period.week => date.subtract(
        Duration(days: date.weekday - DateTime.monday),
      ),
      _Period.month => DateTime(date.year, date.month),
    };
    final end = switch (_period) {
      _Period.today => date,
      _Period.week => start.add(const Duration(days: 6)),
      _Period.month => DateTime(date.year, date.month + 1, 0),
    };
    try {
      final entries = await _repository.load(
        widget.profile,
        startDate: start,
        endDate: end,
      );
      if (mounted && serial == _serial) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted && serial == _serial) {
        setState(() {
          _loading = false;
          _error =
              error is AttendanceUnauthorizedException ||
                  error is FirebaseException &&
                      error.code == 'permission-denied'
              ? 'Không có quyền xem lịch sử chấm công.'
              : 'Không thể tải lịch sử chấm công. Vui lòng thử lại.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final period in _Period.values)
              FilterChip(
                label: Text(switch (period) {
                  _Period.today => 'Hôm nay',
                  _Period.week => 'Tuần này',
                  _Period.month => 'Tháng này',
                }),
                selected: _period == period,
                onSelected: (_) {
                  if (_period != period) {
                    setState(() => _period = period);
                    _load();
                  }
                },
              ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                '${_entries.length} bản ghi',
                style: theme.textTheme.titleSmall,
              ),
            ),
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Làm mới',
            ),
          ],
        ),
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
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('Thử lại')),
                ],
              ),
            ),
          )
        else if (_entries.isEmpty)
          const Card.filled(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Không có bản ghi chấm công trong thời gian đã chọn.',
              ),
            ),
          )
        else
          for (final entry in _entries) _card(entry),
      ],
    );
  }

  Widget _card(TeamAttendanceEntry entry) {
    final record = entry.record;
    final completed = record.checkOutAt != null;
    final date = record.workDate.split('-');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.employee.name,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 8),
            Text('Ngày: ${date[2]}/${date[1]}/${date[0]}'),
            Text('Check-in: ${_time(record.checkInAt)}'),
            Text(
              'Check-out: ${completed ? _time(record.checkOutAt!) : 'Chưa check-out'}',
            ),
            if (completed)
              Text(
                'Tổng thời gian làm việc: ${_duration(record.workedDuration!)}',
              ),
            const SizedBox(height: 8),
            Chip(label: Text(completed ? 'Đã hoàn thành ca' : 'Đang làm việc')),
          ],
        ),
      ),
    );
  }

  String _time(DateTime instant) {
    final date = vietnamWallTime(instant);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _duration(Duration duration) =>
      '${duration.inHours} giờ ${(duration.inMinutes % 60).toString().padLeft(2, '0')} phút';
}
