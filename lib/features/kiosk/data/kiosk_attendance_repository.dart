import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_attendance/features/admin/nfc_cards/data/nfc_card_repository.dart';
import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';

class KioskOperatorUnauthorized implements Exception {
  const KioskOperatorUnauthorized();
}

class KioskCardUnavailable implements Exception {
  const KioskCardUnavailable();
}

class KioskEmployeeInactive implements Exception {
  const KioskEmployeeInactive();
}

class KioskAlreadyCheckedIn implements Exception {
  const KioskAlreadyCheckedIn();
}

class KioskNotCheckedIn implements Exception {
  const KioskNotCheckedIn();
}

class KioskAlreadyCheckedOut implements Exception {
  const KioskAlreadyCheckedOut();
}

class KioskInvalidAttendance implements Exception {
  const KioskInvalidAttendance();
}

abstract class KioskAttendanceTransaction {
  Future<Map<String, dynamic>?> user(String uid);
  Future<Map<String, dynamic>?> card(String cardUid);
  Future<Map<String, dynamic>?> employeeCard(String employeeUid);
  Future<Map<String, dynamic>?> attendance(String documentId);
  void createAttendance(String documentId, Map<String, dynamic> data);
  void updateAttendance(String documentId, Map<String, dynamic> changes);
}

abstract class KioskAttendanceStore {
  String? get operatorUid;
  Object get serverTimestamp;
  Future<void> transact(
    Future<void> Function(KioskAttendanceTransaction tx) action,
  );
}

abstract class KioskAttendanceWriter {
  Future<void> checkIn(String cardUid, DateTime now);
  Future<void> checkOut(String cardUid, DateTime now);
}

/// Demo on Spark: Rules constrain state and links, but cannot prove a scan.
class TransactionalKioskAttendanceWriter implements KioskAttendanceWriter {
  const TransactionalKioskAttendanceWriter(this.store);

  final KioskAttendanceStore store;

  @override
  Future<void> checkIn(String rawCardUid, DateTime now) =>
      _write(rawCardUid, now, checkIn: true);

  @override
  Future<void> checkOut(String rawCardUid, DateTime now) =>
      _write(rawCardUid, now, checkIn: false);

  Future<void> _write(
    String rawCardUid,
    DateTime now, {
    required bool checkIn,
  }) async {
    final cardUid = normalizeCardUid(rawCardUid);
    final operatorUid = store.operatorUid;
    if (operatorUid == null) throw const KioskOperatorUnauthorized();
    final workDate = vietnamWorkDate(now);
    await store.transact((tx) async {
      final operator = await tx.user(operatorUid);
      if (operator?['status'] != 'active' ||
          !['admin', 'manager'].contains(operator?['role'])) {
        throw const KioskOperatorUnauthorized();
      }
      final card = await tx.card(cardUid);
      if (card == null ||
          (card['status'] != null && card['status'] != 'active')) {
        throw const KioskCardUnavailable();
      }
      final employeeUid = card['employeeUid'];
      if (employeeUid is! String || employeeUid.isEmpty) {
        throw const KioskCardUnavailable();
      }
      final link = await tx.employeeCard(employeeUid);
      if (link?['cardUid'] != cardUid) throw const KioskCardUnavailable();
      final employee = await tx.user(employeeUid);
      if (employee?['role'] != 'employee' || employee?['status'] != 'active') {
        throw const KioskEmployeeInactive();
      }
      final documentId = attendanceDocumentId(employeeUid, workDate);
      final existing = await tx.attendance(documentId);
      if (checkIn) {
        if (existing != null) throw const KioskAlreadyCheckedIn();
        tx.createAttendance(documentId, {
          'employeeId': employeeUid,
          'workDate': workDate,
          'checkInAt': store.serverTimestamp,
          'method': 'nfc',
          'status': 'working',
          'nfcCardUid': cardUid,
          'operatorUid': operatorUid,
          'recordedAt': store.serverTimestamp,
        });
        return;
      }
      if (existing == null) throw const KioskNotCheckedIn();
      if (existing['status'] == 'completed' ||
          existing.containsKey('checkOutAt')) {
        throw const KioskAlreadyCheckedOut();
      }
      if (existing['employeeId'] != employeeUid ||
          existing['workDate'] != workDate ||
          existing['checkInAt'] is! Timestamp ||
          !['biometric', 'nfc'].contains(existing['method']) ||
          existing['status'] != 'working') {
        throw const KioskInvalidAttendance();
      }
      tx.updateAttendance(documentId, {
        'status': 'completed',
        'checkOutAt': store.serverTimestamp,
        'checkOutMethod': 'nfc',
        'checkOutOperatorUid': operatorUid,
        'checkOutCardUid': cardUid,
        'checkOutRecordedAt': store.serverTimestamp,
      });
    });
  }
}

class FirestoreKioskAttendanceStore implements KioskAttendanceStore {
  FirestoreKioskAttendanceStore({
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
    Future<void> Function(KioskAttendanceTransaction tx) action,
  ) => _firestore.runTransaction((transaction) async {
    await action(_FirestoreKioskAttendanceTransaction(_firestore, transaction));
  });
}

class _FirestoreKioskAttendanceTransaction
    implements KioskAttendanceTransaction {
  _FirestoreKioskAttendanceTransaction(this.firestore, this.transaction);

  final FirebaseFirestore firestore;
  final Transaction transaction;

  Future<Map<String, dynamic>?> _get(String collection, String id) async =>
      (await transaction.get(firestore.collection(collection).doc(id))).data();

  @override
  Future<Map<String, dynamic>?> user(String uid) => _get('users', uid);

  @override
  Future<Map<String, dynamic>?> card(String cardUid) =>
      _get('nfc_cards', cardUid);

  @override
  Future<Map<String, dynamic>?> employeeCard(String employeeUid) =>
      _get('nfc_employee_cards', employeeUid);

  @override
  Future<Map<String, dynamic>?> attendance(String documentId) =>
      _get('attendance', documentId);

  @override
  void createAttendance(String documentId, Map<String, dynamic> data) =>
      transaction.set(firestore.collection('attendance').doc(documentId), data);

  @override
  void updateAttendance(String documentId, Map<String, dynamic> changes) =>
      transaction.update(
        firestore.collection('attendance').doc(documentId),
        changes,
      );
}
