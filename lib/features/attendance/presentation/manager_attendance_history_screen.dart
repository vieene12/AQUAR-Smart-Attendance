import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';
import 'package:smart_attendance/features/attendance/data/manager_attendance_history_repository.dart';
import 'package:smart_attendance/features/attendance/presentation/attendance_history_screen.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';

class ManagerAttendanceHistoryScreen extends StatefulWidget {
  const ManagerAttendanceHistoryScreen({
    required this.profile,
    this.repository,
    super.key,
  });

  final UserProfile profile;
  final ManagerAttendanceHistoryRepository? repository;

  @override
  State<ManagerAttendanceHistoryScreen> createState() =>
      _ManagerAttendanceHistoryScreenState();
}

class _ManagerAttendanceHistoryScreenState
    extends State<ManagerAttendanceHistoryScreen> {
  late final ManagerAttendanceHistoryRepository _repository;
  List<ManagerHistoryEmployee> _employees = const [];
  ManagerHistoryEmployee? _selected;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? FirestoreManagerAttendanceHistoryRepository();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final allowed = await _repository.canAccess(widget.profile);
      if (!mounted) return;
      if (!allowed) {
        setState(() {
          _loading = false;
          _error = 'Bạn không có quyền xem lịch sử nhân viên.';
        });
        return;
      }
      final employees = await _repository.loadEmployees();
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  String _message(Object error) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'Bạn không có quyền xem lịch sử nhân viên.';
    }
    if (error is FirebaseException &&
        const {
          'unavailable',
          'deadline-exceeded',
          'network-request-failed',
        }.contains(error.code)) {
      return 'Không thể kết nối Firestore. Vui lòng thử lại.';
    }
    return 'Không thể tải danh sách nhân viên. Vui lòng thử lại.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Lịch sử chấm công nhân viên')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null) ...[
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Center(
              child: FilledButton.icon(
                onPressed: _loadEmployees,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ),
          ] else if (_employees.isEmpty)
            const Text(
              'Chưa có nhân viên để xem lịch sử.',
              textAlign: TextAlign.center,
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _selected?.uid,
              decoration: const InputDecoration(
                labelText: 'Chọn nhân viên',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
              items: [
                for (final employee in _employees)
                  DropdownMenuItem(
                    value: employee.uid,
                    child: Text(employee.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (uid) {
                if (uid == null) return;
                setState(() {
                  _selected = _employees.firstWhere(
                    (employee) => employee.uid == uid,
                  );
                });
              },
            ),
            const SizedBox(height: 16),
            if (_selected == null)
              const Text(
                'Chọn một nhân viên để xem lịch sử chấm công.',
                textAlign: TextAlign.center,
              )
            else
              AttendanceHistoryScreen(
                key: ValueKey(_selected!.uid),
                employeeId: _selected!.uid,
                repository: _ManagerHistoryAdapter(_repository),
              ),
          ],
        ],
      ),
    ),
  );
}

class _ManagerHistoryAdapter implements AttendanceRepository {
  const _ManagerHistoryAdapter(this.repository);

  final ManagerAttendanceHistoryRepository repository;

  @override
  Future<List<AttendanceRecord>> loadHistory(
    String employeeId, {
    DateTime? startDate,
    DateTime? endDate,
  }) => repository.loadHistory(
    employeeId,
    startDate: startDate,
    endDate: endDate,
  );

  @override
  Future<AttendanceRecord?> loadToday(String employeeId) =>
      throw UnsupportedError('Manager history is read-only.');

  @override
  Future<AttendanceRecord> checkIn(
    String employeeId, {
    String method = 'biometric',
    String? cardUid,
  }) => throw UnsupportedError('Manager history is read-only.');

  @override
  Future<AttendanceRecord> checkOut(String employeeId, {String? cardUid}) =>
      throw UnsupportedError('Manager history is read-only.');
}
