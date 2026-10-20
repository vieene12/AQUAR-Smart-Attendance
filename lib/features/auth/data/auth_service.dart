import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';

enum UserProfileFailure { missing, locked, invalidStatus, invalidRole }

class UserProfileException implements Exception {
  const UserProfileException(this.failure);

  final UserProfileFailure failure;
}

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    try {
      final user = credential.user;
      if (user == null) {
        throw const UserProfileException(UserProfileFailure.missing);
      }

      return await _loadActiveProfile(user);
    } catch (_) {
      await _auth.signOut();
      rethrow;
    }
  }

  Future<UserProfile?> restoreSession() async {
    final user = await _auth.authStateChanges().first;
    if (user == null) return null;

    try {
      // Firebase Auth persists the session on Android. Reload checks whether
      // the account was disabled or deleted since its last use.
      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null) {
        await _auth.signOut();
        return null;
      }
      return await _loadActiveProfile(refreshedUser);
    } on UserProfileException {
      await _auth.signOut();
      rethrow;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'user-disabled' || error.code == 'user-not-found') {
        await _auth.signOut();
      }
      rethrow;
    }
  }

  Future<void> signOut() => _auth.signOut();

  Future<UserProfile> _loadActiveProfile(User user) async {
    final profile = await _firestore
        .collection('users')
        .doc(user.uid)
        .get(const GetOptions(source: Source.server));

    if (!profile.exists) {
      throw const UserProfileException(UserProfileFailure.missing);
    }

    final data = profile.data();
    final status = data?['status'];
    if (status == 'locked') {
      throw const UserProfileException(UserProfileFailure.locked);
    }
    if (status != 'active') {
      throw const UserProfileException(UserProfileFailure.invalidStatus);
    }

    final role = UserRole.fromFirestore(data?['role']);
    if (role == null) {
      throw const UserProfileException(UserProfileFailure.invalidRole);
    }

    final name =
        _nonEmptyText(data?['name']) ??
        _nonEmptyText(data?['fullName']) ??
        _nonEmptyText(user.displayName) ??
        _nonEmptyText(user.email) ??
        'Người dùng';

    return UserProfile(uid: user.uid, displayName: name, role: role);
  }

  String? _nonEmptyText(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}
