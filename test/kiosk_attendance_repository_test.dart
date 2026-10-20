import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/kiosk/data/kiosk_attendance_repository.dart';

final _now = DateTime.utc(2026, 10, 11, 3);

void main() {
  test(
    'Check-in/Check-out NFC dùng cùng document và giữ nguyên trường vào',
    () async {
      final store = _FakeKioskAttendanceStore();
      final writer = TransactionalKioskAttendanceWriter(store);
      await writer.checkIn('04ab01', _now);
      final created = store.attendance['employee-1_2026-10-11']!;
      expect(created['method'], 'nfc');
      expect(created['nfcCardUid'], '04AB01');
      expect(created['operatorUid'], 'manager-1');
      expect(created['checkInAt'], store.serverTimestamp);
      expect(created['recordedAt'], store.serverTimestamp);
      expect(created['status'], 'working');

      store.timestamp = Timestamp.fromDate(DateTime.utc(2026, 10, 11, 10));
      await writer.checkOut('04AB01', _now);
      final completed = store.attendance['employee-1_2026-10-11']!;
      expect(completed['method'], 'nfc');
      expect(completed['checkInAt'], created['checkInAt']);
      expect(completed['operatorUid'], created['operatorUid']);
      expect(completed['status'], 'completed');
      expect(completed['checkOutMethod'], 'nfc');
      expect(completed['checkOutOperatorUid'], 'manager-1');
      expect(completed['checkOutCardUid'], '04AB01');
      expect(completed['checkOutAt'], store.serverTimestamp);
      expect(completed['checkOutRecordedAt'], store.serverTimestamp);
    },
  );

  test('từ chối Check-in trùng và Check-out trùng', () async {
    final store = _FakeKioskAttendanceStore();
    final writer = TransactionalKioskAttendanceWriter(store);
    await writer.checkIn('04AB01', _now);
    await expectLater(
      writer.checkIn('04AB01', _now),
      throwsA(isA<KioskAlreadyCheckedIn>()),
    );
    await writer.checkOut('04AB01', _now);
    await expectLater(
      writer.checkOut('04AB01', _now),
      throwsA(isA<KioskAlreadyCheckedOut>()),
    );
    expect(store.attendance.length, 1);
  });

  test('từ chối Check-out trước Check-in', () async {
    final writer = TransactionalKioskAttendanceWriter(
      _FakeKioskAttendanceStore(),
    );
    await expectLater(
      writer.checkOut('04AB01', _now),
      throwsA(isA<KioskNotCheckedIn>()),
    );
  });

  test('Check-out bản ghi sinh trắc học chỉ bổ sung trường ra', () async {
    final store = _FakeKioskAttendanceStore();
    final original = {
      'employeeId': 'employee-1',
      'workDate': '2026-10-11',
      'checkInAt': Timestamp.fromDate(DateTime.utc(2026, 10, 11, 2)),
      'method': 'biometric',
      'status': 'working',
    };
    store.attendance['employee-1_2026-10-11'] = original;
    await TransactionalKioskAttendanceWriter(store).checkOut('04AB01', _now);
    final saved = store.attendance['employee-1_2026-10-11']!;
    expect(saved['method'], 'biometric');
    expect(saved['checkInAt'], original['checkInAt']);
    expect(saved['checkOutMethod'], 'nfc');
  });

  test(
    'thu hồi thẻ hoặc khóa nhân viên ngăn ghi dù đã quét trước đó',
    () async {
      final store = _FakeKioskAttendanceStore();
      final writer = TransactionalKioskAttendanceWriter(store);
      store.cards.clear();
      await expectLater(
        writer.checkIn('04AB01', _now),
        throwsA(isA<KioskCardUnavailable>()),
      );
      store.cards['04AB01'] = {'employeeUid': 'employee-1'};
      store.links.clear();
      await expectLater(
        writer.checkIn('04AB01', _now),
        throwsA(isA<KioskCardUnavailable>()),
      );
      store.links['employee-1'] = {'cardUid': '04AB01'};
      store.users['employee-1']!['status'] = 'locked';
      await expectLater(
        writer.checkIn('04AB01', _now),
        throwsA(isA<KioskEmployeeInactive>()),
      );
      expect(store.attendance, isEmpty);
    },
  );

  test('thu hồi hoặc khóa sau Check-in cũng chặn Check-out', () async {
    final store = _FakeKioskAttendanceStore();
    final writer = TransactionalKioskAttendanceWriter(store);
    await writer.checkIn('04AB01', _now);
    store.cards.clear();
    await expectLater(
      writer.checkOut('04AB01', _now),
      throwsA(isA<KioskCardUnavailable>()),
    );
    store.cards['04AB01'] = {'employeeUid': 'employee-1'};
    store.users['employee-1']!['status'] = 'locked';
    await expectLater(
      writer.checkOut('04AB01', _now),
      throwsA(isA<KioskEmployeeInactive>()),
    );
    expect(store.attendance['employee-1_2026-10-11']!['status'], 'working');
  });

  test('operator bị khóa hoặc không đăng nhập không thể ghi', () async {
    final store = _FakeKioskAttendanceStore();
    final writer = TransactionalKioskAttendanceWriter(store);
    store.users['manager-1']!['status'] = 'locked';
    await expectLater(
      writer.checkIn('04AB01', _now),
      throwsA(isA<KioskOperatorUnauthorized>()),
    );
    store.users['manager-1']!['status'] = 'active';
    store.users['manager-1']!['role'] = 'employee';
    await expectLater(
      writer.checkIn('04AB01', _now),
      throwsA(isA<KioskOperatorUnauthorized>()),
    );
    store.operator = null;
    await expectLater(
      writer.checkIn('04AB01', _now),
      throwsA(isA<KioskOperatorUnauthorized>()),
    );
  });

  test('mất mạng không commit bản ghi', () async {
    final store = _FakeKioskAttendanceStore()
      ..networkError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
    await expectLater(
      TransactionalKioskAttendanceWriter(store).checkIn('04AB01', _now),
      throwsA(isA<FirebaseException>()),
    );
    expect(store.attendance, isEmpty);
  });
}

class _FakeKioskAttendanceStore implements KioskAttendanceStore {
  String? operator = 'manager-1';
  Timestamp timestamp = Timestamp.fromDate(_now);
  Object? networkError;
  final users = <String, Map<String, dynamic>>{
    'manager-1': {'role': 'manager', 'status': 'active'},
    'employee-1': {'role': 'employee', 'status': 'active'},
  };
  final cards = <String, Map<String, dynamic>>{
    '04AB01': {'employeeUid': 'employee-1'},
  };
  final links = <String, Map<String, dynamic>>{
    'employee-1': {'cardUid': '04AB01'},
  };
  final attendance = <String, Map<String, dynamic>>{};

  @override
  String? get operatorUid => operator;

  @override
  Object get serverTimestamp => timestamp;

  @override
  Future<void> transact(
    Future<void> Function(KioskAttendanceTransaction tx) action,
  ) async {
    if (networkError != null) throw networkError!;
    final draft = {
      for (final entry in attendance.entries)
        entry.key: Map<String, dynamic>.of(entry.value),
    };
    await action(_FakeKioskTransaction(users, cards, links, draft));
    attendance
      ..clear()
      ..addAll(draft);
  }
}

class _FakeKioskTransaction implements KioskAttendanceTransaction {
  _FakeKioskTransaction(
    this.users,
    this.cards,
    this.links,
    this.attendanceData,
  );
  final Map<String, Map<String, dynamic>> users;
  final Map<String, Map<String, dynamic>> cards;
  final Map<String, Map<String, dynamic>> links;
  final Map<String, Map<String, dynamic>> attendanceData;

  @override
  Future<Map<String, dynamic>?> user(String uid) async => users[uid];

  @override
  Future<Map<String, dynamic>?> card(String cardUid) async => cards[cardUid];

  @override
  Future<Map<String, dynamic>?> employeeCard(String employeeUid) async =>
      links[employeeUid];

  @override
  Future<Map<String, dynamic>?> attendance(String documentId) async =>
      attendanceData[documentId];

  @override
  void createAttendance(String documentId, Map<String, dynamic> data) =>
      attendanceData[documentId] = Map<String, dynamic>.of(data);

  @override
  void updateAttendance(String documentId, Map<String, dynamic> changes) =>
      attendanceData[documentId]!.addAll(changes);
}
