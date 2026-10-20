import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:smart_attendance/features/admin/attendance_location/data/attendance_location_repository.dart';
import 'package:smart_attendance/features/attendance/data/location_service.dart';

class AttendanceLocationScreen extends StatefulWidget {
  const AttendanceLocationScreen({
    super.key,
    this.repository,
    this.locationService,
  });

  final AttendanceLocationRepository? repository;
  final LocationService? locationService;

  @override
  State<AttendanceLocationScreen> createState() =>
      _AttendanceLocationScreenState();
}

class _AttendanceLocationScreenState extends State<AttendanceLocationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _radius = TextEditingController();
  final _accuracy = TextEditingController();
  late final AttendanceLocationRepository _repository;
  late final LocationService _locationService;
  AttendanceLocationConfig? _saved;
  bool _loading = true;
  bool _saving = false;
  bool _locating = false;
  String? _loadError;
  int _loadSerial = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirestoreAttendanceLocationRepository();
    _locationService = widget.locationService ?? LocationService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _radius.dispose();
    _accuracy.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final serial = ++_loadSerial;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final config = await _repository.load();
      if (!mounted || serial != _loadSerial) return;
      setState(() {
        _saved = config;
        _loading = false;
      });
      if (config != null) _fillForm(config);
    } catch (error) {
      if (!mounted || serial != _loadSerial) return;
      setState(() {
        _loading = false;
        _loadError = _repositoryError(error);
      });
    }
  }

  void _fillForm(AttendanceLocationConfig config) {
    _name.text = config.name;
    _latitude.text = config.latitude.toString();
    _longitude.text = config.longitude.toString();
    _radius.text = config.radiusMeters.toString();
    _accuracy.text = config.maxAccuracyMeters.toString();
  }

  double? _parseNumber(String input) =>
      double.tryParse(input.trim().replaceAll(',', '.'));

  String? _coordinateError(String input, double min, double max) {
    final value = _parseNumber(input);
    if (value == null || !value.isFinite || value < min || value > max) {
      return 'Nhập số từ $min đến $max.';
    }
    return null;
  }

  String? _positiveError(String input) {
    final value = _parseNumber(input);
    if (value == null || !value.isFinite || value <= 0) {
      return 'Nhập số lớn hơn 0.';
    }
    return null;
  }

  Future<void> _locate() async {
    if (_locating || _saving) return;
    final maxAccuracy = _parseNumber(_accuracy.text);
    if (maxAccuracy == null || !maxAccuracy.isFinite || maxAccuracy <= 0) {
      _formKey.currentState?.validate();
      _showMessage('Nhập độ chính xác GPS tối đa trước khi lấy vị trí.');
      return;
    }
    setState(() => _locating = true);
    try {
      final fix = await _locationService.getCurrentLocation(
        maxAccuracyMeters: maxAccuracy,
      );
      if (!mounted) return;
      _latitude.text = fix.latitude.toStringAsFixed(7);
      _longitude.text = fix.longitude.toStringAsFixed(7);
      _showMessage(
        'Đã lấy vị trí hiện tại (sai số ${fix.accuracyMeters.toStringAsFixed(1)} m). Kiểm tra rồi lưu.',
      );
    } on LocationServiceException catch (error) {
      if (mounted) _showMessage(_locationError(error));
    } catch (_) {
      if (mounted) _showMessage('Không thể lấy vị trí hiện tại. Hãy thử lại.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _locating || !_formKey.currentState!.validate()) return;
    final config = AttendanceLocationConfig(
      name: _name.text.trim(),
      latitude: _parseNumber(_latitude.text)!,
      longitude: _parseNumber(_longitude.text)!,
      radiusMeters: _parseNumber(_radius.text)!,
      maxAccuracyMeters: _parseNumber(_accuracy.text)!,
    );
    setState(() => _saving = true);
    try {
      final saved = await _repository.save(config);
      if (!mounted) return;
      setState(() => _saved = saved);
      _fillForm(saved);
      _showMessage('Đã lưu vị trí chấm công.');
    } catch (error) {
      if (mounted) _showMessage(_repositoryError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _locationError(
    LocationServiceException error,
  ) => switch (error.reason) {
    LocationFailure.gpsDisabled =>
      'GPS đang tắt. Hãy bật Vị trí trong Cài đặt Android.',
    LocationFailure.permissionDenied => 'Bạn đã từ chối quyền vị trí.',
    LocationFailure.permissionDeniedForever => 'Quyền vị trí bị từ chối vĩnh viễn. Hãy bật quyền trong Cài đặt ứng dụng.',
    LocationFailure.timeout => 'Hết thời gian chờ lấy vị trí. Hãy thử lại.',
    LocationFailure.inaccurate =>
      'Vị trí chưa đủ chính xác (sai số ${error.accuracyMeters?.toStringAsFixed(1) ?? '?'} m). Hãy thử lại.',
    LocationFailure.unavailable =>
      'Không thể lấy vị trí hiện tại. Hãy thử lại.',
  };

  String _repositoryError(Object error) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'Không có quyền lưu hoặc đọc cấu hình vị trí.';
    }
    if (error is FirebaseException && error.code == 'unauthenticated') {
      return 'Phiên đăng nhập không hợp lệ. Hãy đăng nhập lại.';
    }
    if (error is FirebaseException &&
        [
          'unavailable',
          'deadline-exceeded',
          'network-request-failed',
        ].contains(error.code)) {
      return 'Không thể kết nối Firestore. Hãy thử lại.';
    }
    if (error is FormatException) {
      return 'Cấu hình vị trí chưa hợp lệ hoặc chưa xác nhận được. Hãy tải lại.';
    }
    return 'Không thể tải hoặc lưu cấu hình vị trí. Hãy thử lại.';
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Vị trí chấm công')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _loadError != null
                  ? Card.filled(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(_loadError!, textAlign: TextAlign.center),
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
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Cấu hình đã lưu',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        _savedCard(),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: _saving || _locating ? null : _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tải lại cấu hình'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Chỉnh sửa vị trí',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _name,
                                decoration: const InputDecoration(
                                  labelText: 'Tên địa điểm',
                                  border: OutlineInputBorder(),
                                ),
                                maxLength: 100,
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? 'Nhập tên địa điểm.'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  const gap = 12.0;
                                  final columns = constraints.maxWidth >= 580
                                      ? 2
                                      : 1;
                                  final width =
                                      (constraints.maxWidth -
                                          gap * (columns - 1)) /
                                      columns;
                                  return Wrap(
                                    spacing: gap,
                                    runSpacing: gap,
                                    children: [
                                      _numberField(
                                        width,
                                        'Vĩ độ',
                                        _latitude,
                                        (value) => _coordinateError(
                                          value ?? '',
                                          -90,
                                          90,
                                        ),
                                      ),
                                      _numberField(
                                        width,
                                        'Kinh độ',
                                        _longitude,
                                        (value) => _coordinateError(
                                          value ?? '',
                                          -180,
                                          180,
                                        ),
                                      ),
                                      _numberField(
                                        width,
                                        'Bán kính cho phép (m)',
                                        _radius,
                                        (value) => _positiveError(value ?? ''),
                                      ),
                                      _numberField(
                                        width,
                                        'Độ chính xác GPS tối đa (m)',
                                        _accuracy,
                                        (value) => _positiveError(value ?? ''),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _saving || _locating
                                        ? null
                                        : _locate,
                                    icon: const Icon(Icons.my_location),
                                    label: Text(
                                      _locating
                                          ? 'Đang lấy vị trí...'
                                          : 'Lấy vị trí hiện tại',
                                    ),
                                  ),
                                  FilledButton.icon(
                                    onPressed: _saving || _locating
                                        ? null
                                        : _save,
                                    icon: const Icon(Icons.save_outlined),
                                    label: Text(
                                      _saving ? 'Đang lưu...' : 'Lưu cấu hình',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _numberField(
    double width,
    String label,
    TextEditingController controller,
    FormFieldValidator<String> validator,
  ) => SizedBox(
    width: width,
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      validator: validator,
    ),
  );

  Widget _savedCard() {
    final config = _saved;
    if (config == null) {
      return const Card.filled(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Chưa có cấu hình vị trí chấm công.'),
        ),
      );
    }
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            Text('Địa điểm: ${config.name}'),
            Text('Vĩ độ: ${config.latitude}'),
            Text('Kinh độ: ${config.longitude}'),
            Text('Bán kính: ${config.radiusMeters} m'),
            Text('Sai số GPS tối đa: ${config.maxAccuracyMeters} m'),
          ],
        ),
      ),
    );
  }
}
