import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';

/// Resolves where the app should navigate once the splash animation completes.
///
/// Order of precedence:
/// 1. First launch (no language chosen) → language selection.
/// 2. No Firebase session → auth selection.
/// 3. Signed in but not fully verified → resume the verification flow.
/// 4. Signed in and verified → Home.
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

    try {
      // Reload from Firebase, then derive verification purely from the auth
      // record (no database): phone is verified once it's linked.
      final emailVerified = await repo.checkEmailVerified();
      final phoneVerified = repo.currentAuthUser?.phoneVerified ?? false;

      if (emailVerified && phoneVerified) {
        return RouteNames.home;
      }
      return emailVerified ? RouteNames.verifyPhone : RouteNames.verifyEmail;
    } catch (_) {
      // Network hiccup while refreshing — fall back to the verify-email step
      // rather than blocking the user at the splash.
      return RouteNames.verifyEmail;
    }
  }
}

final splashControllerProvider =
    NotifierProvider<SplashController, void>(SplashController.new);
