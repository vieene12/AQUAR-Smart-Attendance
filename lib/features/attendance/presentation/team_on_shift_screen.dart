import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';
import 'package:smart_attendance/features/attendance/data/team_attendance_repository.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';

class TeamOnShiftScreen extends StatefulWidget {
  const TeamOnShiftScreen({required this.profile, this.repository, super.key});

  final UserProfile profile;
  final TeamAttendanceRepository? repository;

  @override
  State<TeamOnShiftScreen> createState() => _TeamOnShiftScreenState();
}

class _TeamOnShiftScreenState extends State<TeamOnShiftScreen> {
  late final TeamAttendanceRepository _repository;
  bool _loading = true;
  String? _error;
  List<TeamAttendanceEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirestoreTeamAttendanceRepository();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _repository.load(
        widget.profile,
        workingTodayOnly: true,
      );
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              error is AttendanceUnauthorizedException ||
                  error is FirebaseException &&
                      error.code == 'permission-denied'
              ? 'Không có quyền xem nhân viên phụ trách.'
              : 'Không thể tải danh sách. Vui lòng thử lại.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_error != null) {
      return Card.filled(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('Thử lại')),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_entries.length} nhân viên đang làm việc',
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Làm mới',
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_entries.isEmpty)
          const Card.filled(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Chưa có nhân viên nào đã check-in và chưa check-out hôm nay.',
              ),
            ),
          ),
        for (final entry in _entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.employee.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Mã nhân viên: ${entry.employee.code ?? 'Chưa cập nhật'}',
                  ),
                  Text(
                    'Chức vụ: ${entry.employee.position ?? 'Chưa cập nhật'}',
                  ),
                  Text(
                    'Ca làm việc: ${entry.employee.shiftStart != null && entry.employee.shiftEnd != null ? '${entry.employee.shiftStart} - ${entry.employee.shiftEnd}' : 'Chưa cập nhật'}',
                  ),
                  Text('Check-in: ${_time(entry.record.checkInAt)}'),
                  const SizedBox(height: 8),
                  Chip(label: Text(entry.isLate ? 'Đi trễ' : 'Đang làm việc')),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _time(DateTime date) {
    final local = vietnamWallTime(date);
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
