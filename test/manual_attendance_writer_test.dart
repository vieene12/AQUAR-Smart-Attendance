import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/manual_attendance/data/manual_attendance_repository.dart';
import 'package:smart_attendance/features/manual_attendance/data/manual_attendance_writer.dart';

final _date = DateTime(2026, 10, 11);
final _in = DateTime.utc(2026, 10, 11, 1);
final _out = DateTime.utc(2026, 10, 11, 9);
const _id = 'employee-1_2026-10-11';

void main() {
  test('tạo bản ghi manual và audit trong cùng transaction', () async {
    final store = _FakeStore();
    await TransactionalManualAttendanceWriter(store).save(_change());
    final data = store.attendance[_id]!;
    final audit = store.audit['${_id}_1']!;
    expect(data['method'], 'manual');
    expect(data['status'], 'working');
    expect(data['manualRevision'], 1);
    expect(data.containsKey('checkOutAt'), isFalse);
    expect(audit['action'], 'create');
    expect(audit['operatorUid'], 'manager-1');
    expect(audit['employeeUid'], 'employee-1');
    expect(audit['reason'], 'Quên chấm công');
    expect(audit['before'], isEmpty);
    expect(audit['after'], data);
    expect(store.commits, 1);
  });

  test('bổ sung giờ ra giữ nguồn biometric và tạo audit riêng', () async {
    final store = _FakeStore()
      ..attendance[_id] = _existing('biometric', completed: false);
    await TransactionalManualAttendanceWriter(store).save(
      _change(
        expected: _expected('biometric', completed: false),
        checkOutAt: _out,
      ),
    );
    final data = store.attendance[_id]!;
    expect(data['method'], 'biometric');
    expect(data['checkOutMethod'], 'manual');
    expect(data['status'], 'completed');
    expect(store.audit['${_id}_1']!['action'], 'add_checkout');
    expect(store.audit['${_id}_1']!['before']['method'], 'biometric');
  });

  test('sửa giờ NFC giữ method gốc, metadata và audit tăng revision', () async {
    final old = _existing('nfc', completed: true)
      ..addAll({
        'checkOutMethod': 'nfc',
        'nfcCardUid': '04AB01',
        'operatorUid': 'manager-1',
        'recordedAt': Timestamp.fromDate(_in),
        'manualRevision': 1,
      });
    final store = _FakeStore()..attendance[_id] = old;
    await TransactionalManualAttendanceWriter(store).save(
      _change(
        checkInAt: _in.add(const Duration(minutes: 15)),
        checkOutAt: _out,
        expected: _expected(
          'nfc',
          completed: true,
          revision: 1,
          checkOutMethod: 'nfc',
        ),
      ),
    );
    final data = store.attendance[_id]!;
    expect(data['method'], 'nfc');
    expect(data['checkOutMethod'], 'nfc');
    expect(data['nfcCardUid'], '04AB01');
    expect(data['manualRevision'], 2);
    expect(store.audit['${_id}_2']!['action'], 'adjust');
    expect(store.audit['${_id}_2']!['before'], old);
    expect(store.audit['${_id}_2']!['after'], data);
  });

  test(
    'thiếu lý do, giờ sai, ca qua đêm và thao tác không đổi đều bị chặn',
    () async {
      final store = _FakeStore();
      final writer = TransactionalManualAttendanceWriter(store);
      await expectLater(
        writer.save(_change(reason: '   ')),
        throwsA(isA<ManualInvalidInput>()),
      );
      await expectLater(
        writer.save(_change(checkOutAt: _in)),
        throwsA(isA<ManualInvalidInput>()),
      );
      await expectLater(
        writer.save(_change(checkOutAt: DateTime.utc(2026, 10, 11, 18))),
        throwsA(isA<ManualInvalidInput>()),
      );
      expect(store.commits, 0);

      store.attendance[_id] = _existing('biometric', completed: false);
      await expectLater(
        writer.save(
          _change(expected: _expected('biometric', completed: false)),
        ),
        throwsA(isA<ManualInvalidInput>()),
      );
      expect(store.audit, isEmpty);
    },
  );

  test(
    'operator/employee bị khóa và quyền Firestore bị từ chối không ghi',
    () async {
      final store = _FakeStore();
      final writer = TransactionalManualAttendanceWriter(store);
      store.users['manager-1']!['status'] = 'locked';
      await expectLater(
        writer.save(_change()),
        throwsA(isA<ManualWriteUnauthorized>()),
      );
      store.users['manager-1']!['status'] = 'active';
      store.users['employee-1']!['status'] = 'locked';
      await expectLater(
        writer.save(_change()),
        throwsA(isA<ManualEmployeeInactive>()),
      );
      store.users['employee-1']!['status'] = 'active';
      store.error = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      await expectLater(
        writer.save(_change()),
        throwsA(isA<FirebaseException>()),
      );
      expect(store.attendance, isEmpty);
      expect(store.audit, isEmpty);
    },
  );

  test('bản ghi đổi đồng thời hoặc audit ID trùng không bị ghi đè', () async {
    final store = _FakeStore()
      ..attendance[_id] = _existing('biometric', completed: false);
    final writer = TransactionalManualAttendanceWriter(store);
    await expectLater(
      writer.save(_change()),
      throwsA(isA<ManualWriteConflict>()),
    );
    await expectLater(
      writer.save(
        _change(
          expected: _expected('biometric', completed: true),
          checkOutAt: _out,
        ),
      ),
      throwsA(isA<ManualWriteConflict>()),
    );
    store.audit['${_id}_1'] = {'action': 'old'};
    await expectLater(
      writer.save(
        _change(
          expected: _expected('biometric', completed: false),
          checkOutAt: _out,
        ),
      ),
      throwsA(isA<ManualWriteConflict>()),
    );
    expect(store.attendance[_id]!['status'], 'working');
  });
}

ManualAttendanceChange _change({
  DateTime? checkInAt,
  DateTime? checkOutAt,
  String reason = 'Quên chấm công',
  ManualAttendanceRecord? expected,
}) => ManualAttendanceChange(
  employeeUid: 'employee-1',
  date: _date,
  checkInAt: checkInAt ?? _in,
  checkOutAt: checkOutAt,
  reason: reason,
  expected: expected,
);

Map<String, dynamic> _existing(String method, {required bool completed}) => {
  'employeeId': 'employee-1',
  'workDate': '2026-10-11',
  'checkInAt': Timestamp.fromDate(_in),
  'method': method,
  'status': completed ? 'completed' : 'working',
  if (completed) 'checkOutAt': Timestamp.fromDate(_out),
};

ManualAttendanceRecord _expected(
  String method, {
  required bool completed,
  int? revision,
  String? checkOutMethod,
}) => ManualAttendanceRecord(
  checkInAt: _in,
  checkOutAt: completed ? _out : null,
  status: completed ? 'completed' : 'working',
  method: method,
  checkOutMethod: checkOutMethod,
  manualRevision: revision,
);

class _FakeStore implements ManualAttendanceStore {
  final users = <String, Map<String, dynamic>>{
    'manager-1': {'role': 'manager', 'status': 'active'},
    'employee-1': {'role': 'employee', 'status': 'active'},
  };
  final attendance = <String, Map<String, dynamic>>{};
  final audit = <String, Map<String, dynamic>>{};
  int commits = 0;
  Object? error;

  @override
  String? get operatorUid => 'manager-1';

  @override
  Object get serverTimestamp =>
      Timestamp.fromDate(DateTime.utc(2026, 10, 11, 12));

  @override
  Future<void> transact(
    Future<void> Function(ManualAttendanceTransaction tx) action,
  ) async {
    if (error != null) throw error!;
    final tx = _FakeTransaction(this);
    await action(tx);
    attendance.addAll(tx.attendanceWrites);
    audit.addAll(tx.auditWrites);
    commits++;
  }
}

class _FakeTransaction implements ManualAttendanceTransaction {
  _FakeTransaction(this.store);
  final _FakeStore store;
  final attendanceWrites = <String, Map<String, dynamic>>{};
  final auditWrites = <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>?> user(String uid) async => store.users[uid];

  @override
  Future<Map<String, dynamic>?> attendance(String id) async =>
      store.attendance[id];

  @override
  Future<Map<String, dynamic>?> audit(String id) async => store.audit[id];

  @override
  void setAttendance(String id, Map<String, dynamic> data) =>
      attendanceWrites[id] = Map.of(data);

  @override
  void createAudit(String id, Map<String, dynamic> data) =>
      auditWrites[id] = Map.of(data);
}
