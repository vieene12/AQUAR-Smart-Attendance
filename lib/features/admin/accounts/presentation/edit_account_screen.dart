import 'package:flutter/material.dart';
import 'package:smart_attendance/features/admin/accounts/data/account_api_client.dart';
import 'package:smart_attendance/features/admin/accounts/data/account_repository.dart';
import 'package:smart_attendance/features/admin/accounts/domain/account_record.dart';

class EditAccountScreen extends StatefulWidget {
  const EditAccountScreen({required this.account, this.repository, super.key});

  final AccountRecord account;
  final AccountRepositoryContract? repository;

  @override
  State<EditAccountScreen> createState() => _EditAccountScreenState();
}

class _EditAccountScreenState extends State<EditAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  late final AccountRepositoryContract _repository;
  late final TextEditingController _nameController;
  late final TextEditingController _hourlyRateController;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? AccountRepository();
    _nameController = TextEditingController(text: widget.account.name ?? '');
    _hourlyRateController = TextEditingController(
      text: widget.account.hourlyRate?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hourlyRateController.dispose();
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
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AccountApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.messageFor(AccountApiOperation.update);
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
