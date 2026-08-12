import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../data/models/auth_user.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../data/services/auth_token_service.dart';
import '../../data/services/firebase_auth_service.dart';
import '../../data/services/google_auth_service.dart';

/// Nenjam Matrimony — Authentication Providers
///
/// Dependency-injection graph for the auth feature. Firebase is the auth
/// provider only — there is no database dependency here.

// ─── SDK singleton ────────────────────────────────────────────────────
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

/// google_sign_in 7.x is a singleton — there is no constructible instance.
/// Exposed as a provider purely so tests can override it.
final googleSignInProvider = Provider<GoogleSignIn>(
  (ref) => GoogleSignIn.instance,
);

// ─── Services ─────────────────────────────────────────────────────────
final firebaseAuthServiceProvider = Provider<FirebaseAuthService>(
  (ref) => FirebaseAuthService(ref.watch(firebaseAuthProvider)),
);

final googleAuthServiceProvider = Provider<GoogleAuthService>(
  (ref) => GoogleAuthService(
    ref.watch(firebaseAuthProvider),
    ref.watch(googleSignInProvider),
  ),
);

/// Firebase ID token (JWT) provider for future Node.js backend calls.
final authTokenServiceProvider = Provider<AuthTokenService>(
  (ref) => AuthTokenService(ref.watch(firebaseAuthProvider)),
);

// ─── Repository ───────────────────────────────────────────────────────
final authRepositoryProvider = Provider<FirebaseAuthRepository>(
  (ref) => FirebaseAuthRepository(
    auth: ref.watch(firebaseAuthServiceProvider),
    google: ref.watch(googleAuthServiceProvider),
  ),
);

// ─── Reactive session state ───────────────────────────────────────────

/// Emits the Firebase user (or `null`) as auth state changes. Drives splash
/// routing and logout redirects.
final authStateChangesProvider = StreamProvider<User?>(
  (ref) => ref.watch(firebaseAuthServiceProvider).authStateChanges(),
);

/// The current signed-in user as a local [AuthUser], rebuilt on auth changes.
final currentAuthUserProvider = Provider<AuthUser?>((ref) {
  final async = ref.watch(authStateChangesProvider);
  final user = async.valueOrNull;
  return user == null ? null : AuthUser.fromFirebase(user);
});
