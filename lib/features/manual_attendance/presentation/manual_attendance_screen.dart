import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/manual_attendance/data/manual_attendance_repository.dart';
import 'package:smart_attendance/features/manual_attendance/data/manual_attendance_writer.dart';

class ManualAttendanceScreen extends StatefulWidget {
  const ManualAttendanceScreen({
    required this.profile,
    super.key,
    this.repository,
    this.writer,
    this.initialDate,
  });

  final UserProfile profile;
  final ManualAttendanceRepository? repository;
  final ManualAttendanceWriter? writer;
  final DateTime? initialDate;

  @override
  State<ManualAttendanceScreen> createState() => _ManualAttendanceScreenState();
}

class _ManualAttendanceScreenState extends State<ManualAttendanceScreen> {
  late final ManualAttendanceRepository _repository;
  late final ManualAttendanceWriter _writer;
  late DateTime _date;
  final _search = TextEditingController();
  final _checkIn = TextEditingController();
  final _checkOut = TextEditingController();
  final _reason = TextEditingController();
  List<ManualEmployee> _employees = const [];
  ManualEmployee? _selected;
  ManualAttendanceRecord? _record;
  bool _loadingEmployees = true;
  bool _loadingRecord = false;
  bool _saving = false;
  bool _denied = false;
  String? _employeeError;
  String? _recordError;
  String? _saveMessage;
  String? _saveError;
  int _recordRequest = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirestoreManualAttendanceRepository();
    _writer =
        widget.writer ??
        TransactionalManualAttendanceWriter(FirestoreManualAttendanceStore());
    _date = widget.initialDate ?? DateTime.now();
    _search.addListener(_refreshSearch);
    if (widget.profile.role == UserRole.admin ||
        widget.profile.role == UserRole.manager) {
      _loadEmployees();
    } else {
      _denied = true;
      _loadingEmployees = false;
    }
  }

  @override
  void dispose() {
    _search.removeListener(_refreshSearch);
    _search.dispose();
    _checkIn.dispose();
    _checkOut.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _refreshSearch() => setState(() {});

  Future<void> _loadEmployees() async {
    setState(() {
      _loadingEmployees = true;
      _employeeError = null;
    });
    try {
      final allowed = await _repository.canAccess(widget.profile);
      if (!mounted) return;
      if (!allowed) {
        setState(() {
          _denied = true;
          _loadingEmployees = false;
        });
        return;
      }
      final employees = await _repository.loadEmployees();
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _loadingEmployees = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingEmployees = false;
        _employeeError = _errorMessage(error);
      });
    }
  }

  void _selectEmployee(ManualEmployee employee) {
    setState(() {
      _selected = employee;
      _record = null;
      _recordError = null;
      _saveMessage = null;
      _saveError = null;
    });
    _loadRecord();
  }

  Future<void> _chooseDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Chọn ngày chấm công',
    );
    if (!mounted || chosen == null) return;
    setState(() => _date = chosen);
    _saveMessage = null;
    _saveError = null;
    if (_selected != null) _loadRecord();
  }

  DateTime? _parseTime(String value) {
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$')
        .firstMatch(value.trim());
    if (match == null) return null;
    return DateTime.utc(
      _date.year,
      _date.month,
      _date.day,
      int.parse(match.group(1)!) - 7,
      int.parse(match.group(2)!),
    );
  }

  Future<void> _save() async {
    final employee = _selected;
    if (_saving || _loadingRecord || employee == null) return;
    final reason = _reason.text.trim();
    final current = _record;
    final checkIn =
        current?.checkInAt != null &&
            _checkIn.text.trim() == _time(current!.checkInAt)
        ? current.checkInAt
        : _parseTime(_checkIn.text);
    final checkOut = _checkOut.text.trim().isEmpty
        ? null
        : current?.checkOutAt != null &&
              _checkOut.text.trim() == _time(current!.checkOutAt)
        ? current.checkOutAt
        : _parseTime(_checkOut.text);
    String? error;
    if (reason.isEmpty || reason.length > 500) {
      error = 'Nhập lý do điều chỉnh (tối đa 500 ký tự).';
    } else if (checkIn == null ||
        (_checkOut.text.trim().isNotEmpty && checkOut == null)) {
      error = 'Nhập giờ hợp lệ theo định dạng HH:mm.';
    } else if (checkOut != null && !checkOut.isAfter(checkIn)) {
      error = 'Giờ ra phải sau giờ vào; chưa hỗ trợ ca qua đêm.';
    }
    if (error != null) {
      setState(() {
        _saveError = error;
        _saveMessage = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
      _saveMessage = null;
    });
    try {
      await _writer.save(
        ManualAttendanceChange(
          employeeUid: employee.uid,
          date: _date,
          checkInAt: checkIn!,
          checkOutAt: checkOut,
          reason: reason,
          expected: _record,
        ),
      );
      if (!mounted) return;
      await _loadRecord();
      if (!mounted) return;
      setState(() {
        _saveMessage = _recordError == null
            ? 'Đã lưu chấm công và tải lại bản ghi.'
            : 'Đã lưu chấm công, nhưng chưa tải lại được bản ghi. Hãy thử lại.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saveError = _writeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _writeError(Object error) {
    if (error is ManualInvalidInput) return error.message;
    if (error is ManualWriteConflict) {
      return 'Bản ghi đã thay đổi hoặc thao tác trùng. Tải lại trước khi lưu.';
    }
    if (error is ManualWriteUnauthorized || error is ManualEmployeeInactive) {
      return 'Tài khoản vận hành hoặc nhân viên không còn hoạt động.';
    }
    if (error is ManualInvalidRecord) return 'Bản ghi hiện có không hợp lệ.';
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' => 'Không có quyền lưu chấm công. Kiểm tra tài khoản và Firestore Rules.',
        'unavailable' || 'deadline-exceeded' => 'Mất kết nối Firestore. Chưa xác nhận được thao tác; hãy tải lại bản ghi.',
        _ => 'Không thể lưu chấm công. Hãy thử lại.',
      };
    }
    return 'Không thể lưu chấm công. Hãy thử lại.';
  }

  Future<void> _loadRecord() async {
    final employee = _selected;
    if (employee == null) return;
    final request = ++_recordRequest;
    setState(() {
      _loadingRecord = true;
      _recordError = null;
      _record = null;
    });
    try {
      final record = await _repository.loadRecord(employee.uid, _date);
      if (!mounted || request != _recordRequest) return;
      setState(() {
        _record = record;
        _loadingRecord = false;
      });
      _checkIn.text = _time(record?.checkInAt);
      _checkOut.text = _time(record?.checkOutAt);
      _reason.clear();
    } catch (error) {
      if (!mounted || request != _recordRequest) return;
      setState(() {
        _loadingRecord = false;
        _recordError = _errorMessage(error);
      });
    }
  }

  String _errorMessage(Object error) {
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' => 'Không có quyền đọc dữ liệu chấm công.',
        'unavailable' ||
        'deadline-exceeded' => 'Không thể kết nối Firestore. Hãy thử lại.',
        _ => 'Không thể tải dữ liệu. Hãy thử lại.',
      };
    }
    return 'Không thể tải dữ liệu. Hãy thử lại.';
  }

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  // Attendance uses Vietnam work dates, independent of the device time zone.
  String _time(DateTime? value) {
    if (value == null) return '';
    final vietnam = value.toUtc().add(const Duration(hours: 7));
    return '${vietnam.hour.toString().padLeft(2, '0')}:'
        '${vietnam.minute.toString().padLeft(2, '0')}';
  }

  String _method(String? value) => switch (value) {
    'biometric' => 'Sinh trắc học (biometric)',
    'nfc' => 'Thẻ NFC',
    'manual' => 'Thủ công (manual)',
    null => 'Chưa có',
    _ => value,
  };

  String _status(ManualAttendanceRecord? record) {
    if (record == null) return 'Chưa có bản ghi';
    return switch (record.status) {
      'working' => 'Đang làm việc',
      'completed' => 'Đã kết thúc',
      null => 'Chưa xác định',
      _ => record.status!,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_denied) {
      return const Scaffold(
        body: Center(child: Text('Bạn không có quyền xem chấm công thủ công.')),
      );
    }
    final query = _search.text.trim().toLowerCase();
    final filtered = _employees
        .where((employee) => employee.name.toLowerCase().contains(query))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Chấm công thủ công')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Xem bản ghi và điều chỉnh chấm công cho nhân viên.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    labelText: 'Tìm nhân viên theo tên',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (_loadingEmployees)
                  const Center(child: CircularProgressIndicator())
                else if (_employeeError != null) ...[
                  Text(_employeeError!),
                  TextButton(
                    onPressed: _loadEmployees,
                    child: const Text('Thử lại'),
                  ),
                ] else if (_employees.isEmpty)
                  const Text('Chưa có nhân viên.')
                else if (filtered.isEmpty)
                  const Text('Không tìm thấy nhân viên phù hợp.')
                else
                  ...filtered.map(
                    (employee) => ListTile(
                      title: Text(employee.name),
                      selected: _selected?.uid == employee.uid,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _saving ? null : () => _selectEmployee(employee),
                    ),
                  ),
                if (_selected != null) ...[
                  const Divider(height: 32),
                  Text(
                    'Nhân viên: ${_selected!.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _chooseDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text('Ngày: ${_dateLabel(_date)}'),
                  ),
                  const SizedBox(height: 12),
                  if (_loadingRecord)
                    const Center(child: CircularProgressIndicator())
                  else if (_recordError != null) ...[
                    Text(_recordError!),
                    TextButton(
                      onPressed: _loadRecord,
                      child: const Text('Thử lại bản ghi'),
                    ),
                  ] else ...[
                    Text('Trạng thái: ${_status(_record)}'),
                    Text(
                      'Check-in: ${_time(_record?.checkInAt).isEmpty ? 'Chưa có' : _time(_record?.checkInAt)}',
                    ),
                    Text(
                      'Check-out: ${_time(_record?.checkOutAt).isEmpty ? 'Chưa có' : _time(_record?.checkOutAt)}',
                    ),
                    Text('Phương thức vào: ${_method(_record?.method)}'),
                    Text(
                      'Phương thức ra: ${_method(_record?.checkOutMethod ?? (_record?.checkOutAt != null ? _record?.method : null))}',
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Nội dung điều chỉnh',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _checkIn,
                      keyboardType: TextInputType.datetime,
                      decoration: const InputDecoration(
                        labelText: 'Giờ vào (HH:mm)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _checkOut,
                      keyboardType: TextInputType.datetime,
                      decoration: const InputDecoration(
                        labelText: 'Giờ ra (HH:mm)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reason,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Lý do điều chỉnh',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_saveError != null) Text(_saveError!),
                    if (_saveMessage != null) Text(_saveMessage!),
                    if (_saving) const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Lưu chấm công'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
