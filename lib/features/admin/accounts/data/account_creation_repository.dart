import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

enum AccountCreationFailure { checkAccount, cleanupFailed, adminSessionChanged }

class AccountCreationException implements Exception {
  const AccountCreationException(this.failure);

  final AccountCreationFailure failure;
}

class AccountCreationRepository {
  AccountCreationRepository({
    FirebaseAuth? adminAuth,
    FirebaseFirestore? firestore,
  }) : _adminAuth = adminAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _adminAuth;
  final FirebaseFirestore _firestore;

  Future<String> createAccount({
    required String fullName,
    required String email,
    required String password,
    required String role,
    required int hourlyRate,
  }) async {
    final adminUid = _adminAuth.currentUser?.uid;
    if (adminUid == null) {
      throw const AccountCreationException(
        AccountCreationFailure.adminSessionChanged,
      );
    }

    final app = await Firebase.initializeApp(
      name: 'account_creation_${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    final secondaryAuth = FirebaseAuth.instanceFor(app: app);

    try {
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final newUser = credential.user;
      if (newUser == null) {
        throw const AccountCreationException(
          AccountCreationFailure.checkAccount,
        );
      }

      final profile = <String, Object>{
        'fullName': fullName,
        'email': email,
        'role': role,
        'status': 'active',
        'hourlyRate': hourlyRate,
      };
      final document = _firestore.collection('users').doc(newUser.uid);

      if (_adminAuth.currentUser?.uid != adminUid) {
        await _deleteCreatedUser(newUser);
        throw const AccountCreationException(
          AccountCreationFailure.adminSessionChanged,
        );
      }

      try {
        await document.set(profile);
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied') {
          await _deleteCreatedUser(newUser);
          rethrow;
        }

        // A transport error may arrive after the server committed the write.
        // Check the server before deciding whether this Auth user is orphaned.
        try {
          final saved = await document.get(
            const GetOptions(source: Source.server),
          );
          if (saved.exists) {
            if (_matchesProfile(saved.data(), profile)) return newUser.uid;
            throw const AccountCreationException(
              AccountCreationFailure.checkAccount,
            );
          }
        } on FirebaseException {
          throw const AccountCreationException(
            AccountCreationFailure.checkAccount,
          );
        }

        await _deleteCreatedUser(newUser);
        rethrow;
      }

      return newUser.uid;
    } finally {
      try {
        await secondaryAuth.signOut();
      } catch (_) {
        // Deleting the temporary app is still attempted below.
      }
      try {
        await app.delete();
      } catch (_) {
        // Do not hide the result of account creation or rollback.
      }
    }
  }

  bool _matchesProfile(
    Map<String, dynamic>? saved,
    Map<String, Object> expected,
  ) {
    if (saved == null) return false;
    for (final entry in expected.entries) {
      if (saved[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<void> _deleteCreatedUser(User user) async {
    try {
      await user.delete();
    } on FirebaseAuthException {
      throw const AccountCreationException(
        AccountCreationFailure.cleanupFailed,
      );
    }
  }
}
