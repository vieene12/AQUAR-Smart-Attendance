import 'package:local_auth/local_auth.dart';

/// Giao diện nhỏ để kiểm thử luồng xác thực mà không mở hộp thoại hệ thống.
abstract class BiometricAuthenticator {
  Future<bool> canCheckBiometrics();
  Future<bool> hasEnrolledBiometrics();
  Future<bool> authenticate({required String reason});
}

class LocalBiometricAuthenticator implements BiometricAuthenticator {
  LocalBiometricAuthenticator({LocalAuthentication? localAuth})
    : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  @override
  Future<bool> canCheckBiometrics() => _localAuth.canCheckBiometrics;

  @override
  Future<bool> hasEnrolledBiometrics() async =>
      (await _localAuth.getAvailableBiometrics()).isNotEmpty;

  @override
  Future<bool> authenticate({required String reason}) =>
      _localAuth.authenticate(localizedReason: reason, biometricOnly: true);
}
