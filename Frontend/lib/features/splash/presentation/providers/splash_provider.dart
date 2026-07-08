import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';

/// Resolves where the app should navigate once the splash animation completes.
///
/// Order of precedence:
/// 1. First launch (no language chosen) → language selection.
/// 2. [AppConfig.devBypassAuth] on → onboarding (if not done yet) then
///    Discover, skipping Firebase entirely. DEVELOPMENT ONLY.
/// 3. No Firebase session → auth selection.
/// 4. Signed in but not fully verified → resume the verification flow.
/// 5. Signed in and verified → Discover.
class SplashController extends Notifier<void> {
  @override
  void build() {}

  Future<String> resolveInitialRoute() async {
    if (!storageService.hasSelectedLanguage) {
      return RouteNames.language;
    }

    if (AppConfig.devBypassAuth) {
      return storageService.isOnboardingDone
          ? RouteNames.discover
          : RouteNames.onboarding;
    }

    final repo = ref.read(authRepositoryProvider);
    final user = repo.currentUser;
    if (user == null) {
      return RouteNames.authSelection;
    }

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
