class AccountRecord {
  const AccountRecord({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    required this.hourlyRate,
  });

  final String uid;
  final String? name;
  final String? email;
  final String? role;
  final String? status;
  final int? hourlyRate;

  factory AccountRecord.fromFirestore(String uid, Map<String, dynamic> data) {
    return AccountRecord(
      uid: uid,
      name: _nonEmptyText(data['fullName']) ?? _nonEmptyText(data['name']),
      email: _nonEmptyText(data['email']),
      role: _nonEmptyText(data['role']),
      status: _nonEmptyText(data['status']),
      hourlyRate: data['hourlyRate'] is int ? data['hourlyRate'] as int : null,
    );
  }

  static String? _nonEmptyText(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}
