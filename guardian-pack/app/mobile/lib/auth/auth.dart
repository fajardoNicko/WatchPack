import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firebase Auth (email + password) and the parent's profile document.
///
/// users/{uid}: { email, displayName, deviceIds: [..], createdAt }

final authStateProvider = StreamProvider<User?>((_) => FirebaseAuth.instance.authStateChanges());

class UserProfile {
  const UserProfile({required this.uid, required this.email, required this.displayName, required this.deviceIds, this.photo});
  final String uid, email, displayName;
  final List<String> deviceIds;
  final String? photo;                    // base64 data URI, see data/photos.dart

  factory UserProfile.fromDoc(String uid, DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return UserProfile(
      uid: uid,
      email: (m['email'] as String?) ?? '',
      displayName: (m['displayName'] as String?) ?? '',
      deviceIds: [for (final x in (m['deviceIds'] as List?) ?? const []) '$x'],
      photo: m['photo'] as String?,
    );
  }
}

final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots().map((d) => UserProfile.fromDoc(user.uid, d));
});

/// Human-readable reasons for the errors a parent can actually do something about.
String authErrorMessage(Object e) {
  if (e is FirebaseAuthException) {
    return switch (e.code) {
      'invalid-email' => 'That email address doesn\'t look right.',
      'user-disabled' => 'This account has been disabled.',
      'user-not-found' || 'wrong-password' || 'invalid-credential' => 'Email or password is incorrect.',
      'email-already-in-use' => 'An account with this email already exists. Sign in instead.',
      'weak-password' => 'Use a longer password (at least 8 characters).',
      'too-many-requests' => 'Too many attempts. Wait a minute and try again.',
      'network-request-failed' => 'No internet connection.',
      _ => e.message ?? 'Something went wrong (${e.code}).',
    };
  }
  return 'Something went wrong. Please try again.';
}

class AuthActions {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  /// Creates the account and its profile. New accounts start linked to the demo
  /// device so the app isn't empty; "Device linking" in Settings replaces it.
  Future<void> signUp(String email, String password, String displayName) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    final user = cred.user!;
    await user.updateDisplayName(displayName.trim());
    await _db.collection('users').doc(user.uid).set({
      'email': email.trim(),
      'displayName': displayName.trim(),
      'deviceIds': ['wp-demo-ivy'],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendReset(String email) => _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() => _auth.signOut();

  Future<void> linkDevice(String uid, String deviceId) => _db.collection('users').doc(uid).set({
        'deviceIds': FieldValue.arrayUnion([deviceId.trim()]),
      }, SetOptions(merge: true));

  Future<void> unlinkDevice(String uid, String deviceId) => _db.collection('users').doc(uid).update({
        'deviceIds': FieldValue.arrayRemove([deviceId]),
      });

  /// Parent's own avatar (data URI) or null to remove it.
  Future<void> setPhoto(String uid, String? dataUri) => _db.collection('users').doc(uid).set({
        'photo': dataUri ?? FieldValue.delete(),
      }, SetOptions(merge: true));

  Future<void> setDisplayName(String uid, String name) async {
    await FirebaseAuth.instance.currentUser?.updateDisplayName(name.trim());
    await _db.collection('users').doc(uid).set({'displayName': name.trim()}, SetOptions(merge: true));
  }
}

final authActionsProvider = Provider<AuthActions>((_) => AuthActions());
