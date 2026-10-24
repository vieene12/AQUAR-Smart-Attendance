import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:smart_attendance/core/theme/app_theme.dart';
import 'package:smart_attendance/features/auth/data/auth_service.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.onSignedIn, this.initialError, super.key});

  final ValueChanged<UserProfile> onSignedIn;
  final String? initialError;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _errorMessage = widget.initialError;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Vui lòng nhập email';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Email không hợp lệ';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Vui lòng nhập mật khẩu';
    if (value.length < 6) return 'Mật khẩu cần ít nhất 6 ký tự';
    return null;
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profile = await AuthService().signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      widget.onSignedIn(profile);
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = _authErrorMessage(error.code));
      }
    } on UserProfileException catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = switch (error.failure) {
            UserProfileFailure.missing => 'Tài khoản chưa có hồ sơ nhân viên.',
            UserProfileFailure.locked =>
              'Tài khoản đã bị khóa. Vui lòng liên hệ quản trị viên.',
            UserProfileFailure.invalidStatus =>
              'Trạng thái tài khoản chưa hợp lệ. Vui lòng liên hệ quản trị viên.',
            UserProfileFailure.invalidRole =>
              'Vai trò tài khoản không hợp lệ. Vui lòng liên hệ quản trị viên.',
          },
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = switch (error.code) {
            'unavailable' || 'network-request-failed' =>
              'Không có kết nối mạng. Vui lòng thử lại.',
            'permission-denied' =>
              'Không thể đọc hồ sơ nhân viên. Vui lòng liên hệ quản trị viên.',
            _ => 'Không thể kiểm tra hồ sơ nhân viên. Vui lòng thử lại.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Đăng nhập thất bại. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _authErrorMessage(String code) => switch (code) {
    'wrong-password' => 'Mật khẩu không đúng.',
    'user-not-found' => 'Email chưa được đăng ký.',
    'user-disabled' => 'Tài khoản đã bị vô hiệu hóa.',
    'network-request-failed' => 'Không có kết nối mạng. Vui lòng thử lại.',
    'invalid-email' => 'Email không hợp lệ.',
    'invalid-credential' ||
    'invalid-login-credentials' => 'Email hoặc mật khẩu không đúng.',
    'too-many-requests' =>
      'Thử đăng nhập quá nhiều lần. Vui lòng thử lại sau.',
    'operation-not-allowed' =>
      'Đăng nhập bằng email chưa được bật. Vui lòng liên hệ quản trị viên.',
    _ => 'Đăng nhập thất bại. Vui lòng thử lại.',
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // ── Background gradient ──────────────────────────────────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: isDark
                    ? AppTheme.darkPrimaryGradient
                    : AppTheme.primaryGradient,
              ),
            ),
          ),

          // ── Decorative shapes ────────────────────────────────────────
          Positioned(
            top: -100,
            right: -100,
            child: _Circle(size: 340, opacity: isDark ? 0.12 : 0.15),
          ),
          Positioned(
            top: 60,
            left: -60,
            child: _Circle(size: 180, opacity: isDark ? 0.08 : 0.10),
          ),

          // ── Content ──────────────────────────────────────────────────
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Header section
                      FadeTransition(
                        opacity: _fadeAnim,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
                          child: Column(
                            children: [
                              // Logo
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(30),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.white.withAlpha(60),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(30),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.fact_check_rounded,
                                  size: 42,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Smart Attendance',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Đăng nhập để bắt đầu ngày làm việc',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withAlpha(200),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── Form card ──────────────────────────────────
                      SlideTransition(
                        position: _slideAnim,
                        child: FadeTransition(
                          opacity: _fadeAnim,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 440),
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF101C2C)
                                  : Colors.white,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(32),
                                bottom: Radius.circular(32),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(30),
                                  blurRadius: 40,
                                  offset: const Offset(0, -8),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
                              child: Form(
                                key: _formKey,
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // ── Section title ────────────────
                                    Text(
                                      'Chào mừng trở lại 👋',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Nhập thông tin đăng nhập của bạn',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 28),

                                    // ── Email ───────────────────────
                                    TextFormField(
                                      controller: _emailController,
                                      enabled: !_isLoading,
                                      keyboardType:
                                          TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [
                                        AutofillHints.email,
                                      ],
                                      autocorrect: false,
                                      validator: _validateEmail,
                                      decoration: const InputDecoration(
                                        labelText: 'Email',
                                        hintText: 'ten@congty.com',
                                        prefixIcon: Icon(
                                          Icons.email_outlined,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // ── Password ─────────────────────
                                    TextFormField(
                                      controller: _passwordController,
                                      enabled: !_isLoading,
                                      obscureText: !_passwordVisible,
                                      textInputAction: TextInputAction.done,
                                      autofillHints: const [
                                        AutofillHints.password,
                                      ],
                                      validator: _validatePassword,
                                      onFieldSubmitted: (_) => _submit(),
                                      decoration: InputDecoration(
                                        labelText: 'Mật khẩu',
                                        prefixIcon: const Icon(
                                          Icons.lock_outline_rounded,
                                        ),
                                        suffixIcon: IconButton(
                                          tooltip: _passwordVisible
                                              ? 'Ẩn mật khẩu'
                                              : 'Hiện mật khẩu',
                                          icon: Icon(
                                            _passwordVisible
                                                ? Icons
                                                      .visibility_off_outlined
                                                : Icons.visibility_outlined,
                                          ),
                                          onPressed: _isLoading
                                              ? null
                                              : () => setState(
                                                    () => _passwordVisible =
                                                        !_passwordVisible,
                                                  ),
                                        ),
                                      ),
                                    ),

                                    // ── Error banner ─────────────────
                                    if (_errorMessage != null) ...[
                                      const SizedBox(height: 16),
                                      AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: cs.errorContainer,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.error_outline_rounded,
                                              color: cs.onErrorContainer,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                _errorMessage!,
                                                style: TextStyle(
                                                  color: cs.onErrorContainer,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],

                                    const SizedBox(height: 28),

                                    // ── Login button ─────────────────
                                    _GradientButton(
                                      onPressed: _isLoading ? null : _submit,
                                      isLoading: _isLoading,
                                      label: 'Đăng nhập',
                                      gradient: AppTheme.primaryGradient,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable widgets ─────────────────────────────────────────────────────────

class _Circle extends StatelessWidget {
  const _Circle({required this.size, required this.opacity});
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: opacity),
    ),
  );
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.onPressed,
    required this.isLoading,
    required this.label,
    required this.gradient,
  });

  final VoidCallback? onPressed;
  final bool isLoading;
  final String label;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 54,
        decoration: BoxDecoration(
          gradient: onPressed == null
              ? null
              : (isDark ? AppTheme.darkPrimaryGradient : gradient),
          color: onPressed == null
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: onPressed == null
              ? []
              : [
                  BoxShadow(
                    color: const Color(0xFF0288D1).withAlpha(80),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: onPressed == null
                        ? Theme.of(context).colorScheme.onSurface.withAlpha(80)
                        : Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
    );
  }
}
