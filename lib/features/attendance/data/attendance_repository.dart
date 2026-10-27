import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_attendance/core/nfc/nfc_uid.dart';

class AttendanceUnauthorizedException implements Exception {
  const AttendanceUnauthorizedException();
}

class AttendanceSessionExpiredException implements Exception {
  const AttendanceSessionExpiredException();
}

class AttendanceAlreadyCheckedInException implements Exception {
  const AttendanceAlreadyCheckedInException();
}

class AttendanceNotCheckedInException implements Exception {
  const AttendanceNotCheckedInException();
}

class AttendanceAlreadyCheckedOutException implements Exception {
  const AttendanceAlreadyCheckedOutException();
}

class AttendanceUnconfirmedException implements Exception {
  const AttendanceUnconfirmedException();
}

class AttendanceKioskOnlyException implements Exception {
  const AttendanceKioskOnlyException();
}

class AttendanceNfcNotAssignedException implements Exception {
  const AttendanceNfcNotAssignedException();
}

class AttendanceNfcCardUnregisteredException implements Exception {
  const AttendanceNfcCardUnregisteredException();
}

class AttendanceNfcCardNotOwnedException implements Exception {
  const AttendanceNfcCardNotOwnedException();
}

void validateEmployeeNfcCard({
  required String employeeId,
  required String cardUid,
  required String? assignedUid,
  required Map<String, dynamic>? cardData,
}) {
  if (assignedUid == null || assignedUid.isEmpty) {
    throw const AttendanceNfcNotAssignedException();
  }
  if (cardData == null ||
      (cardData['status'] != null && cardData['status'] != 'active')) {
    throw const AttendanceNfcCardUnregisteredException();
  }
  if (assignedUid != cardUid || cardData['employeeUid'] != employeeId) {
    throw const AttendanceNfcCardNotOwnedException();
  }
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.employeeId,
    required this.workDate,
    required this.checkInAt,
    this.checkOutAt,
    this.method = 'biometric',
  });

  final String employeeId;
  final String workDate;
  final DateTime checkInAt;
  final DateTime? checkOutAt;
  final String method;

  Duration? get workedDuration => checkOutAt?.difference(checkInAt);
}

/// Ngày làm việc tại Việt Nam, độc lập với múi giờ được chọn trên thiết bị.
String vietnamWorkDate(DateTime instant) {
  final vietnamTime = instant.toUtc().add(const Duration(hours: 7));
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${vietnamTime.year}-${twoDigits(vietnamTime.month)}-${twoDigits(vietnamTime.day)}';
}

DateTime vietnamWallTime(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 7));

String attendanceDocumentId(String employeeId, String workDate) =>
    '${employeeId}_$workDate';

String workDateFromCalendarDate(DateTime date) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
}

abstract class AttendanceRepository {
  Future<AttendanceRecord?> loadToday(String employeeId);
  Future<AttendanceRecord> checkIn(
    String employeeId, {
    String method = 'biometric',
    String? cardUid,
  });
  Future<AttendanceRecord> checkOut(String employeeId, {String? cardUid});
  Future<List<AttendanceRecord>> loadHistory(
    String employeeId, {
    DateTime? startDate,
    DateTime? endDate,
  });
}

class FirestoreAttendanceRepository implements AttendanceRepository {
  FirestoreAttendanceRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    DateTime Function()? now,
  }) : _providedAuth = auth,
       _providedFirestore = firestore,
       _now = now ?? DateTime.now;

  final FirebaseAuth? _providedAuth;
  final FirebaseFirestore? _providedFirestore;
  final DateTime Function() _now;

  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;

  @override
  Future<AttendanceRecord?> loadToday(String employeeId) async {
    _ensureSignedIn(employeeId);
    final workDate = vietnamWorkDate(_now());
    final document = _attendanceDocument(employeeId, workDate);
    final snapshot = await document.get(
      const GetOptions(source: Source.server),
    );
    return _recordFromSnapshot(snapshot, employeeId, workDate);
  }

  @override
  Future<List<AttendanceRecord>> loadHistory(
    String employeeId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _ensureSignedIn(employeeId);
    Query<Map<String, dynamic>> query = _firestore
        .collection('attendance')
        .where('employeeId', isEqualTo: employeeId);
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
      for (final document in snapshot.docs)
        _recordFromSnapshot(
              document,
              employeeId,
              _historyWorkDate(document, employeeId),
            ) ??
            (throw const AttendanceUnconfirmedException()),
    ];
  }

  String _historyWorkDate(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
    String employeeId,
  ) {
    final workDate = document.data()['workDate'];
    if (workDate is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(workDate) ||
        document.id != attendanceDocumentId(employeeId, workDate)) {
      throw const AttendanceUnconfirmedException();
    }
    return workDate;
  }

  @override
  Future<AttendanceRecord> checkIn(
    String employeeId, {
    String method = 'biometric',
    String? cardUid,
  }) async {
    if (!['biometric', 'nfc_mobile'].contains(method)) {
      throw ArgumentError.value(method, 'method');
    }
    if ((method == 'nfc_mobile') != (cardUid != null)) {
      throw ArgumentError.value(cardUid, 'cardUid');
    }
    final normalizedCardUid = cardUid == null
        ? null
        : normalizeCardUid(cardUid);
    final user = _ensureSignedIn(employeeId);
    await user.reload();
    _ensureSignedIn(employeeId);

    final workDate = vietnamWorkDate(_now());
    final document = _attendanceDocument(employeeId, workDate);
    final profile = _firestore.collection('users').doc(employeeId);

    await _firestore.runTransaction<void>((transaction) async {
      if (normalizedCardUid != null) {
        debugPrint('NFC Employee: đọc hồ sơ users trong transaction.');
      }
      final profileSnapshot = await transaction.get(profile);
      final profileData = profileSnapshot.data();
      if (profileData?['role'] != 'employee' ||
          profileData?['status'] != 'active') {
        throw const AttendanceUnauthorizedException();
      }

      if (normalizedCardUid != null) {
        await _verifyNfcCard(transaction, employeeId, normalizedCardUid);
      }

      if (normalizedCardUid != null) {
        debugPrint('NFC Employee: đọc bản ghi attendance trong transaction.');
      }
      final existing = await transaction.get(document);
      if (existing.exists) {
        throw const AttendanceAlreadyCheckedInException();
      }

      transaction.set(document, {
        'employeeId': employeeId,
        'workDate': workDate,
        'checkInAt': FieldValue.serverTimestamp(),
        'method': method,
        'status': 'working',
        'nfcCardUid': ?normalizedCardUid,
      });
      if (normalizedCardUid != null) {
        debugPrint('NFC Employee: gửi transaction tạo attendance.');
      }
    });

    // Chỉ trả thành công khi đọc được giờ vào đã được server ghi nhận.
    try {
      final saved = await document.get(const GetOptions(source: Source.server));
      return _recordFromSnapshot(saved, employeeId, workDate) ??
          (throw const AttendanceUnconfirmedException());
    } catch (_) {
      throw const AttendanceUnconfirmedException();
    }
  }

  @override
  Future<AttendanceRecord> checkOut(
    String employeeId, {
    String? cardUid,
  }) async {
    final normalizedCardUid = cardUid == null
        ? null
        : normalizeCardUid(cardUid);
    final user = _ensureSignedIn(employeeId);
    await user.reload();
    _ensureSignedIn(employeeId);

    final workDate = vietnamWorkDate(_now());
    final document = _attendanceDocument(employeeId, workDate);
    final profile = _firestore.collection('users').doc(employeeId);

    await _firestore.runTransaction<void>((transaction) async {
      if (normalizedCardUid != null) {
        debugPrint('NFC Employee: đọc hồ sơ users trong transaction.');
      }
      final profileSnapshot = await transaction.get(profile);
      final profileData = profileSnapshot.data();
      if (profileData?['role'] != 'employee' ||
          profileData?['status'] != 'active') {
        throw const AttendanceUnauthorizedException();
      }

      if (normalizedCardUid != null) {
        await _verifyNfcCard(transaction, employeeId, normalizedCardUid);
      }

      if (normalizedCardUid != null) {
        debugPrint('NFC Employee: đọc bản ghi attendance trong transaction.');
      }
      final existing = await transaction.get(document);
      if (!existing.exists) {
        throw const AttendanceNotCheckedInException();
      }
      final data = existing.data();
      if (data?['status'] == 'completed' ||
          data?.containsKey('checkOutAt') == true) {
        throw const AttendanceAlreadyCheckedOutException();
      }
      // Chỉ bản ghi NFC từ kiosk (method='nfc') và thủ công mới cần checkout tại quầy.
      // Bản ghi NFC từ điện thoại (method='nfc_mobile') cho phép checkout bình thường.
      if (data?['method'] == 'nfc' || data?['method'] == 'manual') {
        throw const AttendanceKioskOnlyException();
      }
      // Reject malformed records before attempting the one-way transition.
      _recordFromSnapshot(existing, employeeId, workDate);
      transaction.update(document, {
        'checkOutAt': FieldValue.serverTimestamp(),
        'status': 'completed',
        'checkOutCardUid': ?normalizedCardUid,
      });
      if (normalizedCardUid != null) {
        debugPrint('NFC Employee: gửi transaction cập nhật attendance.');
      }
    });

    try {
      final saved = await document.get(const GetOptions(source: Source.server));
      final record = _recordFromSnapshot(saved, employeeId, workDate);
      if (record?.checkOutAt == null) {
        throw const AttendanceUnconfirmedException();
      }
      return record!;
    } catch (_) {
      throw const AttendanceUnconfirmedException();
    }
  }

  User _ensureSignedIn(String employeeId) {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AttendanceSessionExpiredException();
    }
    if (user.uid != employeeId) {
      throw const AttendanceUnauthorizedException();
    }
    return user;
  }

  Future<void> _verifyNfcCard(
    Transaction transaction,
    String employeeId,
    String cardUid,
  ) async {
    debugPrint('NFC Employee: đọc nfc_employee_cards trong transaction.');
    final link = await transaction.get(
      _firestore.collection('nfc_employee_cards').doc(employeeId),
    );
    final assignedUid = link.data()?['cardUid'];
    if (assignedUid is! String || assignedUid.isEmpty) {
      throw const AttendanceNfcNotAssignedException();
    }
    debugPrint('NFC Employee: đọc nfc_cards trong transaction.');
    final card = await transaction.get(
      _firestore.collection('nfc_cards').doc(cardUid),
    );
    validateEmployeeNfcCard(
      employeeId: employeeId,
      cardUid: cardUid,
      assignedUid: assignedUid,
      cardData: card.data(),
    );
  }

  DocumentReference<Map<String, dynamic>> _attendanceDocument(
    String employeeId,
    String workDate,
  ) => _firestore
      .collection('attendance')
      .doc(attendanceDocumentId(employeeId, workDate));

  AttendanceRecord? _recordFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String employeeId,
    String workDate,
  ) {
    if (!snapshot.exists) return null;
    final data = snapshot.data();
    final checkInAt = data?['checkInAt'];
    if (data?['employeeId'] != employeeId ||
        data?['workDate'] != workDate ||
        ![
          'biometric',
          'nfc',
          'nfc_mobile',
          'manual',
        ].contains(data?['method']) ||
        checkInAt is! Timestamp) {
      throw const AttendanceUnconfirmedException();
    }
    final checkOutAt = data?['checkOutAt'];
    if (data?['status'] == 'working' &&
        data?.containsKey('checkOutAt') == false) {
      return AttendanceRecord(
        employeeId: employeeId,
        workDate: workDate,
        checkInAt: checkInAt.toDate(),
        method: data!['method'] as String,
      );
    }
    if (data?['status'] != 'completed' ||
        checkOutAt is! Timestamp ||
        checkOutAt.compareTo(checkInAt) < 0) {
      throw const AttendanceUnconfirmedException();
    }
    return AttendanceRecord(
      employeeId: employeeId,
      workDate: workDate,
      checkInAt: checkInAt.toDate(),
      checkOutAt: checkOutAt.toDate(),
      method: data!['method'] as String,
    );
  }
}
