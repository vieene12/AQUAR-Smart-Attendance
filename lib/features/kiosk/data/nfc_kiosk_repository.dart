import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smart_attendance/features/admin/nfc_cards/data/nfc_card_repository.dart';
import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';

enum KioskCardStatus { unregisteredOrRevoked, employeeInactive, active }

enum KioskAttendanceStatus { notCheckedIn, working, completed }

class KioskLookup {
  const KioskLookup({
    required this.cardStatus,
    this.employeeName,
    this.attendanceStatus,
  });

  final KioskCardStatus cardStatus;
  final String? employeeName;
  final KioskAttendanceStatus? attendanceStatus;
}

abstract class KioskDataSource {
  Future<Map<String, dynamic>?> card(String cardUid);
  Future<Map<String, dynamic>?> employeeCard(String employeeUid);
  Future<Map<String, dynamic>?> employee(String employeeUid);
  Future<Map<String, dynamic>?> attendance(String documentId);
}

class FirestoreKioskDataSource implements KioskDataSource {
  FirestoreKioskDataSource({FirebaseFirestore? firestore})
    : _providedFirestore = firestore;

  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;

  Future<Map<String, dynamic>?> _get(String collection, String id) async {
    final snapshot = await _firestore
        .collection(collection)
        .doc(id)
        .get(const GetOptions(source: Source.server));
    return snapshot.data();
  }

  @override
  Future<Map<String, dynamic>?> card(String cardUid) =>
      _get('nfc_cards', cardUid);

  @override
  Future<Map<String, dynamic>?> employeeCard(String employeeUid) =>
      _get('nfc_employee_cards', employeeUid);

  @override
  Future<Map<String, dynamic>?> employee(String employeeUid) =>
      _get('users', employeeUid);

  @override
  Future<Map<String, dynamic>?> attendance(String documentId) =>
      _get('attendance', documentId);
}

abstract class KioskLookupRepository {
  Future<KioskLookup> lookup(String cardUid, DateTime now);
}

class NfcKioskRepository implements KioskLookupRepository {
  const NfcKioskRepository(this.source);

  final KioskDataSource source;

  @override
  Future<KioskLookup> lookup(String rawCardUid, DateTime now) async {
    final cardUid = normalizeCardUid(rawCardUid);
    final card = await source.card(cardUid);
    // 08.3 keeps only active cards as documents. Reject any future non-active
    // status as well, rather than treating an unfamiliar state as usable.
    if (card == null ||
        (card['status'] != null && card['status'] != 'active')) {
      return const KioskLookup(
        cardStatus: KioskCardStatus.unregisteredOrRevoked,
      );
    }
    final employeeUid = card['employeeUid'];
    if (employeeUid is! String || employeeUid.isEmpty) {
      throw const FormatException('Liên kết thẻ không hợp lệ.');
    }
    final link = await source.employeeCard(employeeUid);
    if (link?['cardUid'] != cardUid) {
      return const KioskLookup(
        cardStatus: KioskCardStatus.unregisteredOrRevoked,
      );
    }
    final employee = await source.employee(employeeUid);
    if (employee == null ||
        employee['role'] != 'employee' ||
        employee['status'] != 'active') {
      return KioskLookup(
        cardStatus: KioskCardStatus.employeeInactive,
        employeeName: _name(employee),
      );
    }
    final workDate = vietnamWorkDate(now);
    final attendance = await source.attendance(
      attendanceDocumentId(employeeUid, workDate),
    );
    return KioskLookup(
      cardStatus: KioskCardStatus.active,
      employeeName: _name(employee) ?? employeeUid,
      attendanceStatus: _attendanceStatus(attendance, employeeUid, workDate),
    );
  }

  String? _name(Map<String, dynamic>? employee) {
    final value = employee?['fullName'] ?? employee?['name'];
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  KioskAttendanceStatus _attendanceStatus(
    Map<String, dynamic>? data,
    String employeeUid,
    String workDate,
  ) {
    if (data == null) return KioskAttendanceStatus.notCheckedIn;
    if (data['employeeId'] != employeeUid ||
        data['workDate'] != workDate ||
        data['checkInAt'] is! Timestamp) {
      throw const FormatException('Bản ghi chấm công không hợp lệ.');
    }
    if (data['status'] == 'working' && data['checkOutAt'] == null) {
      return KioskAttendanceStatus.working;
    }
    if (data['status'] == 'completed' && data['checkOutAt'] is Timestamp) {
      return KioskAttendanceStatus.completed;
    }
    throw const FormatException('Bản ghi chấm công không hợp lệ.');
  }
}
