import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../authentication/data/services/backend_sync_service.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';

/// Resolves where the app should navigate once the splash animation completes.
///
/// Order of precedence:
/// 1. First launch (no language chosen) → language selection.
/// 2. No Firebase session → auth selection.
/// 3. Signed in but not fully verified → resume the verification flow.
/// 4. Signed in and verified → Discover.
class SplashController extends Notifier<void> {
  @override
  void build() {}

  Future<String> resolveInitialRoute() async {
    if (!storageService.hasSelectedLanguage) {
      return RouteNames.language;
    }

    final repo = ref.read(authRepositoryProvider);
    final user = repo.currentUser;
    if (user == null) {
      return RouteNames.authSelection;
    }

    // Best-effort: refreshes this session's mirror in the NestJS + Postgres
    // backend on app resume. Never awaited — must not block the splash.
    unawaited(syncUserWithBackend(ref.read(apiClientProvider)));

    try {
      // Phone OTP verification is disabled for now — gate entry on email
      // verification only.
      final emailVerified = await repo.checkEmailVerified();
      return emailVerified ? RouteNames.discover : RouteNames.verifyEmail;
    } catch (_) {
      // Network hiccup while refreshing — fall back to the verify-email step
      // rather than blocking the user at the splash.
      return RouteNames.verifyEmail;
    }
  }
}

final splashControllerProvider =
    NotifierProvider<SplashController, void>(SplashController.new);
