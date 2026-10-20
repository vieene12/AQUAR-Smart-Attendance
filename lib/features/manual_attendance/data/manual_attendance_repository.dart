import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';

class ManualEmployee {
  const ManualEmployee({required this.uid, required this.name});

  final String uid;
  final String name;
}

class ManualAttendanceRecord {
  const ManualAttendanceRecord({
    required this.checkInAt,
    required this.status,
    required this.method,
    this.checkOutAt,
    this.checkOutMethod,
    this.manualRevision,
  });

  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final String? status;
  final String? method;
  final String? checkOutMethod;
  final int? manualRevision;
}

abstract class ManualAttendanceRepository {
  Future<bool> canAccess(UserProfile profile);
  Future<List<ManualEmployee>> loadEmployees();
  Future<ManualAttendanceRecord?> loadRecord(String employeeUid, DateTime date);
}

class FirestoreManualAttendanceRepository
    implements ManualAttendanceRepository {
  FirestoreManualAttendanceRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _providedFirestore = firestore,
       _providedAuth = auth;

  final FirebaseFirestore? _providedFirestore;
  final FirebaseAuth? _providedAuth;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;

  @override
  Future<bool> canAccess(UserProfile profile) async {
    if (_auth.currentUser?.uid != profile.uid ||
        (profile.role != UserRole.admin && profile.role != UserRole.manager)) {
      return false;
    }
    final snapshot = await _firestore
        .collection('users')
        .doc(profile.uid)
        .get(const GetOptions(source: Source.server));
    final data = snapshot.data();
    return data?['status'] == 'active' && data?['role'] == profile.role.name;
  }

  @override
  Future<List<ManualEmployee>> loadEmployees() async {
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'employee')
        .get(const GetOptions(source: Source.server));
    final employees = [
      for (final doc in snapshot.docs)
        ManualEmployee(
          uid: doc.id,
          name: (doc.data()['fullName'] as String?)?.trim().isNotEmpty == true
              ? (doc.data()['fullName'] as String).trim()
              : doc.id,
        ),
    ];
    employees.sort((a, b) => a.name.compareTo(b.name));
    return employees;
  }

  @override
  Future<ManualAttendanceRecord?> loadRecord(
    String employeeUid,
    DateTime date,
  ) async {
    final workDate =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final snapshot = await _firestore
        .collection('attendance')
        .doc(attendanceDocumentId(employeeUid, workDate))
        .get(const GetOptions(source: Source.server));
    final data = snapshot.data();
    if (data == null) return null;
    if (data['employeeId'] != employeeUid || data['workDate'] != workDate) {
      throw const FormatException(
        'Bản ghi chấm công không khớp nhân viên/ngày.',
      );
    }
    return ManualAttendanceRecord(
      checkInAt: (data['checkInAt'] as Timestamp?)?.toDate(),
      checkOutAt: (data['checkOutAt'] as Timestamp?)?.toDate(),
      status: data['status'] as String?,
      method: data['method'] as String?,
      checkOutMethod: data['checkOutMethod'] as String?,
      manualRevision: data['manualRevision'] as int?,
    );
  }
}
