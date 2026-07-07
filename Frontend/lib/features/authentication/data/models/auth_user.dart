import 'package:firebase_auth/firebase_auth.dart';

/// Nenjam Matrimony — Local Auth User
///
/// A lightweight, in-memory view of the signed-in Firebase user. There is NO
/// database: Firebase is the authentication provider only. Every field is
/// derived from [FirebaseAuth.currentUser].
///
/// - [username] is carried in the Firebase user's `displayName` until the
///   Node.js backend owns the profile (it will be sent with the Firebase JWT
///   to `POST /api/auth/register`).
/// - [phoneVerified] is true once a phone credential is linked, which Firebase
///   surfaces as a non-null `phoneNumber`.
class AuthUser {
  final String uid;
  final String? username;
  final String? email;
  final String? phone;
  final bool emailVerified;
  final bool phoneVerified;

  const AuthUser({
    required this.uid,
    this.username,
    this.email,
    this.phone,
    this.emailVerified = false,
    this.phoneVerified = false,
  });

  factory AuthUser.fromFirebase(User user) {
    final phone = user.phoneNumber;
    return AuthUser(
      uid: user.uid,
      username: user.displayName,
      email: user.email,
      phone: phone,
      emailVerified: user.emailVerified,
      phoneVerified: phone != null && phone.isNotEmpty,
    );
  }

  /// The gate for entering the app: both channels confirmed.
  bool get isFullyVerified => emailVerified && phoneVerified;
}
