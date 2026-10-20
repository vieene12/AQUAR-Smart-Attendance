import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/payroll/domain/work_time_calculator.dart';

class PayrollEmployee {
  const PayrollEmployee({
    required this.uid,
    required this.name,
    this.hourlyRate,
  });

  final String uid;
  final String name;
  final int? hourlyRate;
}

class PayrollData {
  const PayrollData({required this.employees, required this.attendance});

  final List<PayrollEmployee> employees;
  final List<WorkAttendance> attendance;
}

abstract class PayrollRepository {
  Future<bool> canAccess(UserProfile profile);
  Future<PayrollData> loadPeriod(String startDate, String endDate);
}

class FirestorePayrollRepository implements PayrollRepository {
  FirestorePayrollRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _providedFirestore = firestore,
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
    final user = await _firestore
        .collection('users')
        .doc(profile.uid)
        .get(const GetOptions(source: Source.server));
    return user.data()?['status'] == 'active' &&
        user.data()?['role'] == profile.role.name;
  }

  @override
  Future<PayrollData> loadPeriod(String startDate, String endDate) async {
    final users = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'employee')
        .get(const GetOptions(source: Source.server));
    final attendance = await _firestore
        .collection('attendance')
        .where('workDate', isGreaterThanOrEqualTo: startDate)
        .where('workDate', isLessThanOrEqualTo: endDate)
        .get(const GetOptions(source: Source.server));
    return PayrollData(
      employees: [
        for (final user in users.docs)
          PayrollEmployee(
            uid: user.id,
            name:
                (user.data()['fullName'] as String?)?.trim().isNotEmpty == true
                ? (user.data()['fullName'] as String).trim()
                : user.id,
            hourlyRate: user.data()['hourlyRate'] is int
                ? user.data()['hourlyRate'] as int
                : null,
          ),
      ]..sort((a, b) => a.name.compareTo(b.name)),
      attendance: [
        for (final doc in attendance.docs)
          WorkAttendance(
            employeeUid: doc.data()['employeeId'] is String
                ? doc.data()['employeeId'] as String
                : '',
            workDate: doc.data()['workDate'] as String?,
            status: doc.data()['status'] as String?,
            method: doc.data()['method'] as String?,
            checkInAt: doc.data()['checkInAt'] is Timestamp
                ? (doc.data()['checkInAt'] as Timestamp).toDate()
                : null,
            checkOutAt: doc.data()['checkOutAt'] is Timestamp
                ? (doc.data()['checkOutAt'] as Timestamp).toDate()
                : null,
          ),
      ],
    );
  }
}
