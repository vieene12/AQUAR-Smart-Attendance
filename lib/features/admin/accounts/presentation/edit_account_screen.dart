import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:smart_attendance/features/admin/accounts/data/account_repository.dart';
import 'package:smart_attendance/features/admin/accounts/domain/account_record.dart';

class EditAccountScreen extends StatefulWidget {
  const EditAccountScreen({required this.account, super.key});

  final AccountRecord account;

  @override
  State<EditAccountScreen> createState() => _EditAccountScreenState();
}

class _EditAccountScreenState extends State<EditAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repository = AccountRepository();
  late final TextEditingController _nameController;
  late final TextEditingController _hourlyRateController;
  late final TextEditingController _codeController;
  late final TextEditingController _positionController;
  late final TextEditingController _shiftStartController;
  late final TextEditingController _shiftEndController;
  late final Future<List<AccountRecord>> _managers;
  String? _managerUid;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.account.name ?? '');
    _hourlyRateController = TextEditingController(
      text: widget.account.hourlyRate?.toString() ?? '',
    );
    _codeController = TextEditingController(
      text: widget.account.employeeCode ?? '',
    );
    _positionController = TextEditingController(
      text: widget.account.position ?? '',
    );
    _shiftStartController = TextEditingController(
      text: widget.account.shiftStart ?? '',
    );
    _shiftEndController = TextEditingController(
      text: widget.account.shiftEnd ?? '',
    );
    _managerUid = widget.account.managerUid;
    _managers = _repository.getAccounts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hourlyRateController.dispose();
    _codeController.dispose();
    _positionController.dispose();
    _shiftStartController.dispose();
    _shiftEndController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _repository.updateAccount(
        uid: widget.account.uid,
        fullName: _nameController.text.trim(),
        hourlyRate: int.parse(_hourlyRateController.text.trim()),
        employeeCode: widget.account.role == 'employee'
            ? _optional(_codeController)
            : null,
        position: widget.account.role == 'employee'
            ? _optional(_positionController)
            : null,
        shiftStart: widget.account.role == 'employee'
            ? _optional(_shiftStartController)
            : null,
        shiftEnd: widget.account.role == 'employee'
            ? _optional(_shiftEndController)
            : null,
        managerUid: widget.account.role == 'employee' ? _managerUid : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = switch (error.code) {
          'permission-denied' => 'Không có quyền cập nhật tài khoản. Hãy kiểm tra Security Rules và quyền Admin.',
          'not-found' => 'Tài khoản không còn tồn tại trong Firestore.',
          'unavailable' || 'deadline-exceeded' =>
            'Không thể kết nối Firestore. Vui lòng thử lại.',
          _ => 'Không thể cập nhật tài khoản. Vui lòng thử lại.',
        };
      });
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _errorMessage = 'Không thể cập nhật tài khoản. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  String? _validateTime(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return null;
    return RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(input)
        ? null
        : 'Nhập giờ theo định dạng HH:mm.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roleLabel = switch (widget.account.role) {
      'manager' => 'Quản lý',
      'employee' => 'Nhân viên',
      _ => widget.account.role ?? 'Chưa xác định',
    };

    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
        appBar: AppBar(title: const Text('Chỉnh sửa tài khoản')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card.filled(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Thông tin tài khoản',
                            style: theme.textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _nameController,
                            enabled: !_isLoading,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Họ tên',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              final name = value?.trim() ?? '';
                              if (name.isEmpty) return 'Vui lòng nhập họ tên.';
                              if (name.length > 100) {
                                return 'Họ tên không được quá 100 ký tự.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          if (widget.account.role == 'employee') ...[
                            TextFormField(
                              controller: _codeController,
                              enabled: !_isLoading,
                              decoration: const InputDecoration(
                                labelText: 'Mã nhân viên',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) =>
                                  (value?.trim().length ?? 0) > 40
                                  ? 'Tối đa 40 ký tự.'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _positionController,
                              enabled: !_isLoading,
                              decoration: const InputDecoration(
                                labelText: 'Chức vụ',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) =>
                                  (value?.trim().length ?? 0) > 100
                                  ? 'Tối đa 100 ký tự.'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _shiftStartController,
                              enabled: !_isLoading,
                              decoration: const InputDecoration(
                                labelText: 'Bắt đầu ca (HH:mm)',
                                border: OutlineInputBorder(),
                              ),
                              validator: _validateTime,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _shiftEndController,
                              enabled: !_isLoading,
                              decoration: const InputDecoration(
                                labelText: 'Kết thúc ca (HH:mm)',
                                border: OutlineInputBorder(),
                              ),
                              validator: _validateTime,
                            ),
                            const SizedBox(height: 16),
                            FutureBuilder<List<AccountRecord>>(
                              future: _managers,
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return Text(
                                    snapshot.hasError
                                        ? 'Không tải được danh sách quản lý.'
                                        : 'Đang tải danh sách quản lý...',
                                  );
                                }
                                final managers = snapshot.data!
                                    .where(
                                      (account) => account.role == 'manager',
                                    )
                                    .toList();
                                return DropdownButtonFormField<String>(
                                  initialValue:
                                      managers.any(
                                        (manager) => manager.uid == _managerUid,
                                      )
                                      ? _managerUid
                                      : null,
                                  decoration: const InputDecoration(
                                    labelText: 'Quản lý phụ trách',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: [
                                    const DropdownMenuItem<String>(
                                      value: '',
                                      child: Text('Chưa phân công'),
                                    ),
                                    for (final manager in managers)
                                      DropdownMenuItem(
                                        value: manager.uid,
                                        child: Text(
                                          manager.name ?? manager.uid,
                                        ),
                                      ),
                                  ],
                                  onChanged: _isLoading
                                      ? null
                                      : (uid) => setState(
                                          () => _managerUid = uid == ''
                                              ? null
                                              : uid,
                                        ),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: _hourlyRateController,
                            enabled: !_isLoading,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Lương theo giờ (VNĐ)',
                              prefixIcon: Icon(Icons.payments_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              final amount = int.tryParse(value?.trim() ?? '');
                              if (amount == null || amount < 0) {
                                return 'Lương theo giờ phải là số nguyên không âm.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            initialValue:
                                widget.account.email ?? 'Chưa cập nhật',
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Email (chỉ đọc)',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            initialValue: roleLabel,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Vai trò (chỉ đọc)',
                              prefixIcon: Icon(Icons.badge_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _isLoading ? null : _save,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(
                              _isLoading ? 'Đang lưu...' : 'Lưu thay đổi',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
