import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';
import 'package:smart_attendance/features/attendance/data/attendance_location_gate.dart';
import 'package:smart_attendance/features/attendance/data/biometric_authenticator.dart';
import 'package:smart_attendance/features/attendance/data/location_service.dart';
import 'package:smart_attendance/features/attendance/data/nfc_availability_checker.dart';
import 'package:smart_attendance/features/attendance/data/nfc_tag_reader.dart';

enum _AttendanceMethod { biometric, nfc }

/// Giao diện chấm công của nhân viên.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    required this.employeeId,
    super.key,
    this.now = DateTime.now,
    this.authenticator,
    this.repository,
    this.locationGate,
    this.nfcChecker,
    this.nfcReader,
  });

  final String employeeId;
  final DateTime Function() now;
  final BiometricAuthenticator? authenticator;
  final AttendanceRepository? repository;
  final AttendanceLocationGate? locationGate;
  final NfcAvailabilityChecker? nfcChecker;
  final NfcTagReader? nfcReader;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with WidgetsBindingObserver {
  late DateTime _currentTime;
  late final BiometricAuthenticator _authenticator;
  late final AttendanceRepository _repository;
  late final AttendanceLocationGate _locationGate;
  late final NfcAvailabilityChecker _nfcChecker;
  late final NfcTagReader _nfcReader;
  Timer? _clockTimer;
  bool _isAuthenticating = false;
  bool _loading = true;
  AttendanceRecord? _record;
  String? _loadError;
  int _loadRequestSerial = 0;
  _AttendanceMethod _method = _AttendanceMethod.biometric;
  NfcAvailability? _nfcAvailability;
  bool _checkingNfc = true;
  bool _nfcCheckFailed = false;
  int _nfcRequestSerial = 0;
  bool _scanningNfc = false;
  bool _finishingNfc = false;
  Future<void>? _nfcStartFuture;
  int _nfcScanSerial = 0;
  String? _nfcUid;
  String? _nfcScanMessage;

  @override
  void initState() {
    super.initState();
    _currentTime = widget.now();
    _authenticator = widget.authenticator ?? LocalBiometricAuthenticator();
    _repository = widget.repository ?? FirestoreAttendanceRepository();
    _locationGate = widget.locationGate ?? ConfiguredAttendanceLocationGate();
    _nfcChecker = widget.nfcChecker ?? DeviceNfcAvailabilityChecker();
    _nfcReader = widget.nfcReader ?? DeviceNfcTagReader();
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final previousDate = vietnamWorkDate(_currentTime);
      final nextTime = widget.now();
      setState(() => _currentTime = nextTime);
      if (vietnamWorkDate(nextTime) != previousDate) {
        _loadToday();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadToday();
        _checkNfc();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    if (_scanningNfc && !_finishingNfc) {
      // startSession may still be registering reader mode when this route closes.
      (_nfcStartFuture ?? Future<void>.value())
          .then((_) => _nfcReader.stop())
          .catchError((Object _) {});
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNfc();
    } else if (_scanningNfc && !_finishingNfc) {
      _finishNfcScan(message: 'Đã hủy quét NFC.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card.filled(
          color: colors.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 40,
                  color: colors.onPrimaryContainer,
                ),
                const SizedBox(height: 12),
                Text(
                  'Giờ Việt Nam hiện tại',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _formatTime(vietnamWallTime(_currentTime)),
                    style: theme.textTheme.displayMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatDate(vietnamWallTime(_currentTime)),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Trạng thái chấm công', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(
                  _loading
                      ? 'Đang tải trạng thái...'
                      : _loadError != null
                      ? 'Chưa xác định'
                      : _record == null
                      ? 'Chưa chấm công'
                      : _record!.checkOutAt == null
                      ? 'Đang làm việc'
                      : 'Đã kết thúc',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _loading
                      ? 'Đang đọc bản ghi từ Firestore...'
                      : _loadError ??
                            (_record == null
                                ? 'Chưa có dữ liệu chấm công hôm nay.'
                                : _record!.checkOutAt == null
                                ? 'Đã ghi nhận giờ vào từ Firestore.'
                                : 'Đã ghi nhận giờ ra từ Firestore.'),
                  style: theme.textTheme.bodyMedium,
                ),
                if (_loadError != null)
                  TextButton.icon(
                    onPressed: _loadToday,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tải lại'),
                  ),
                const SizedBox(height: 16),
                Text('Các trạng thái', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('Chưa chấm công')),
                    Chip(label: Text('Đang làm việc')),
                    Chip(label: Text('Đã kết thúc')),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Thời gian làm việc', style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 600 ? 3 : 1;
                    const gap = 12.0;
                    final itemWidth =
                        (constraints.maxWidth - gap * (columns - 1)) / columns;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        _TimeTile(
                          width: itemWidth,
                          icon: Icons.login_rounded,
                          label: 'Giờ vào',
                          value: _record == null
                              ? _loading
                                    ? 'Đang tải...'
                                    : _loadError != null
                                    ? 'Chưa xác định'
                                    : 'Chưa có dữ liệu'
                              : _formatTime(
                                  vietnamWallTime(_record!.checkInAt),
                                ),
                        ),
                        _TimeTile(
                          width: itemWidth,
                          icon: Icons.logout_rounded,
                          label: 'Giờ ra',
                          value: _record?.checkOutAt == null
                              ? 'Chưa có dữ liệu'
                              : _formatTime(
                                  vietnamWallTime(_record!.checkOutAt!),
                                ),
                        ),
                        _TimeTile(
                          width: itemWidth,
                          icon: Icons.timelapse_rounded,
                          label: 'Tổng giờ làm',
                          value: _record?.workedDuration == null
                              ? 'Chưa có dữ liệu'
                              : _formatDuration(_record!.workedDuration!),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Phương thức chấm công',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Sinh trắc học'),
                      avatar: const Icon(Icons.fingerprint),
                      selected: _method == _AttendanceMethod.biometric,
                      onSelected: _isAuthenticating || _scanningNfc
                          ? null
                          : (_) => setState(
                              () => _method = _AttendanceMethod.biometric,
                            ),
                    ),
                    ChoiceChip(
                      label: const Text('Thẻ NFC'),
                      avatar: const Icon(Icons.nfc),
                      selected: _method == _AttendanceMethod.nfc,
                      onSelected:
                          _isAuthenticating ||
                              _checkingNfc ||
                              _nfcCheckFailed ||
                              _nfcAvailability == NfcAvailability.unsupported ||
                              _scanningNfc
                          ? null
                          : (_) =>
                                setState(() => _method = _AttendanceMethod.nfc),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_nfcStatusMessage(), style: theme.textTheme.bodyMedium),
                if (_nfcAvailability == NfcAvailability.disabled)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Mở Cài đặt Android, tìm NFC và bật lên, rồi quay lại ứng dụng.',
                    ),
                  ),
                TextButton.icon(
                  onPressed: _checkingNfc || _scanningNfc ? null : _checkNfc,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Kiểm tra lại NFC'),
                ),
                if (_method == _AttendanceMethod.nfc) ...[
                  const SizedBox(height: 8),
                  if (_scanningNfc) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text(
                      'Đang quét NFC. Đưa thẻ đến mặt lưng điện thoại.',
                    ),
                    TextButton(
                      onPressed: _finishingNfc
                          ? null
                          : () => _finishNfcScan(message: 'Đã hủy quét NFC.'),
                      child: const Text('Hủy'),
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed:
                          _checkingNfc ||
                              _nfcCheckFailed ||
                              _nfcAvailability != NfcAvailability.enabled
                          ? null
                          : _scanNfc,
                      icon: const Icon(Icons.nfc),
                      label: const Text('Quét thẻ NFC'),
                    ),
                  if (_nfcUid != null) Text('UID (hex): $_nfcUid'),
                  if (_nfcScanMessage != null) Text(_nfcScanMessage!),
                  const Text(
                    'UID chỉ là mã nhận dạng thẻ, không phải bằng chứng xác thực an toàn. Chưa liên kết thẻ hoặc chấm công bằng NFC.',
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final buttons = [
              FilledButton.icon(
                onPressed:
                    _isAuthenticating ||
                        _method == _AttendanceMethod.nfc ||
                        _loading ||
                        _loadError != null ||
                        _record != null
                    ? null
                    : () => _authenticate('chấm công vào', checkIn: true),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Check-in'),
              ),
              OutlinedButton.icon(
                onPressed:
                    _isAuthenticating ||
                        _method == _AttendanceMethod.nfc ||
                        _loading ||
                        _loadError != null ||
                        _record == null ||
                        _record!.checkOutAt != null ||
                        _record!.method == 'nfc' ||
                        _record!.method == 'manual'
                    ? null
                    : () => _authenticate('chấm công ra'),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Check-out'),
              ),
            ];
            if (constraints.maxWidth >= 480) {
              return Row(
                children: [
                  Expanded(child: buttons[0]),
                  const SizedBox(width: 12),
                  Expanded(child: buttons[1]),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [buttons[0], const SizedBox(height: 8), buttons[1]],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          _isAuthenticating
              ? 'Đang kiểm tra vị trí, xác thực hoặc lưu chấm công...'
              : _method == _AttendanceMethod.nfc
              ? 'Quét NFC chỉ đọc mã thẻ; chưa lưu chấm công.'
              : _record?.method == 'nfc' && _record?.checkOutAt == null
              ? 'Bản ghi vào bằng NFC tại quầy cần Check-out tại quầy.'
              : _record?.method == 'manual' && _record?.checkOutAt == null
              ? 'Bản ghi thủ công cần Manager/Admin bổ sung giờ ra.'
              : 'Check-in và Check-out được lưu sau xác thực sinh trắc học.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Future<void> _checkNfc() async {
    final serial = ++_nfcRequestSerial;
    setState(() {
      _checkingNfc = true;
      _nfcCheckFailed = false;
    });
    try {
      final availability = await _nfcChecker.checkAvailability();
      if (!mounted || serial != _nfcRequestSerial) return;
      setState(() {
        _nfcAvailability = availability;
        _checkingNfc = false;
        if (availability == NfcAvailability.unsupported) {
          _method = _AttendanceMethod.biometric;
        }
      });
    } catch (_) {
      if (!mounted || serial != _nfcRequestSerial) return;
      setState(() {
        _nfcAvailability = null;
        _nfcCheckFailed = true;
        _checkingNfc = false;
        _method = _AttendanceMethod.biometric;
      });
    }
  }

  Future<void> _scanNfc() async {
    if (_scanningNfc || _nfcAvailability != NfcAvailability.enabled) return;
    final scanSerial = ++_nfcScanSerial;
    setState(() {
      _scanningNfc = true;
      _nfcUid = null;
      _nfcScanMessage = null;
    });
    try {
      final availability = await _nfcChecker.checkAvailability();
      if (!mounted || !_scanningNfc || _finishingNfc) return;
      if (availability != NfcAvailability.enabled) {
        setState(() {
          _nfcAvailability = availability;
          _scanningNfc = false;
          _nfcScanMessage = availability == NfcAvailability.disabled
              ? 'NFC đang tắt. Hãy bật NFC trong Cài đặt Android.'
              : 'Thiết bị không hỗ trợ NFC.';
          if (availability == NfcAvailability.unsupported) {
            _method = _AttendanceMethod.biometric;
          }
        });
        return;
      }
      _nfcStartFuture = _nfcReader.start(
        onTag: (uid) {
          if (!_scanningNfc ||
              _finishingNfc ||
              !mounted ||
              scanSerial != _nfcScanSerial) {
            return;
          }
          _finishNfcScan(
            uid: nfcUidHex(uid),
            message: uid == null || uid.isEmpty
                ? 'Đã phát hiện thẻ, nhưng loại thẻ này không cung cấp UID.'
                : 'Đã đọc thẻ NFC.',
          );
        },
      );
      await _nfcStartFuture;
    } catch (_) {
      if (!mounted || !_scanningNfc || _finishingNfc) return;
      await _finishNfcScan(message: 'Không thể đọc thẻ NFC. Hãy thử lại.');
    }
  }

  Future<void> _finishNfcScan({String? uid, required String message}) async {
    if (!_scanningNfc || _finishingNfc) return;
    _finishingNfc = true;
    try {
      if (_nfcStartFuture != null) {
        try {
          await _nfcStartFuture;
        } catch (_) {
          return;
        }
        await _nfcReader.stop();
      }
    } catch (_) {
      message = 'Không thể kết thúc phiên NFC. Hãy thử lại.';
      uid = null;
    } finally {
      _nfcStartFuture = null;
      _finishingNfc = false;
      _scanningNfc = false;
      if (mounted) {
        setState(() {
          _nfcUid = uid;
          _nfcScanMessage = message;
        });
      }
    }
  }

  String _nfcStatusMessage() {
    if (_checkingNfc) return 'Đang kiểm tra NFC trên thiết bị...';
    if (_nfcCheckFailed) return 'Không thể kiểm tra NFC. Hãy thử lại.';
    return switch (_nfcAvailability) {
      NfcAvailability.enabled => 'NFC đang bật trên thiết bị.',
      NfcAvailability.disabled => 'NFC có sẵn nhưng đang tắt.',
      NfcAvailability.unsupported => 'Thiết bị không hỗ trợ NFC.',
      null => 'Chưa xác định được trạng thái NFC.',
    };
  }

  Future<void> _loadToday() async {
    final requestSerial = ++_loadRequestSerial;
    final requestedDate = vietnamWorkDate(widget.now());
    setState(() {
      _loading = true;
      _loadError = null;
      _record = null;
    });
    try {
      final record = await _repository.loadToday(widget.employeeId);
      if (!mounted ||
          requestSerial != _loadRequestSerial ||
          requestedDate != vietnamWorkDate(widget.now())) {
        return;
      }
      setState(() {
        _record = record;
        _loading = false;
      });
    } catch (error) {
      if (!mounted ||
          requestSerial != _loadRequestSerial ||
          requestedDate != vietnamWorkDate(widget.now())) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = _repositoryErrorMessage(error);
      });
    }
  }

  Future<void> _authenticate(String action, {bool checkIn = false}) async {
    if (_isAuthenticating || _method == _AttendanceMethod.nfc) return;
    var writeAttempted = false;
    setState(() => _isAuthenticating = true);
    try {
      await _locationGate.verify();
      if (!mounted) return;
      if (!await _authenticator.canCheckBiometrics()) {
        if (mounted) {
          _showMessage('Thiết bị không hỗ trợ sinh trắc học.');
        }
        return;
      }
      if (!await _authenticator.hasEnrolledBiometrics()) {
        if (mounted) {
          _showMessage('Chưa đăng ký sinh trắc học trên thiết bị.');
        }
        return;
      }
      final authenticated = await _authenticator.authenticate(
        reason: 'Xác thực sinh trắc học để $action',
      );
      if (!mounted) return;
      if (!authenticated) {
        _showMessage('Xác thực không thành công. Vui lòng thử lại.');
        return;
      }
      writeAttempted = true;
      final record = checkIn
          ? await _repository.checkIn(widget.employeeId)
          : await _repository.checkOut(widget.employeeId);
      if (!mounted) return;
      ++_loadRequestSerial;
      setState(() {
        _record = record;
        _loading = false;
        _loadError = null;
      });
      _showMessage(checkIn ? 'Check-in thành công.' : 'Check-out thành công.');
    } on AttendanceLocationNotConfiguredException {
      if (mounted) {
        _showMessage('Chưa có cấu hình vị trí chấm công. Hãy liên hệ Admin.');
      }
    } on AttendanceLocationConfigUnavailableException catch (error) {
      if (mounted) {
        _showMessage(_locationConfigErrorMessage(error));
      }
    } on AttendanceOutsideAreaException catch (error) {
      if (mounted) {
        _showMessage(
          'Bạn đang ngoài phạm vi chấm công: cách ${error.distanceMeters.toStringAsFixed(0)} m, bán kính cho phép ${error.radiusMeters.toStringAsFixed(0)} m.',
        );
      }
    } on LocationServiceException catch (error) {
      if (mounted) _showMessage(_locationErrorMessage(error));
    } on AttendanceAlreadyCheckedInException {
      if (!mounted) return;
      await _loadToday();
      if (mounted) _showMessage('Hôm nay bạn đã check-in.');
    } on AttendanceNotCheckedInException {
      if (!mounted) return;
      await _loadToday();
      if (mounted) _showMessage('Bạn cần check-in trước khi check-out.');
    } on AttendanceAlreadyCheckedOutException {
      if (!mounted) return;
      await _loadToday();
      if (mounted) _showMessage('Hôm nay bạn đã check-out.');
    } on AttendanceKioskOnlyException {
      if (mounted) _showMessage('Bản ghi NFC cần Check-out tại quầy.');
    } on AttendanceUnconfirmedException {
      if (mounted) {
        _markUnconfirmed();
        _showMessage('Chưa xác nhận được kết quả lưu. Hãy tải lại trạng thái.');
      }
    } on AttendanceUnauthorizedException {
      if (mounted) {
        _showMessage('Tài khoản không có quyền chấm công.');
      }
    } on LocalAuthException catch (error) {
      if (mounted) {
        _showMessage(_authErrorMessage(error.code));
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        if (writeAttempted && error.code != 'permission-denied') {
          _markUnconfirmed();
        }
        _showMessage(_repositoryErrorMessage(error));
      }
    } catch (_) {
      if (mounted) {
        if (writeAttempted) _markUnconfirmed();
        _showMessage('Không thể hoàn tất thao tác. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) {
        setState(() => _isAuthenticating = false);
      }
    }
  }

  void _markUnconfirmed() {
    ++_loadRequestSerial;
    setState(() {
      _record = null;
      _loading = false;
      _loadError = 'Chưa xác nhận được bản ghi. Hãy tải lại trạng thái.';
    });
  }

  String _repositoryErrorMessage(Object error) {
    if (error is AttendanceUnauthorizedException ||
        error is FirebaseException && error.code == 'permission-denied') {
      return 'Không có quyền chấm công. Kiểm tra tài khoản, Rules và ngày giờ thiết bị.';
    }
    if (error is FirebaseException &&
        [
          'user-disabled',
          'user-not-found',
          'invalid-user-token',
        ].contains(error.code)) {
      return 'Phiên đăng nhập không còn hợp lệ. Vui lòng đăng nhập lại.';
    }
    if (error is FirebaseException &&
        [
          'unavailable',
          'deadline-exceeded',
          'network-request-failed',
        ].contains(error.code)) {
      return 'Không có kết nối để xác nhận chấm công. Vui lòng thử lại.';
    }
    return 'Không thể tải hoặc lưu chấm công. Vui lòng thử lại.';
  }

  String _locationErrorMessage(
    LocationServiceException error,
  ) => switch (error.reason) {
    LocationFailure.gpsDisabled =>
      'GPS đang tắt. Hãy bật Vị trí trong Cài đặt Android.',
    LocationFailure.permissionDenied =>
      'Bạn đã từ chối quyền vị trí. Không thể chấm công.',
    LocationFailure.permissionDeniedForever => 'Quyền vị trí bị từ chối vĩnh viễn. Hãy bật quyền trong Cài đặt ứng dụng.',
    LocationFailure.timeout => 'Hết thời gian chờ lấy vị trí. Hãy thử lại.',
    LocationFailure.inaccurate =>
      'Vị trí chưa đủ chính xác (sai số ${error.accuracyMeters?.toStringAsFixed(1) ?? '?'} m). Hãy thử lại.',
    LocationFailure.unavailable =>
      'Không thể lấy vị trí hiện tại. Hãy thử lại.',
  };

  String _locationConfigErrorMessage(
    AttendanceLocationConfigUnavailableException error,
  ) {
    final cause = error.cause;
    if (cause is FirebaseException && cause.code == 'permission-denied') {
      return 'Không có quyền đọc cấu hình vị trí. Hãy kiểm tra tài khoản và Rules.';
    }
    if (cause is FirebaseException &&
        [
          'unavailable',
          'deadline-exceeded',
          'network-request-failed',
        ].contains(cause.code)) {
      return 'Không thể kết nối để tải cấu hình vị trí. Hãy thử lại.';
    }
    if (cause is FormatException) {
      return 'Cấu hình vị trí không hợp lệ. Hãy liên hệ Admin.';
    }
    return 'Không tải được cấu hình vị trí. Hãy thử lại.';
  }

  String _authErrorMessage(LocalAuthExceptionCode code) => switch (code) {
    LocalAuthExceptionCode.userCanceled ||
    LocalAuthExceptionCode.systemCanceled => 'Đã hủy xác thực sinh trắc học.',
    LocalAuthExceptionCode.noBiometricsEnrolled ||
    LocalAuthExceptionCode.noCredentialsSet =>
      'Chưa đăng ký sinh trắc học trên thiết bị.',
    LocalAuthExceptionCode.noBiometricHardware =>
      'Thiết bị không hỗ trợ sinh trắc học.',
    LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
    LocalAuthExceptionCode.temporaryLockout ||
    LocalAuthExceptionCode.biometricLockout =>
      'Sinh trắc học tạm thời không khả dụng. Vui lòng thử lại sau.',
    LocalAuthExceptionCode.userRequestedFallback =>
      'Chỉ hỗ trợ xác thực sinh trắc học.',
    _ => 'Xác thực không thành công. Vui lòng thử lại.',
  };

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDate(DateTime date) {
    const weekdays = [
      'Thứ Hai',
      'Thứ Ba',
      'Thứ Tư',
      'Thứ Năm',
      'Thứ Sáu',
      'Thứ Bảy',
      'Chủ Nhật',
    ];
    return '${weekdays[date.weekday - 1]}, '
        '${_twoDigits(date.day)}/${_twoDigits(date.month)}/${date.year}';
  }

  String _formatTime(DateTime date) =>
      '${_twoDigits(date.hour)}:${_twoDigits(date.minute)}:${_twoDigits(date.second)}';

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '$hours giờ ${_twoDigits(minutes)} phút ${_twoDigits(seconds)} giây';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
