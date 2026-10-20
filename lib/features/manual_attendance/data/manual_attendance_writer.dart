import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';
import 'package:smart_attendance/features/manual_attendance/data/manual_attendance_repository.dart';

class ManualInvalidInput implements Exception {
  const ManualInvalidInput(this.message);
  final String message;
}

class ManualWriteUnauthorized implements Exception {
  const ManualWriteUnauthorized();
}

class ManualEmployeeInactive implements Exception {
  const ManualEmployeeInactive();
}

class ManualWriteConflict implements Exception {
  const ManualWriteConflict();
}

class ManualInvalidRecord implements Exception {
  const ManualInvalidRecord();
}

class ManualAttendanceChange {
  const ManualAttendanceChange({
    required this.employeeUid,
    required this.date,
    required this.checkInAt,
    required this.reason,
    required this.expected,
    this.checkOutAt,
  });

  final String employeeUid;
  final DateTime date;
  final DateTime checkInAt;
  final DateTime? checkOutAt;
  final String reason;
  final ManualAttendanceRecord? expected;
}

abstract class ManualAttendanceTransaction {
  Future<Map<String, dynamic>?> user(String uid);
  Future<Map<String, dynamic>?> attendance(String id);
  Future<Map<String, dynamic>?> audit(String id);
  void setAttendance(String id, Map<String, dynamic> data);
  void createAudit(String id, Map<String, dynamic> data);
}

abstract class ManualAttendanceStore {
  String? get operatorUid;
  Object get serverTimestamp;
  Future<void> transact(
    Future<void> Function(ManualAttendanceTransaction tx) action,
  );
}

abstract class ManualAttendanceWriter {
  Future<void> save(ManualAttendanceChange change);
}

class TransactionalManualAttendanceWriter implements ManualAttendanceWriter {
  const TransactionalManualAttendanceWriter(this.store);

  final ManualAttendanceStore store;

  @override
  Future<void> save(ManualAttendanceChange change) async {
    final reason = change.reason.trim();
    final workDate = _workDate(change.date);
    if (reason.isEmpty || reason.length > 500) {
      throw const ManualInvalidInput(
        'Nhập lý do điều chỉnh (tối đa 500 ký tự).',
      );
    }
    if (vietnamWorkDate(change.checkInAt) != workDate ||
        (change.checkOutAt != null &&
            (vietnamWorkDate(change.checkOutAt!) != workDate ||
                !change.checkOutAt!.isAfter(change.checkInAt)))) {
      throw const ManualInvalidInput(
        'Giờ ra phải sau giờ vào và cùng ngày; chưa hỗ trợ ca qua đêm.',
      );
    }
    final operatorUid = store.operatorUid;
    if (operatorUid == null) throw const ManualWriteUnauthorized();
    final attendanceId = attendanceDocumentId(change.employeeUid, workDate);

    await store.transact((tx) async {
      final operator = await tx.user(operatorUid);
      if (operator?['status'] != 'active' ||
          !['admin', 'manager'].contains(operator?['role'])) {
        throw const ManualWriteUnauthorized();
      }
      final employee = await tx.user(change.employeeUid);
      if (employee?['role'] != 'employee' || employee?['status'] != 'active') {
        throw const ManualEmployeeInactive();
      }
      final existing = await tx.attendance(attendanceId);
      if (existing != null &&
          !_validExisting(existing, change.employeeUid, workDate)) {
        throw const ManualInvalidRecord();
      }
      if (!_matchesExpected(existing, change.expected)) {
        throw const ManualWriteConflict();
      }
      if (existing != null &&
          existing['checkOutAt'] != null &&
          change.checkOutAt == null) {
        throw const ManualInvalidInput('Không thể xóa giờ ra đã ghi.');
      }
      final oldCheckIn = (existing?['checkInAt'] as Timestamp?)?.toDate();
      final oldCheckOut = (existing?['checkOutAt'] as Timestamp?)?.toDate();
      if (existing != null &&
          _sameTime(oldCheckIn, change.checkInAt) &&
          _sameTime(oldCheckOut, change.checkOutAt)) {
        throw const ManualInvalidInput('Giờ chấm công chưa thay đổi.');
      }

      final revision = (existing?['manualRevision'] as int? ?? 0) + 1;
      final auditId = '${attendanceId}_$revision';
      if (await tx.audit(auditId) != null) throw const ManualWriteConflict();
      final before = Map<String, dynamic>.from(existing ?? const {});
      final after = Map<String, dynamic>.from(before)
        ..addAll({
          'employeeId': change.employeeUid,
          'workDate': workDate,
          'checkInAt': Timestamp.fromDate(change.checkInAt),
          'method': existing?['method'] ?? 'manual',
          'status': change.checkOutAt == null ? 'working' : 'completed',
          'manualRevision': revision,
          'lastManualAt': store.serverTimestamp,
          'lastManualBy': operatorUid,
        });
      if (change.checkOutAt != null) {
        after['checkOutAt'] = Timestamp.fromDate(change.checkOutAt!);
        if (existing?['checkOutAt'] == null) {
          after['checkOutMethod'] = 'manual';
        }
      }
      final action = existing == null
          ? 'create'
          : existing['checkOutAt'] == null && change.checkOutAt != null
          ? 'add_checkout'
          : 'adjust';
      tx.setAttendance(attendanceId, after);
      tx.createAudit(auditId, {
        'attendanceId': attendanceId,
        'employeeUid': change.employeeUid,
        'operatorUid': operatorUid,
        'reason': reason,
        'action': action,
        'revision': revision,
        'before': before,
        'after': after,
        'createdAt': store.serverTimestamp,
      });
    });
  }

  bool _matchesExpected(
    Map<String, dynamic>? data,
    ManualAttendanceRecord? expected,
  ) {
    if (data == null || expected == null) {
      return data == null && expected == null;
    }
    return _sameTime(
          (data['checkInAt'] as Timestamp?)?.toDate(),
          expected.checkInAt,
        ) &&
        _sameTime(
          (data['checkOutAt'] as Timestamp?)?.toDate(),
          expected.checkOutAt,
        ) &&
        data['status'] == expected.status &&
        data['method'] == expected.method &&
        data['checkOutMethod'] == expected.checkOutMethod &&
        data['manualRevision'] == expected.manualRevision;
  }

  bool _sameTime(DateTime? first, DateTime? second) => first == null
      ? second == null
      : second != null && first.isAtSameMomentAs(second);

  bool _validExisting(Map<String, dynamic> data, String uid, String workDate) {
    final checkIn = data['checkInAt'];
    if (data['employeeId'] != uid ||
        data['workDate'] != workDate ||
        checkIn is! Timestamp ||
        vietnamWorkDate(checkIn.toDate()) != workDate ||
        !['biometric', 'nfc', 'manual'].contains(data['method'])) {
      return false;
    }
    if (data['status'] == 'working') return !data.containsKey('checkOutAt');
    final checkOut = data['checkOutAt'];
    return data['status'] == 'completed' &&
        checkOut is Timestamp &&
        checkOut.compareTo(checkIn) > 0 &&
        vietnamWorkDate(checkOut.toDate()) == workDate;
  }

  String _workDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class FirestoreManualAttendanceStore implements ManualAttendanceStore {
  FirestoreManualAttendanceStore({
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
  String? get operatorUid => _auth.currentUser?.uid;

  @override
  Object get serverTimestamp => FieldValue.serverTimestamp();

  @override
  Future<void> transact(
    Future<void> Function(ManualAttendanceTransaction tx) action,
  ) => _firestore.runTransaction((transaction) async {
    await action(
      _FirestoreManualAttendanceTransaction(_firestore, transaction),
    );
  });
}

class _FirestoreManualAttendanceTransaction
    implements ManualAttendanceTransaction {
  _FirestoreManualAttendanceTransaction(this.firestore, this.transaction);

  final FirebaseFirestore firestore;
  final Transaction transaction;

  Future<Map<String, dynamic>?> _get(String collection, String id) async =>
      (await transaction.get(firestore.collection(collection).doc(id))).data();

  @override
  Future<Map<String, dynamic>?> user(String uid) => _get('users', uid);

  @override
  Future<Map<String, dynamic>?> attendance(String id) => _get('attendance', id);

  @override
  Future<Map<String, dynamic>?> audit(String id) =>
      _get('attendance_audit', id);

  @override
  void setAttendance(String id, Map<String, dynamic> data) =>
      transaction.set(firestore.collection('attendance').doc(id), data);

  @override
  void createAudit(String id, Map<String, dynamic> data) =>
      transaction.set(firestore.collection('attendance_audit').doc(id), data);
}
