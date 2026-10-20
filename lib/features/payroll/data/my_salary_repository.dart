import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_attendance/features/payroll/domain/work_time_calculator.dart';

class MySalaryAccessException implements Exception {
  const MySalaryAccessException();
}

class MySalaryData {
  const MySalaryData({
    required this.uid,
    required this.hourlyRate,
    required this.attendance,
  });

  final String uid;
  final Object? hourlyRate;
  final List<WorkAttendance> attendance;
}

abstract class MySalaryRepository {
  Future<MySalaryData> loadPeriod(String startDate, String endDate);
}

/// Reads only the signed-in employee. No caller-supplied employee UID is accepted.
class FirestoreMySalaryRepository implements MySalaryRepository {
  FirestoreMySalaryRepository({
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
  Future<MySalaryData> loadPeriod(String startDate, String endDate) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const MySalaryAccessException();
    final profile = await _firestore
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    if (_auth.currentUser?.uid != uid ||
        profile.data()?['role'] != 'employee' ||
        profile.data()?['status'] != 'active') {
      throw const MySalaryAccessException();
    }
    final records = await _firestore
        .collection('attendance')
        .where('employeeId', isEqualTo: uid)
        .where('workDate', isGreaterThanOrEqualTo: startDate)
        .where('workDate', isLessThanOrEqualTo: endDate)
        .orderBy('workDate', descending: true)
        .get(const GetOptions(source: Source.server));
    if (_auth.currentUser?.uid != uid) throw const MySalaryAccessException();
    return MySalaryData(
      uid: uid,
      hourlyRate: profile.data()?['hourlyRate'],
      attendance: [
        for (final doc in records.docs)
          WorkAttendance(
            employeeUid: doc.data()['employeeId'] is String
                ? doc.data()['employeeId'] as String
                : '',
            workDate: doc.data()['workDate'] is String
                ? doc.data()['workDate'] as String
                : null,
            status: doc.data()['status'] is String
                ? doc.data()['status'] as String
                : null,
            method: doc.data()['method'] is String
                ? doc.data()['method'] as String
                : null,
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
