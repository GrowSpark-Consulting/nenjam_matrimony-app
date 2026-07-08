import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/config/dev_user.dart';
import '../../data/models/auth_user.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../data/services/auth_token_service.dart';
import '../../data/services/firebase_auth_service.dart';

/// Nenjam Matrimony — Authentication Providers
///
/// Dependency-injection graph for the auth feature. Firebase is the auth
/// provider only — there is no database dependency here.

// ─── SDK singleton ────────────────────────────────────────────────────
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

// ─── Services ─────────────────────────────────────────────────────────
final firebaseAuthServiceProvider = Provider<FirebaseAuthService>(
  (ref) => FirebaseAuthService(ref.watch(firebaseAuthProvider)),
);

/// Firebase ID token (JWT) provider for future Node.js backend calls.
final authTokenServiceProvider = Provider<AuthTokenService>(
  (ref) => AuthTokenService(ref.watch(firebaseAuthProvider)),
);

// ─── Repository ───────────────────────────────────────────────────────
final authRepositoryProvider = Provider<FirebaseAuthRepository>(
  (ref) => FirebaseAuthRepository(
    auth: ref.watch(firebaseAuthServiceProvider),
  ),
);

// ─── Reactive session state ───────────────────────────────────────────

/// Emits the Firebase user (or `null`) as auth state changes. Drives splash
/// routing and logout redirects.
final authStateChangesProvider = StreamProvider<User?>(
  (ref) => ref.watch(firebaseAuthServiceProvider).authStateChanges(),
);

/// The current signed-in user as a local [AuthUser], rebuilt on auth changes.
///
/// DEVELOPMENT ONLY: while [AppConfig.devBypassAuth] is on, this hands out a
/// synthetic [DevUser]-backed session instead of reading Firebase, so any
/// screen that already depends on "the current user" keeps working without
/// a real login. Production (flag off) is untouched.
final currentAuthUserProvider = Provider<AuthUser?>((ref) {
  if (AppConfig.devBypassAuth) {
    return const AuthUser(
      uid: DevUser.id,
      username: DevUser.name,
      email: 'dev@nenjam.local',
      emailVerified: true,
      phoneVerified: true,
    );
  }

  final async = ref.watch(authStateChangesProvider);
  final user = async.valueOrNull;
  return user == null ? null : AuthUser.fromFirebase(user);
});
