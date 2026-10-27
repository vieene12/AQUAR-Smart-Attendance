import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smart_attendance/features/admin/accounts/domain/account_record.dart';

class AccountRepository {
  AccountRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<List<AccountRecord>> getAccounts() async {
    final snapshot = await _firestore
        .collection('users')
        .get(const GetOptions(source: Source.server));

    return [
      for (final document in snapshot.docs)
        AccountRecord.fromFirestore(document.id, document.data()),
    ];
  }

  Future<void> updateAccount({
    required String uid,
    required String fullName,
    required int hourlyRate,
    String? employeeCode,
    String? position,
    String? shiftStart,
    String? shiftEnd,
    String? managerUid,
  }) {
    return _firestore.collection('users').doc(uid).update({
      'fullName': fullName,
      'hourlyRate': hourlyRate,
      'employeeCode': employeeCode ?? FieldValue.delete(),
      'position': position ?? FieldValue.delete(),
      'shiftStart': shiftStart ?? FieldValue.delete(),
      'shiftEnd': shiftEnd ?? FieldValue.delete(),
      'managerUid': managerUid ?? FieldValue.delete(),
    });
  }

  Future<void> setAccountLocked({required String uid, required bool locked}) {
    return _firestore.collection('users').doc(uid).update({
      'status': locked ? 'locked' : 'active',
    });
  }
}
