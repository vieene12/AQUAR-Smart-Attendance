import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_attendance/features/payroll/domain/work_time_calculator.dart';
import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';

class MyAttendanceReportAccessException implements Exception {
  const MyAttendanceReportAccessException();
}

class MyAttendanceReportData {
  const MyAttendanceReportData({required this.uid, required this.records});

  final String uid;
  final List<StatisticsAttendance> records;
}

abstract class MyAttendanceReportRepository {
  Future<MyAttendanceReportData> loadPeriod(String startDate, String endDate);
}

/// Reads only the signed-in employee. The caller cannot select an employee UID.
class FirestoreMyAttendanceReportRepository
    implements MyAttendanceReportRepository {
  FirestoreMyAttendanceReportRepository({
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
  Future<MyAttendanceReportData> loadPeriod(
    String startDate,
    String endDate,
  ) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const MyAttendanceReportAccessException();
    final account = await _firestore
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    if (_auth.currentUser?.uid != uid ||
        account.data()?['role'] != 'employee' ||
        account.data()?['status'] != 'active') {
      throw const MyAttendanceReportAccessException();
    }

    final attendance = await _firestore
        .collection('attendance')
        .where('employeeId', isEqualTo: uid)
        .where('workDate', isGreaterThanOrEqualTo: startDate)
        .where('workDate', isLessThanOrEqualTo: endDate)
        .orderBy('workDate', descending: true)
        .get(const GetOptions(source: Source.server));
    if (_auth.currentUser?.uid != uid) {
      throw const MyAttendanceReportAccessException();
    }
    return MyAttendanceReportData(
      uid: uid,
      records: [
        for (final document in attendance.docs)
          StatisticsAttendance(
            WorkAttendance(
              employeeUid: document.data()['employeeId'] is String
                  ? document.data()['employeeId'] as String
                  : '',
              workDate: document.data()['workDate'] is String
                  ? document.data()['workDate'] as String
                  : null,
              status: document.data()['status'] is String
                  ? document.data()['status'] as String
                  : null,
              method: document.data()['method'] is String
                  ? document.data()['method'] as String
                  : null,
              checkInAt: document.data()['checkInAt'] is Timestamp
                  ? (document.data()['checkInAt'] as Timestamp).toDate()
                  : null,
              checkOutAt: document.data()['checkOutAt'] is Timestamp
                  ? (document.data()['checkOutAt'] as Timestamp).toDate()
                  : null,
            ),
            manualRevision: document.data().containsKey('manualRevision')
                ? (document.data()['manualRevision'] is int
                      ? document.data()['manualRevision'] as int
                      : -1)
                : null,
          ),
      ],
    );
  }
}
