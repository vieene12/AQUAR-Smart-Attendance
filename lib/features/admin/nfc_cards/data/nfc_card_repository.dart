import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smart_attendance/features/admin/accounts/domain/account_record.dart';

class EmployeeNfcCard {
  const EmployeeNfcCard({required this.account, this.cardUid});

  final AccountRecord account;
  final String? cardUid;
}

class NfcCardConflict implements Exception {
  const NfcCardConflict();
}

class NfcCardAlreadyRegistered implements Exception {
  const NfcCardAlreadyRegistered();
}

class NfcEmployeeUnavailable implements Exception {
  const NfcEmployeeUnavailable();
}

String normalizeCardUid(String value) {
  final uid = value.trim().toUpperCase();
  if (!RegExp(r'^([0-9A-F]{2}){1,32}$').hasMatch(uid)) {
    throw const FormatException('UID thẻ không hợp lệ.');
  }
  return uid;
}

abstract class NfcCardTransaction {
  Future<AccountRecord?> employee(String employeeUid);
  Future<String?> employeeCard(String employeeUid);
  Future<String?> cardOwner(String cardUid);
  void putCard(String cardUid, String employeeUid);
  void deleteCard(String cardUid);
  void putEmployeeCard(String employeeUid, String cardUid);
  void deleteEmployeeCard(String employeeUid);
}

abstract class NfcCardStore {
  Future<List<EmployeeNfcCard>> loadEmployees();
  Future<void> transact(Future<void> Function(NfcCardTransaction tx) action);
}

class NfcCardRepository {
  const NfcCardRepository(this.store);

  final NfcCardStore store;

  Future<List<EmployeeNfcCard>> loadEmployees() => store.loadEmployees();

  Future<void> register(String employeeUid, String rawCardUid) async {
    final cardUid = normalizeCardUid(rawCardUid);
    await store.transact((tx) async {
      final employee = await tx.employee(employeeUid);
      if (employee?.role != 'employee' || employee?.status != 'active') {
        throw const NfcEmployeeUnavailable();
      }
      final previous = await tx.employeeCard(employeeUid);
      final owner = await tx.cardOwner(cardUid);
      if (previous == cardUid) throw const NfcCardAlreadyRegistered();
      if (owner != null) throw const NfcCardConflict();
      if (previous != null) tx.deleteCard(previous);
      tx.putCard(cardUid, employeeUid);
      tx.putEmployeeCard(employeeUid, cardUid);
    });
  }

  Future<void> revoke(String employeeUid) async {
    await store.transact((tx) async {
      final previous = await tx.employeeCard(employeeUid);
      if (previous == null) return;
      tx.deleteCard(previous);
      tx.deleteEmployeeCard(employeeUid);
    });
  }
}

class FirestoreNfcCardStore implements NfcCardStore {
  FirestoreNfcCardStore({FirebaseFirestore? firestore})
    : _providedFirestore = firestore;

  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;

  @override
  Future<List<EmployeeNfcCard>> loadEmployees() async {
    final users = await _firestore
        .collection('users')
        .get(const GetOptions(source: Source.server));
    final links = await _firestore
        .collection('nfc_employee_cards')
        .get(const GetOptions(source: Source.server));
    final cardByEmployee = {
      for (final link in links.docs) link.id: link.data()['cardUid'] as String?,
    };
    final employees = [
      for (final user in users.docs)
        if (user.data()['role'] == 'employee')
          EmployeeNfcCard(
            account: AccountRecord.fromFirestore(user.id, user.data()),
            cardUid: cardByEmployee[user.id],
          ),
    ];
    employees.sort(
      (a, b) => (a.account.name ?? a.account.email ?? a.account.uid).compareTo(
        b.account.name ?? b.account.email ?? b.account.uid,
      ),
    );
    return employees;
  }

  @override
  Future<void> transact(Future<void> Function(NfcCardTransaction tx) action) =>
      _firestore.runTransaction((transaction) async {
        await action(_FirestoreNfcCardTransaction(_firestore, transaction));
      });
}

class _FirestoreNfcCardTransaction implements NfcCardTransaction {
  _FirestoreNfcCardTransaction(this.firestore, this.transaction);

  final FirebaseFirestore firestore;
  final Transaction transaction;

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      firestore.collection('users').doc(uid);
  DocumentReference<Map<String, dynamic>> _link(String uid) =>
      firestore.collection('nfc_employee_cards').doc(uid);
  DocumentReference<Map<String, dynamic>> _card(String uid) =>
      firestore.collection('nfc_cards').doc(uid);

  @override
  Future<AccountRecord?> employee(String employeeUid) async {
    final snapshot = await transaction.get(_user(employeeUid));
    final data = snapshot.data();
    return data == null ? null : AccountRecord.fromFirestore(employeeUid, data);
  }

  @override
  Future<String?> employeeCard(String employeeUid) async {
    final snapshot = await transaction.get(_link(employeeUid));
    return snapshot.data()?['cardUid'] as String?;
  }

  @override
  Future<String?> cardOwner(String cardUid) async {
    final snapshot = await transaction.get(_card(cardUid));
    if (!snapshot.exists) return null;
    return snapshot.data()?['employeeUid'] as String? ?? '';
  }

  @override
  void putCard(String cardUid, String employeeUid) => transaction.set(
    _card(cardUid),
    {'employeeUid': employeeUid, 'createdAt': FieldValue.serverTimestamp()},
  );

  @override
  void deleteCard(String cardUid) => transaction.delete(_card(cardUid));

  @override
  void putEmployeeCard(String employeeUid, String cardUid) => transaction.set(
    _link(employeeUid),
    {'cardUid': cardUid, 'updatedAt': FieldValue.serverTimestamp()},
  );

  @override
  void deleteEmployeeCard(String employeeUid) =>
      transaction.delete(_link(employeeUid));
}
