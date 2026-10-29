import 'package:flutter/material.dart';
import 'package:smart_attendance/features/admin/accounts/data/account_api_client.dart';
import 'package:smart_attendance/features/admin/accounts/data/account_creation_repository.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';

class AddAccountScreen extends StatefulWidget {
  const AddAccountScreen({this.repository, super.key});

  final AccountCreationRepositoryContract? repository;

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  late final AccountCreationRepositoryContract _repository;
  UserRole? _selectedRole;
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? AccountCreationRepository();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _hourlyRateController.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final role = _selectedRole;
    if (role == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _repository.createAccount(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        role: role.name,
        hourlyRate: int.parse(_hourlyRateController.text.trim()),
      );
      if (!mounted) return;
      _passwordController.clear();
      Navigator.of(context).pop(true);
    } on AccountApiException catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = error.messageFor(AccountApiOperation.create),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Không thể tạo tài khoản. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(title: const Text('Thêm tài khoản')),
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
                          Icon(
                            Icons.person_add_alt_1_outlined,
                            size: 44,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Thông tin tài khoản',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tạo tài khoản cho nhân viên hoặc quản lý.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            decoration: const InputDecoration(
                              labelText: 'Họ tên',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Vui lòng nhập họ tên.'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              if (email.isEmpty) return 'Vui lòng nhập email.';
                              if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(email)) {
                                return 'Email không hợp lệ.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Mật khẩu ban đầu',
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Hiện mật khẩu'
                                    : 'Ẩn mật khẩu',
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Vui lòng nhập mật khẩu ban đầu.';
                              }
                              if (value.length < 6) {
                                return 'Mật khẩu phải có ít nhất 6 ký tự.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<UserRole>(
                            decoration: const InputDecoration(
                              labelText: 'Vai trò',
                              prefixIcon: Icon(Icons.badge_outlined),
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: UserRole.employee,
                                child: Text('Nhân viên'),
                              ),
                              DropdownMenuItem(
                                value: UserRole.manager,
                                child: Text('Quản lý'),
                              ),
                            ],
                            onChanged: _isLoading
                                ? null
                                : (role) =>
                                      setState(() => _selectedRole = role),
                            validator: (value) =>
                                value == null ? 'Vui lòng chọn vai trò.' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _hourlyRateController,
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                            ),
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Lương theo giờ (VNĐ)',
                              prefixIcon: Icon(Icons.payments_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              final input = value?.trim() ?? '';
                              if (input.isEmpty) {
                                return 'Vui lòng nhập lương theo giờ.';
                              }
                              final amount = int.tryParse(input);
                              if (amount == null || amount < 0) {
                                return 'Lương theo giờ phải là số nguyên không âm.';
                              }
                              return null;
                            },
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
                            onPressed: _isLoading ? null : _onSave,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(_isLoading ? 'Đang tạo...' : 'Lưu'),
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
