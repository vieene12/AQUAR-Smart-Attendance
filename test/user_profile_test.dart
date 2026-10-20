import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';

void main() {
  test('đọc đúng ba vai trò được hỗ trợ', () {
    expect(UserRole.fromFirestore('admin'), UserRole.admin);
    expect(UserRole.fromFirestore('manager'), UserRole.manager);
    expect(UserRole.fromFirestore('employee'), UserRole.employee);
  });

  test('từ chối vai trò thiếu hoặc không hợp lệ', () {
    expect(UserRole.fromFirestore(null), isNull);
    expect(UserRole.fromFirestore('owner'), isNull);
    expect(UserRole.fromFirestore(1), isNull);
  });
}
