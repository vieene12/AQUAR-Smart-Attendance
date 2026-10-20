import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:smart_attendance/features/admin/nfc_cards/data/nfc_card_repository.dart';
import 'package:smart_attendance/features/attendance/data/nfc_availability_checker.dart';
import 'package:smart_attendance/features/attendance/data/nfc_tag_reader.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';

class NfcCardScreen extends StatefulWidget {
  const NfcCardScreen({
    required this.profile,
    super.key,
    this.repository,
    this.checker,
    this.reader,
  });

  final UserProfile profile;
  final NfcCardRepository? repository;
  final NfcAvailabilityChecker? checker;
  final NfcTagReader? reader;

  @override
  State<NfcCardScreen> createState() => _NfcCardScreenState();
}

class _NfcCardScreenState extends State<NfcCardScreen>
    with WidgetsBindingObserver {
  late final NfcCardRepository _repository;
  late final NfcAvailabilityChecker _checker;
  late final NfcTagReader _reader;
  List<EmployeeNfcCard>? _employees;
  String? _loadError;
  int _loadSerial = 0;
  NfcAvailability? _availability;
  bool _checkingNfc = true;
  String? _nfcError;
  String? _selectedUid;
  String? _scanningUid;
  bool _finishingScan = false;
  bool _saving = false;
  Future<void>? _startFuture;
  int _scanSerial = 0;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? NfcCardRepository(FirestoreNfcCardStore());
    _checker = widget.checker ?? DeviceNfcAvailabilityChecker();
    _reader = widget.reader ?? DeviceNfcTagReader();
    WidgetsBinding.instance.addObserver(this);
    if (widget.profile.role == UserRole.admin) {
      _load();
      _checkNfc();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_scanningUid != null && !_finishingScan) {
      (_startFuture ?? Future<void>.value())
          .then((_) => _reader.stop())
          .catchError((Object _) {});
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNfc();
    } else if (_scanningUid != null && !_finishingScan) {
      _finishScan(cancelled: true);
    }
  }

  Future<void> _load() async {
    final serial = ++_loadSerial;
    setState(() => _loadError = null);
    try {
      final employees = await _repository.loadEmployees();
      if (mounted && serial == _loadSerial) {
        setState(() => _employees = employees);
      }
    } catch (error) {
      if (mounted && serial == _loadSerial) {
        setState(() => _loadError = _errorMessage(error));
      }
    }
  }

  Future<void> _checkNfc() async {
    if (_scanningUid != null) return;
    setState(() {
      _checkingNfc = true;
      _nfcError = null;
    });
    try {
      final availability = await _checker.checkAvailability();
      if (mounted) {
        setState(() {
          _availability = availability;
          _checkingNfc = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _checkingNfc = false;
          _nfcError = 'Không thể kiểm tra NFC. Hãy thử lại.';
        });
      }
    }
  }

  Future<void> _scan(EmployeeNfcCard employee) async {
    if (_scanningUid != null ||
        _saving ||
        employee.account.status != 'active' ||
        _availability != NfcAvailability.enabled) {
      return;
    }
    final serial = ++_scanSerial;
    setState(() => _scanningUid = employee.account.uid);
    try {
      final availability = await _checker.checkAvailability();
      if (!mounted || _scanningUid == null || _finishingScan) return;
      if (availability != NfcAvailability.enabled) {
        setState(() {
          _availability = availability;
          _scanningUid = null;
        });
        return;
      }
      _startFuture = _reader.start(
        onTag: (uid) {
          // Defer in case a reader invokes the callback before start returns.
          scheduleMicrotask(() {
            if (!mounted ||
                _scanningUid == null ||
                _finishingScan ||
                serial != _scanSerial) {
              return;
            }
            _finishScan(uid: uid);
          });
        },
      );
      await _startFuture;
    } catch (_) {
      if (mounted && _scanningUid != null && !_finishingScan) {
        await _finishScan(error: 'Không thể đọc thẻ NFC. Hãy thử lại.');
      }
    }
  }

  Future<void> _finishScan({
    Uint8List? uid,
    bool cancelled = false,
    String? error,
  }) async {
    final employeeUid = _scanningUid;
    if (employeeUid == null || _finishingScan) return;
    _finishingScan = true;
    try {
      if (_startFuture != null) {
        try {
          await _startFuture;
        } catch (_) {
          error ??= 'Không thể mở phiên NFC. Hãy thử lại.';
        }
        await _reader.stop();
      }
    } catch (_) {
      error = 'Không thể kết thúc phiên NFC. Hãy thử lại.';
    } finally {
      _startFuture = null;
      _scanningUid = null;
      _finishingScan = false;
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    if (error != null) {
      _showMessage(error);
      return;
    }
    if (cancelled) {
      _showMessage('Đã hủy quét NFC.');
      return;
    }
    final cardUid = nfcUidHex(uid);
    if (cardUid == null) {
      _showMessage('Thẻ này không cung cấp UID để đăng ký.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _repository.register(employeeUid, cardUid);
      if (!mounted) return;
      await _load();
      if (mounted) _showMessage('Đã đăng ký thẻ $cardUid.');
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _revoke(EmployeeNfcCard employee) async {
    if (_saving || _scanningUid != null || employee.cardUid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Thu hồi thẻ NFC?'),
        content: Text(
          'Thu hồi thẻ của ${employee.account.name ?? employee.account.email ?? employee.account.uid}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Thu hồi'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _saving = true);
    try {
      await _repository.revoke(employee.account.uid);
      if (!mounted) return;
      await _load();
      if (mounted) _showMessage('Đã thu hồi thẻ NFC.');
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _errorMessage(Object error) {
    if (error is NfcCardConflict) {
      return 'Thẻ này đã được đăng ký cho nhân viên khác.';
    }
    if (error is NfcCardAlreadyRegistered) {
      return 'Thẻ này đã đăng ký cho nhân viên đã chọn.';
    }
    if (error is NfcEmployeeUnavailable) {
      return 'Tài khoản nhân viên không hoạt động hoặc không còn tồn tại.';
    }
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' => 'Không có quyền quản lý thẻ NFC. Kiểm tra quyền Admin và Firestore Rules.',
        'unavailable' ||
        'deadline-exceeded' => 'Không thể kết nối Firestore. Hãy thử lại.',
        _ => 'Không thể lưu thẻ NFC. Hãy thử lại.',
      };
    }
    return 'Không thể quản lý thẻ NFC. Hãy thử lại.';
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.profile.role != UserRole.admin) {
      return const Scaffold(
        body: Center(child: Text('Bạn không có quyền quản lý thẻ NFC.')),
      );
    }
    final employees = _employees;
    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý thẻ NFC')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(_availabilityMessage()),
            if (_nfcError != null) Text(_nfcError!),
            TextButton.icon(
              onPressed: _checkingNfc || _scanningUid != null
                  ? null
                  : _checkNfc,
              icon: const Icon(Icons.refresh),
              label: const Text('Kiểm tra lại NFC'),
            ),
            const Text(
              'UID chỉ là mã nhận dạng thẻ, không phải bằng chứng xác thực an toàn. Ứng dụng không ghi dữ liệu lên thẻ.',
            ),
            const SizedBox(height: 12),
            if (_loadError != null) ...[
              Text(_loadError!),
              TextButton(
                onPressed: _load,
                child: const Text('Tải lại danh sách'),
              ),
            ] else if (employees == null)
              const Center(child: CircularProgressIndicator())
            else if (employees.isEmpty)
              const Text('Chưa có tài khoản nhân viên.')
            else ...[
              Text(
                'Nhân viên (${employees.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              for (final employee in employees) _employeeCard(employee),
            ],
          ],
        ),
      ),
    );
  }

  String _availabilityMessage() {
    if (_checkingNfc) return 'Đang kiểm tra NFC trên thiết bị...';
    if (_nfcError != null) return 'Không xác định được trạng thái NFC.';
    return switch (_availability) {
      NfcAvailability.enabled => 'NFC đang bật. Có thể đăng ký thẻ.',
      NfcAvailability.disabled =>
        'NFC đang tắt. Bật NFC trong Cài đặt Android để quét thẻ.',
      NfcAvailability.unsupported =>
        'Thiết bị không hỗ trợ NFC. Vẫn có thể xem danh sách và thu hồi thẻ.',
      null => 'Chưa xác định được trạng thái NFC.',
    };
  }

  Widget _employeeCard(EmployeeNfcCard employee) {
    final selected = _selectedUid == employee.account.uid;
    final scanning = _scanningUid == employee.account.uid;
    final hasCard = employee.cardUid != null;
    return Card(
      child: Column(
        children: [
          ListTile(
            selected: selected,
            title: Text(
              employee.account.name ??
                  employee.account.email ??
                  employee.account.uid,
            ),
            subtitle: Text(
              [
                hasCard
                    ? 'Đã đăng ký thẻ: ${employee.cardUid}'
                    : 'Chưa đăng ký thẻ',
                employee.account.status == 'active'
                    ? 'Đang hoạt động'
                    : 'Tài khoản bị khóa',
              ].join(' • '),
            ),
            trailing: Icon(selected ? Icons.expand_less : Icons.expand_more),
            onTap: _scanningUid != null || _saving
                ? null
                : () => setState(
                    () => _selectedUid = selected ? null : employee.account.uid,
                  ),
          ),
          if (selected) ...[
            if (scanning) ...[
              const LinearProgressIndicator(),
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Đang quét NFC. Đưa thẻ đến mặt lưng điện thoại.'),
              ),
              TextButton(
                onPressed: _finishingScan
                    ? null
                    : () => _finishScan(cancelled: true),
                child: const Text('Hủy'),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed:
                          _saving ||
                              _scanningUid != null ||
                              _checkingNfc ||
                              _nfcError != null ||
                              _availability != NfcAvailability.enabled ||
                              employee.account.status != 'active'
                          ? null
                          : () => _scan(employee),
                      icon: const Icon(Icons.nfc),
                      label: Text(
                        hasCard ? 'Đăng ký thẻ thay thế' : 'Đăng ký thẻ',
                      ),
                    ),
                    if (hasCard)
                      OutlinedButton.icon(
                        onPressed: _saving || _scanningUid != null
                            ? null
                            : () => _revoke(employee),
                        icon: const Icon(Icons.remove_circle_outline),
                        label: const Text('Thu hồi thẻ'),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
