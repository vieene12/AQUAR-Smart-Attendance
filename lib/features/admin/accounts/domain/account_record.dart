class AccountRecord {
  const AccountRecord({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    required this.hourlyRate,
    this.employeeCode,
    this.position,
    this.shiftStart,
    this.shiftEnd,
    this.managerUid,
  });

  final String uid;
  final String? name;
  final String? email;
  final String? role;
  final String? status;
  final int? hourlyRate;
  final String? employeeCode;
  final String? position;
  final String? shiftStart;
  final String? shiftEnd;
  final String? managerUid;

  factory AccountRecord.fromFirestore(String uid, Map<String, dynamic> data) {
    return AccountRecord(
      uid: uid,
      name: _nonEmptyText(data['fullName']) ?? _nonEmptyText(data['name']),
      email: _nonEmptyText(data['email']),
      role: _nonEmptyText(data['role']),
      status: _nonEmptyText(data['status']),
      hourlyRate: data['hourlyRate'] is int ? data['hourlyRate'] as int : null,
      employeeCode: _nonEmptyText(data['employeeCode']),
      position: _nonEmptyText(data['position']),
      shiftStart: _nonEmptyText(data['shiftStart']),
      shiftEnd: _nonEmptyText(data['shiftEnd']),
      managerUid: _nonEmptyText(data['managerUid']),
    );
  }

  factory AccountRecord.fromApi(Map<String, dynamic> data) {
    final uid = _nonEmptyText(data['uid']);
    final role = _nonEmptyText(data['role']);
    final status = _nonEmptyText(data['status']);
    final hourlyRate = data['hourlyRate'];
    if (uid == null ||
        role == null ||
        status == null ||
        (hourlyRate != null && hourlyRate is! int)) {
      throw const FormatException('Invalid account response.');
    }
    return AccountRecord(
      uid: uid,
      name: _nonEmptyText(data['fullName']),
      email: _nonEmptyText(data['email']),
      role: role,
      status: status,
      hourlyRate: hourlyRate as int?,
    );
  }

  static String? _nonEmptyText(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}
