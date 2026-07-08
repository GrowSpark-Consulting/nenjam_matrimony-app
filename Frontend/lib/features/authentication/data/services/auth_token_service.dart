import 'package:firebase_auth/firebase_auth.dart';

/// Nenjam Matrimony — Firebase JWT / ID Token Service
///
/// Bridges Firebase Authentication to the future Node.js backend. The Firebase
/// ID token is a signed JWT the backend verifies with the Firebase Admin SDK
/// before creating/reading the PostgreSQL user record.
///
/// Usage (future):
/// ```dart
/// final token = await tokenService.getFirebaseToken();
/// dio.options.headers['Authorization'] = 'Bearer $token';
/// ```
class AuthTokenService {
  AuthTokenService(this._auth);

  final FirebaseAuth _auth;

  /// Returns the current user's Firebase ID token (JWT), or `null` if signed
  /// out. Firebase auto-refreshes tokens; pass [forceRefresh] to mint a fresh
  /// one (e.g. after custom claims change).
  Future<String?> getFirebaseToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return user.getIdToken(forceRefresh);
  }

  /// Convenience for the `Authorization` header value, or `null` if signed out.
  Future<String?> getBearerHeader() async {
    final token = await getFirebaseToken();
    return token == null ? null : 'Bearer $token';
  }
}
