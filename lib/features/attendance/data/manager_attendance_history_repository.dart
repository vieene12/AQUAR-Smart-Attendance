import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';

class ManagerHistoryEmployee {
  const ManagerHistoryEmployee({required this.uid, required this.name});

  final String uid;
  final String name;
}

abstract interface class ManagerAttendanceHistoryRepository {
  Future<bool> canAccess(UserProfile profile);

  Future<List<ManagerHistoryEmployee>> loadEmployees();

  Future<List<AttendanceRecord>> loadHistory(
    String employeeUid, {
    DateTime? startDate,
    DateTime? endDate,
  });
}

class FirestoreManagerAttendanceHistoryRepository
    implements ManagerAttendanceHistoryRepository {
  FirestoreManagerAttendanceHistoryRepository({
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
        profile.role != UserRole.manager) {
      return false;
    }
    final snapshot = await _firestore
        .collection('users')
        .doc(profile.uid)
        .get(const GetOptions(source: Source.server));
    return _auth.currentUser?.uid == profile.uid &&
        snapshot.data()?['role'] == 'manager' &&
        snapshot.data()?['status'] == 'active';
  }

  @override
  Future<List<ManagerHistoryEmployee>> loadEmployees() async {
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'employee')
        .get(const GetOptions(source: Source.server));
    final employees = [
      for (final document in snapshot.docs)
        ManagerHistoryEmployee(
          uid: document.id,
          name:
              (document.data()['fullName'] as String?)?.trim().isNotEmpty ==
                  true
              ? (document.data()['fullName'] as String).trim()
              : document.id,
        ),
    ];
    employees.sort((a, b) => a.name.compareTo(b.name));
    return employees;
  }

  @override
  Future<List<AttendanceRecord>> loadHistory(
    String employeeUid, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('attendance')
        .where('employeeId', isEqualTo: employeeUid);
    if (startDate != null) {
      query = query.where(
        'workDate',
        isGreaterThanOrEqualTo: workDateFromCalendarDate(startDate),
      );
    }
    if (endDate != null) {
      query = query.where(
        'workDate',
        isLessThanOrEqualTo: workDateFromCalendarDate(endDate),
      );
    }
    final snapshot = await query
        .orderBy('workDate', descending: true)
        .get(const GetOptions(source: Source.server));
    return [
      for (final document in snapshot.docs) _record(document, employeeUid),
    ];
  }

  AttendanceRecord _record(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
    String employeeUid,
  ) {
    final data = document.data();
    final workDate = data['workDate'];
    final checkInAt = data['checkInAt'];
    final checkOutAt = data['checkOutAt'];
    final method = data['method'];
    final status = data['status'];
    if (data['employeeId'] != employeeUid ||
        workDate is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(workDate) ||
        document.id != attendanceDocumentId(employeeUid, workDate) ||
        checkInAt is! Timestamp ||
        !const {'biometric', 'nfc', 'nfc_mobile', 'manual'}.contains(method)) {
      throw const AttendanceUnconfirmedException();
    }
    if (status == 'working' && !data.containsKey('checkOutAt')) {
      return AttendanceRecord(
        employeeId: employeeUid,
        workDate: workDate,
        checkInAt: checkInAt.toDate(),
        method: method as String,
      );
    }
    if (status != 'completed' ||
        checkOutAt is! Timestamp ||
        checkOutAt.compareTo(checkInAt) < 0) {
      throw const AttendanceUnconfirmedException();
    }
    return AttendanceRecord(
      employeeId: employeeUid,
      workDate: workDate,
      checkInAt: checkInAt.toDate(),
      checkOutAt: checkOutAt.toDate(),
      method: method as String,
    );
  }
}
