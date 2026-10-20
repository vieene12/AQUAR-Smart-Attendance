enum UserRole {
  admin,
  manager,
  employee;

  static UserRole? fromFirestore(Object? value) => switch (value) {
    'admin' => UserRole.admin,
    'manager' => UserRole.manager,
    'employee' => UserRole.employee,
    _ => null,
  };

  String get label => switch (this) {
    UserRole.admin => 'Quản trị viên',
    UserRole.manager => 'Quản lý',
    UserRole.employee => 'Nhân viên',
  };
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.role,
  });

  final String uid;
  final String displayName;
  final UserRole role;
}
