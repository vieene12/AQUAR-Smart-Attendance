import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';

class TeamEmployee {
  const TeamEmployee({
    required this.uid,
    required this.name,
    this.code,
    this.position,
    this.shiftStart,
    this.shiftEnd,
  });

  final String uid;
  final String name;
  final String? code;
  final String? position;
  final String? shiftStart;
  final String? shiftEnd;
}

class TeamAttendanceEntry {
  const TeamAttendanceEntry({required this.employee, required this.record});

  final TeamEmployee employee;
  final AttendanceRecord record;

  bool get isLate {
    final start = employee.shiftStart;
    if (start == null ||
        !RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(start)) {
      return false;
    }
    final local = vietnamWallTime(record.checkInAt);
    final seconds = local.hour * 3600 + local.minute * 60 + local.second;
    final shiftSeconds =
        (int.parse(start.substring(0, 2)) * 60 +
            int.parse(start.substring(3))) *
        60;
    return seconds > shiftSeconds;
  }
}

/// Hồ sơ cũ chưa có managerUid được hiển thị cho quản lý cho đến khi Admin phân công.
bool canManagerViewEmployee(UserProfile profile, Object? managerUid) {
  if (profile.role == UserRole.admin) return true;
  if (profile.role != UserRole.manager) return false;
  return managerUid == null ||
      managerUid is String &&
          (managerUid.trim().isEmpty || managerUid == profile.uid);
}

abstract class TeamAttendanceRepository {
  Future<List<TeamAttendanceEntry>> load(
    UserProfile profile, {
    DateTime? startDate,
    DateTime? endDate,
    bool workingTodayOnly = false,
  });
}

class FirestoreTeamAttendanceRepository implements TeamAttendanceRepository {
  FirestoreTeamAttendanceRepository({
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
  Future<List<TeamAttendanceEntry>> load(
    UserProfile profile, {
    DateTime? startDate,
    DateTime? endDate,
    bool workingTodayOnly = false,
  }) async {
    if (_auth.currentUser?.uid != profile.uid ||
        profile.role == UserRole.employee) {
      throw const AttendanceUnauthorizedException();
    }
    final operator = await _firestore
        .collection('users')
        .doc(profile.uid)
        .get(const GetOptions(source: Source.server));
    if (operator.data()?['role'] != profile.role.name ||
        operator.data()?['status'] != 'active') {
      throw const AttendanceUnauthorizedException();
    }
    final employees = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'employee')
        .get(const GetOptions(source: Source.server));
    final allowed = <String, TeamEmployee>{};
    for (final doc in employees.docs) {
      final data = doc.data();
      if (!canManagerViewEmployee(profile, data['managerUid'])) {
        continue;
      }
      allowed[doc.id] = TeamEmployee(
        uid: doc.id,
        name: _text(data['fullName']) ?? _text(data['name']) ?? doc.id,
        code: _text(data['employeeCode']),
        position: _text(data['position']),
        shiftStart: _text(data['shiftStart']),
        shiftEnd: _text(data['shiftEnd']),
      );
    }
    if (allowed.isEmpty) return [];
    final today = vietnamWorkDate(DateTime.now());
    Query<Map<String, dynamic>> query = _firestore.collection('attendance');
    if (workingTodayOnly) {
      query = query.where('workDate', isEqualTo: today);
    } else {
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
    }
    final attendance = await query.get(const GetOptions(source: Source.server));
    if (_auth.currentUser?.uid != profile.uid) {
      throw const AttendanceUnauthorizedException();
    }
    final result = <TeamAttendanceEntry>[];
    for (final doc in attendance.docs) {
      final data = doc.data();
      final uid = data['employeeId'];
      final employee = allowed[uid];
      if (employee == null) continue;
      final date = data['workDate'];
      final checkIn = data['checkInAt'];
      final checkOut = data['checkOutAt'];
      if (date is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          checkIn is! Timestamp ||
          doc.id != attendanceDocumentId(uid as String, date)) {
        continue;
      }
      if (vietnamWorkDate(checkIn.toDate()) != date) {
        continue;
      }
      if (workingTodayOnly &&
          (data['status'] != 'working' || checkOut != null)) {
        continue;
      }
      if (data['status'] != 'working' && data['status'] != 'completed') {
        continue;
      }
      if (data['status'] == 'completed' && checkOut is! Timestamp) {
        continue;
      }
      if (data['status'] == 'working' && checkOut != null) {
        continue;
      }
      if (checkOut is Timestamp && checkOut.compareTo(checkIn) < 0) {
        continue;
      }
      final record = AttendanceRecord(
        employeeId: uid,
        workDate: date,
        checkInAt: checkIn.toDate(),
        checkOutAt: checkOut is Timestamp ? checkOut.toDate() : null,
        method: data['method'] is String
            ? data['method'] as String
            : 'biometric',
      );
      result.add(TeamAttendanceEntry(employee: employee, record: record));
    }
    result.sort((a, b) => b.record.checkInAt.compareTo(a.record.checkInAt));
    return result;
  }

  String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
