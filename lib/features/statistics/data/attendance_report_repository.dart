import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/payroll/domain/work_time_calculator.dart';
import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';

class AttendanceReportAccessException implements Exception {
  const AttendanceReportAccessException();
}

class AttendanceReportData {
  const AttendanceReportData({
    required this.records,
    required this.employeeNames,
    this.employeeEmails = const {},
  });

  final List<StatisticsAttendance> records;
  final Map<String, String> employeeNames;
  final Map<String, String> employeeEmails;
}

abstract class AttendanceReportRepository {
  Future<AttendanceReportData> loadPeriod(
    UserProfile profile,
    String startDate,
    String endDate,
  );
}

class FirestoreAttendanceReportRepository
    implements AttendanceReportRepository {
  FirestoreAttendanceReportRepository({
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
  Future<AttendanceReportData> loadPeriod(
    UserProfile profile,
    String startDate,
    String endDate,
  ) async {
    if (_auth.currentUser?.uid != profile.uid ||
        (profile.role != UserRole.admin && profile.role != UserRole.manager)) {
      throw const AttendanceReportAccessException();
    }
    final account = await _firestore
        .collection('users')
        .doc(profile.uid)
        .get(const GetOptions(source: Source.server));
    if (_auth.currentUser?.uid != profile.uid ||
        account.data()?['role'] != profile.role.name ||
        account.data()?['status'] != 'active') {
      throw const AttendanceReportAccessException();
    }

    final attendance = await _firestore
        .collection('attendance')
        .where('workDate', isGreaterThanOrEqualTo: startDate)
        .where('workDate', isLessThanOrEqualTo: endDate)
        .get(const GetOptions(source: Source.server));
    final users = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'employee')
        .get(const GetOptions(source: Source.server));
    if (_auth.currentUser?.uid != profile.uid) {
      throw const AttendanceReportAccessException();
    }

    return AttendanceReportData(
      employeeNames: {
        for (final user in users.docs)
          user.id:
              user.data()['fullName'] is String &&
                  (user.data()['fullName'] as String).trim().isNotEmpty
              ? (user.data()['fullName'] as String).trim()
              : user.id,
      },
      employeeEmails: {
        for (final user in users.docs)
          if (user.data()['email'] is String)
            user.id: (user.data()['email'] as String).trim(),
      },
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
