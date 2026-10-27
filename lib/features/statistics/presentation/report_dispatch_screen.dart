import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/statistics/data/report_dispatch_repository.dart';
import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';
import 'package:smart_attendance/features/statistics/presentation/employee_report_detail_screen.dart';

class ReportDispatchScreen extends StatefulWidget {
  const ReportDispatchScreen({
    required this.profile,
    this.repository,
    this.fileExporter,
    this.initialEmployeeUid,
    this.initialKind = AttendancePeriodKind.month,
    this.initialDate,
    super.key,
  });

  final UserProfile profile;
  final ReportDispatchRepository? repository;
  final ReportFileExporter? fileExporter;
  final String? initialEmployeeUid;
  final AttendancePeriodKind initialKind;
  final DateTime? initialDate;

  @override
  State<ReportDispatchScreen> createState() => _ReportDispatchScreenState();
}

class _ReportDispatchScreenState extends State<ReportDispatchScreen> {
  late final ReportDispatchRepository _repository;
  late final ReportFileExporter _fileExporter;
  late AttendancePeriodKind _kind;
  late DateTime _date;
  List<ReportRecipient> _recipients = const [];
  final Set<String> _selected = {};
  List<ReportSendResult>? _results;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _progress;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirebaseReportDispatchRepository();
    _fileExporter = widget.fileExporter ?? const ReportFileExporter();
    _kind = widget.initialKind;
    final initial = widget.initialDate ?? DateTime.now();
    _date = DateTime.utc(initial.year, initial.month, initial.day, 12);
    if (widget.initialEmployeeUid != null) {
      _selected.add(widget.initialEmployeeUid!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  AttendanceStatisticsPeriod get _period =>
      AttendanceStatisticsPeriod.containing(_kind, _date);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final recipients = await _repository.listRecipients(widget.profile);
      if (!mounted) return;
      setState(() {
        _recipients = recipients;
        _selected.removeWhere(
          (uid) => !recipients.any((person) => person.uid == uid),
        );
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _message(error);
        });
      }
    }
  }

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(_date.year, _date.month, _date.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Chọn ngày thuộc kỳ báo cáo',
    );
    if (selected != null && mounted) {
      setState(() {
        _date = DateTime.utc(selected.year, selected.month, selected.day, 12);
        _results = null;
      });
    }
  }

  Future<void> _send() async {
    if (_busy || _selected.isEmpty) return;
    final recipients = _recipients
        .where((person) => _selected.contains(person.uid))
        .toList();
    setState(() {
      _busy = true;
      _error = null;
      _results = null;
      _progress = 'Đang gửi email: 0/${recipients.length}';
    });
    try {
      final results = await _repository.send(
        recipients: recipients,
        kind: _kind,
        date: _date,
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _progress = 'Đang gửi email: $done/$total');
          }
        },
      );
      if (mounted) {
        setState(() => _results = results);
        final sent = results.where((item) => item.success).length;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Đã gửi thành công $sent/${results.length} nhân viên'),
            content: SizedBox(
              width: 400,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in results.where((item) => !item.success))
                    ListTile(
                      title: Text(item.name),
                      subtitle: Text(item.message),
                    ),
                  if (sent == results.length)
                    const Text('Tất cả email đã được máy chủ chấp nhận.'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _export() async {
    if (_busy || _selected.isEmpty) return;
    final recipients = _recipients
        .where((person) => _selected.contains(person.uid))
        .toList();
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Đang tạo báo cáo: 0/${recipients.length}';
    });
    try {
      final result = await _repository.export(
        recipients: recipients,
        kind: _kind,
        date: _date,
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _progress = 'Đang tạo báo cáo: $done/$total');
          }
        },
      );
      if (!mounted) return;
      final bytes = result.bytes;
      if (bytes != null) {
        final saved = await _fileExporter.save(result.fileName, bytes);
        if (!mounted) return;
        if (saved) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Đã lưu ${result.fileName}')));
        }
      }
      if (result.failures.isNotEmpty && mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              'Xuất được ${recipients.length - result.failures.length}/${recipients.length} báo cáo',
            ),
            content: SizedBox(
              width: 400,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in result.failures)
                    ListTile(
                      title: Text(item.name),
                      subtitle: Text(item.message),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  void _openDetail() {
    if (_busy || _selected.length != 1) return;
    final person = _recipients.firstWhere(
      (item) => item.uid == _selected.single,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmployeeReportDetailScreen(
          person: person,
          kind: _kind,
          date: _date,
          repository: _repository,
          fileExporter: _fileExporter,
        ),
      ),
    );
  }

  String _message(Object error) {
    if (error is FirebaseFunctionsException &&
        error.message != null &&
        error.message!.isNotEmpty) {
      return error.message!;
    }
    return 'Không thể xử lý yêu cầu. Kiểm tra kết nối và thử lại.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final period = _period;
    final count = _selected.length;
    final results = _results;
    final successCount = results?.where((entry) => entry.success).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Báo cáo nhân viên')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_progress != null) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 6),
                Text(_progress!),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Đã chọn: $count nhân viên',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: _busy || count == 0
                        ? null
                        : () => setState(() {
                            _selected.clear();
                            _results = null;
                          }),
                    child: const Text('Bỏ chọn tất cả'),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy || count == 0 ? null : _send,
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Gửi email'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy || count == 0 ? null : _export,
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('Xuất file'),
                    ),
                  ),
                ],
              ),
              if (count == 1)
                TextButton.icon(
                  onPressed: _busy ? null : _openDetail,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Xem chi tiết'),
                ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card.filled(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Kỳ báo cáo và bảng lương',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<AttendancePeriodKind>(
                            initialValue: _kind,
                            decoration: const InputDecoration(
                              labelText: 'Loại kỳ',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: AttendancePeriodKind.week,
                                child: Text('Tuần'),
                              ),
                              DropdownMenuItem(
                                value: AttendancePeriodKind.month,
                                child: Text('Tháng'),
                              ),
                              DropdownMenuItem(
                                value: AttendancePeriodKind.quarter,
                                child: Text('Quý'),
                              ),
                              DropdownMenuItem(
                                value: AttendancePeriodKind.year,
                                child: Text('Năm'),
                              ),
                            ],
                            onChanged: _busy
                                ? null
                                : (kind) {
                                    if (kind != null) {
                                      setState(() {
                                        _kind = kind;
                                        _results = null;
                                      });
                                    }
                                  },
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _chooseDate,
                            icon: const Icon(Icons.calendar_month),
                            label: Text(
                              '${period.startDate} – ${period.endDate}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_error != null && _recipients.isEmpty)
                    Card.filled(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(_error!),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Thử lại'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        const Spacer(),
                        TextButton(
                          onPressed: _busy || _recipients.isEmpty
                              ? null
                              : () => setState(() {
                                  _selected.addAll(
                                    _recipients.map((person) => person.uid),
                                  );
                                  _results = null;
                                }),
                          child: const Text('Chọn tất cả'),
                        ),
                      ],
                    ),
                    if (_recipients.isEmpty)
                      const Card.filled(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'Không có nhân viên trong phạm vi được phép.',
                          ),
                        ),
                      ),
                    for (final person in _recipients)
                      Card(
                        child: CheckboxListTile(
                          value: _selected.contains(person.uid),
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  if (value == true) {
                                    _selected.add(person.uid);
                                  } else {
                                    _selected.remove(person.uid);
                                  }
                                  _results = null;
                                }),
                          title: Text(person.name),
                          subtitle: Text(
                            '${person.code ?? 'Chưa có mã'}\n${person.email ?? 'Chưa đăng ký email'}',
                          ),
                          isThreeLine: true,
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    if (results != null)
                      Card.filled(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Gửi thành công: $successCount · Thất bại: ${results.length - successCount}',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              for (final result in results.where((entry) => !entry.success))
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    '${result.name} – ${result.message}',
                                    style: TextStyle(
                                      color: result.success
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.error,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
