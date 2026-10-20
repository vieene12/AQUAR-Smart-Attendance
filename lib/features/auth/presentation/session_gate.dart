import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:smart_attendance/features/auth/data/auth_service.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/auth/presentation/login_screen.dart';
import 'package:smart_attendance/features/home/presentation/role_home_screens.dart';

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> with WidgetsBindingObserver {
  final _authService = AuthService();
  bool _checking = true;
  bool _restoreInFlight = false;
  UserProfile? _profile;
  String? _gateError;
  String? _loginError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _profile != null && !_checking) {
      _restoreSession();
    }
  }

  Future<void> _restoreSession() async {
    if (_restoreInFlight) return;
    _restoreInFlight = true;
    setState(() {
      _checking = true;
      _gateError = null;
    });

    try {
      final profile = await _authService.restoreSession();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loginError = null;
      });
    } on UserProfileException catch (error) {
      if (!mounted) return;
      setState(() {
        _profile = null;
        _loginError = switch (error.failure) {
          UserProfileFailure.missing => 'Tài khoản chưa có hồ sơ nhân viên.',
          UserProfileFailure.locked =>
            'Tài khoản đã bị khóa. Vui lòng liên hệ quản trị viên.',
          UserProfileFailure.invalidStatus => 'Trạng thái tài khoản không hợp lệ. Vui lòng liên hệ quản trị viên.',
          UserProfileFailure.invalidRole =>
            'Vai trò tài khoản không hợp lệ. Vui lòng liên hệ quản trị viên.',
        };
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _profile = null;
        if (error.code == 'user-disabled' || error.code == 'user-not-found') {
          _loginError = 'Tài khoản đã bị vô hiệu hóa hoặc không còn tồn tại.';
        } else {
          _gateError = _connectionError(error.code);
        }
      });
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _profile = null;
        _gateError = _connectionError(error.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profile = null;
        _gateError = 'Không thể kiểm tra phiên đăng nhập. Vui lòng thử lại.';
      });
    } finally {
      _restoreInFlight = false;
      if (mounted) setState(() => _checking = false);
    }
  }

  String _connectionError(String code) => switch (code) {
    'network-request-failed' || 'unavailable' =>
      'Không có kết nối mạng để xác minh tài khoản. Vui lòng thử lại.',
    'permission-denied' =>
      'Không thể đọc hồ sơ nhân viên. Vui lòng liên hệ quản trị viên.',
    _ => 'Không thể kiểm tra phiên đăng nhập. Vui lòng thử lại.',
  };

  void _onSignedIn(UserProfile profile) {
    setState(() {
      _profile = profile;
      _gateError = null;
      _loginError = null;
    });
  }

  Future<void> _signOut() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await _authService.signOut();
      if (!mounted) return;
      setState(() {
        _profile = null;
        _gateError = null;
        _loginError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profile = null;
        _gateError = 'Không thể đăng xuất. Vui lòng thử lại.';
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_gateError != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(_gateError!, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _restoreSession,
                    child: const Text('Thử lại'),
                  ),
                  TextButton(
                    onPressed: _signOut,
                    child: const Text('Đăng xuất'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final profile = _profile;
    if (profile == null) {
      return LoginScreen(onSignedIn: _onSignedIn, initialError: _loginError);
    }

    return switch (profile.role) {
      UserRole.admin => AdminHomeScreen(profile: profile, onSignOut: _signOut),
      UserRole.manager => ManagerHomeScreen(
        profile: profile,
        onSignOut: _signOut,
      ),
      UserRole.employee => EmployeeHomeScreen(
        profile: profile,
        onSignOut: _signOut,
      ),
    };
  }
}
