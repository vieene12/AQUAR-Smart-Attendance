import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:smart_attendance/features/attendance/data/nfc_availability_checker.dart';
import 'package:smart_attendance/features/attendance/data/nfc_tag_reader.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/kiosk/data/nfc_kiosk_repository.dart';
import 'package:smart_attendance/features/kiosk/data/kiosk_attendance_repository.dart';

class NfcKioskScreen extends StatefulWidget {
  const NfcKioskScreen({
    required this.profile,
    super.key,
    this.repository,
    this.checker,
    this.reader,
    this.writer,
    this.now = DateTime.now,
  });

  final UserProfile profile;
  final KioskLookupRepository? repository;
  final NfcAvailabilityChecker? checker;
  final NfcTagReader? reader;
  final KioskAttendanceWriter? writer;
  final DateTime Function() now;

  @override
  State<NfcKioskScreen> createState() => _NfcKioskScreenState();
}

class _NfcKioskScreenState extends State<NfcKioskScreen>
    with WidgetsBindingObserver {
  late final KioskLookupRepository _repository;
  late final NfcAvailabilityChecker _checker;
  late final NfcTagReader _reader;
  late final KioskAttendanceWriter _writer;
  NfcAvailability? _availability;
  bool _checkingNfc = true;
  bool _scanning = false;
  bool _finishing = false;
  bool _lookingUp = false;
  bool _writing = false;
  Future<void>? _startFuture;
  int _scanSerial = 0;
  String? _message;
  String? _cardUid;
  KioskLookup? _result;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? NfcKioskRepository(FirestoreKioskDataSource());
    _checker = widget.checker ?? DeviceNfcAvailabilityChecker();
    _reader = widget.reader ?? DeviceNfcTagReader();
    _writer =
        widget.writer ??
        TransactionalKioskAttendanceWriter(FirestoreKioskAttendanceStore());
    WidgetsBinding.instance.addObserver(this);
    if (_isOperator) _checkNfc();
  }

  bool get _isOperator =>
      widget.profile.role == UserRole.admin ||
      widget.profile.role == UserRole.manager;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_scanning && !_finishing) {
      (_startFuture ?? Future<void>.value())
          .then((_) => _reader.stop())
          .catchError((Object _) {});
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isOperator) _checkNfc();
    } else if (_scanning && !_finishing) {
      _finish(cancelled: true);
    }
  }

  Future<void> _checkNfc() async {
    if (_scanning) return;
    setState(() => _checkingNfc = true);
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
          _availability = null;
          _checkingNfc = false;
          _message = 'Không thể kiểm tra NFC. Hãy thử lại.';
        });
      }
    }
  }

  Future<void> _scan() async {
    if (_scanning ||
        _lookingUp ||
        _writing ||
        _availability != NfcAvailability.enabled) {
      return;
    }
    final serial = ++_scanSerial;
    setState(() {
      _scanning = true;
      _message = null;
      _cardUid = null;
      _result = null;
    });
    try {
      final availability = await _checker.checkAvailability();
      if (!mounted || !_scanning || _finishing) return;
      if (availability != NfcAvailability.enabled) {
        setState(() {
          _availability = availability;
          _scanning = false;
        });
        return;
      }
      _startFuture = _reader.start(
        onTag: (uid) {
          scheduleMicrotask(() {
            if (!mounted || !_scanning || _finishing || serial != _scanSerial) {
              return;
            }
            _finish(uid: uid);
          });
        },
      );
      await _startFuture;
    } catch (_) {
      if (mounted && _scanning && !_finishing) {
        await _finish(error: 'Không thể đọc thẻ NFC. Hãy thử lại.');
      }
    }
  }

  Future<void> _finish({
    Uint8List? uid,
    bool cancelled = false,
    String? error,
  }) async {
    if (!_scanning || _finishing) return;
    _finishing = true;
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
      _scanning = false;
      _finishing = false;
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    if (error != null) {
      setState(() => _message = error);
      return;
    }
    if (cancelled) {
      setState(() => _message = 'Đã hủy quét NFC.');
      return;
    }
    final cardUid = nfcUidHex(uid);
    if (cardUid == null) {
      setState(() => _message = 'Thẻ này không cung cấp UID để tra cứu.');
      return;
    }
    setState(() {
      _lookingUp = true;
      _cardUid = cardUid;
    });
    try {
      final result = await _repository.lookup(cardUid, widget.now());
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _message = _lookupError(error));
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  String _lookupError(Object error) {
    if (error is KioskOperatorUnauthorized) {
      return 'Tài khoản vận hành không còn quyền chấm công tại quầy.';
    }
    if (error is KioskCardUnavailable) {
      return 'Thẻ đã bị thu hồi hoặc không còn liên kết hợp lệ. Hãy quét lại.';
    }
    if (error is KioskEmployeeInactive) {
      return 'Tài khoản nhân viên đã khóa hoặc không còn hoạt động.';
    }
    if (error is KioskAlreadyCheckedIn) {
      return 'Nhân viên đã Check-in hôm nay. Không thể Check-in lần nữa.';
    }
    if (error is KioskNotCheckedIn) {
      return 'Chưa có Check-in hôm nay. Không thể Check-out.';
    }
    if (error is KioskAlreadyCheckedOut) {
      return 'Nhân viên đã Check-out hôm nay. Không thể Check-out lần nữa.';
    }
    if (error is KioskInvalidAttendance) {
      return 'Bản ghi chấm công không hợp lệ. Không thể cập nhật.';
    }
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' => 'Không có quyền thao tác tại quầy. Kiểm tra tài khoản và Firestore Rules.',
        'unavailable' ||
        'deadline-exceeded' => 'Không thể kết nối Firestore. Hãy thử lại.',
        _ => 'Không thể hoàn tất thao tác NFC. Hãy thử lại.',
      };
    }
    return 'Không thể hoàn tất thao tác NFC. Hãy thử lại.';
  }

  Future<void> _write({required bool checkIn}) async {
    final cardUid = _cardUid;
    final result = _result;
    if (_writing ||
        _scanning ||
        _lookingUp ||
        cardUid == null ||
        result?.cardStatus != KioskCardStatus.active ||
        (checkIn &&
            result?.attendanceStatus != KioskAttendanceStatus.notCheckedIn) ||
        (!checkIn &&
            result?.attendanceStatus != KioskAttendanceStatus.working)) {
      return;
    }
    setState(() {
      _writing = true;
      _message = null;
    });
    try {
      if (checkIn) {
        await _writer.checkIn(cardUid, widget.now());
      } else {
        await _writer.checkOut(cardUid, widget.now());
      }
      if (!mounted) return;
      setState(() {
        _result = null;
        _message = checkIn
            ? 'Đã ghi Check-in NFC tại quầy.'
            : 'Đã ghi Check-out NFC tại quầy.';
      });
      try {
        final refreshed = await _repository.lookup(cardUid, widget.now());
        if (mounted) setState(() => _result = refreshed);
      } catch (_) {
        // The transaction committed; keep its success message and require a new
        // scan before another action when the follow-up read is unavailable.
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = _lookupError(error);
        _result = null;
      });
      try {
        final refreshed = await _repository.lookup(cardUid, widget.now());
        if (mounted) setState(() => _result = refreshed);
      } catch (_) {
        // A fresh scan is required once Firestore becomes available again.
      }
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  String _availabilityMessage() {
    if (_checkingNfc) return 'Đang kiểm tra NFC trên thiết bị...';
    return switch (_availability) {
      NfcAvailability.enabled => 'NFC đang bật. Sẵn sàng quét thẻ.',
      NfcAvailability.disabled =>
        'NFC đang tắt. Bật NFC trong Cài đặt Android để quét.',
      NfcAvailability.unsupported =>
        'Thiết bị không hỗ trợ NFC. Không thể quét thẻ.',
      null => 'Chưa xác định được trạng thái NFC.',
    };
  }

  String _resultMessage(KioskLookup result) => switch (result.cardStatus) {
    KioskCardStatus.unregisteredOrRevoked =>
      'Thẻ chưa đăng ký hoặc đã thu hồi.',
    KioskCardStatus.employeeInactive =>
      'Tài khoản nhân viên đã khóa hoặc không còn hoạt động.',
    KioskCardStatus.active => switch (result.attendanceStatus) {
      KioskAttendanceStatus.notCheckedIn => 'Hôm nay: Chưa chấm công.',
      KioskAttendanceStatus.working => 'Hôm nay: Đang làm việc.',
      KioskAttendanceStatus.completed => 'Hôm nay: Đã kết thúc.',
      null => 'Chưa xác định trạng thái chấm công.',
    },
  };

  @override
  Widget build(BuildContext context) {
    if (!_isOperator) {
      return const Scaffold(
        body: Center(
          child: Text('Bạn không có quyền dùng quầy chấm công NFC.'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Chấm công NFC tại quầy')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(_availabilityMessage()),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _checkingNfc || _scanning ? null : _checkNfc,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Kiểm tra lại NFC'),
                ),
                const SizedBox(height: 12),
                if (_scanning) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text('Đang quét NFC. Đưa thẻ đến mặt lưng điện thoại.'),
                  TextButton(
                    onPressed: _finishing
                        ? null
                        : () => _finish(cancelled: true),
                    child: const Text('Hủy'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed:
                        _checkingNfc ||
                            _lookingUp ||
                            _writing ||
                            _availability != NfcAvailability.enabled
                        ? null
                        : _scan,
                    icon: const Icon(Icons.nfc),
                    label: const Text('Quét thẻ NFC'),
                  ),
                if (_lookingUp) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const Text('Đang tra cứu thẻ và trạng thái hôm nay...'),
                ],
                if (_writing) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const Text('Đang ghi chấm công tại quầy...'),
                ],
                if (_cardUid != null) ...[
                  const SizedBox(height: 12),
                  Text('UID (hex): $_cardUid'),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 16),
                  Card.filled(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_result!.employeeName != null) ...[
                            Text(
                              _result!.employeeName!,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (_result!.cardStatus == KioskCardStatus.active)
                            const Text('Thẻ đang hoạt động.'),
                          Text(_resultMessage(_result!)),
                          if (_result!.cardStatus == KioskCardStatus.active &&
                              _result!.attendanceStatus ==
                                  KioskAttendanceStatus.notCheckedIn) ...[
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _writing
                                  ? null
                                  : () => _write(checkIn: true),
                              child: const Text('Check-in'),
                            ),
                          ],
                          if (_result!.cardStatus == KioskCardStatus.active &&
                              _result!.attendanceStatus ==
                                  KioskAttendanceStatus.working) ...[
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _writing
                                  ? null
                                  : () => _write(checkIn: false),
                              child: const Text('Check-out'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Bản demo Firebase Spark: UID có thể bị sao chép và Firestore Rules không xác minh được thẻ vừa được quét. Chỉ dùng trên quầy có người giám sát; không xem đây là xác thực NFC an toàn.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
