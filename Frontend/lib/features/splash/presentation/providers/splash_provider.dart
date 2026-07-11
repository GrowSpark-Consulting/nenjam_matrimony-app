import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../authentication/data/services/backend_sync_service.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../registration/domain/models/profile_draft.dart';
import '../../../registration/domain/models/profile_flow_mode.dart';
import '../../../registration/presentation/providers/registration_provider.dart';

/// Routes that a screen paused on may be safely resumed into on the next
/// cold start — a mid-registration/edit session (data rehydrated from the
/// saved draft) or simply the last bottom-nav tab. Anything else (splash,
/// auth screens, OTP entry, ...) depends on ephemeral state that can't
/// survive a process restart, so those are never restored to.
const _restorableRegistrationRoutes = {
  RouteNames.registrationWizard,
  RouteNames.profileReview,
};
const _restorableTabRoutes = {
  RouteNames.discover,
  RouteNames.matches,
  RouteNames.messages,
  RouteNames.astro,
  RouteNames.premium,
};

/// Resolves where the app should navigate once the splash animation completes.
///
/// Order of precedence:
/// 1. First launch (no language chosen) → language selection.
/// 2. No Firebase session → auth selection.
/// 3. Signed in but not fully verified → resume the verification flow.
/// 4. Signed in, verified, and a mid-registration/edit session (or last
///    tab) was saved before the process died → resume it exactly.
/// 5. Signed in and verified → Discover.
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
      await storageService.clearNavState();
      return RouteNames.authSelection;
    }

    // Best-effort: refreshes this session's mirror in the NestJS + Postgres
    // backend on app resume. Never awaited — must not block the splash.
    unawaited(syncUserWithBackend(ref.read(apiClientProvider)));

    try {
      // Phone OTP verification is disabled for now — gate entry on email
      // verification only.
      final emailVerified = await repo.checkEmailVerified();
      if (!emailVerified) return RouteNames.verifyEmail;
    } catch (_) {
      // Network hiccup while refreshing — fall back to the verify-email step
      // rather than blocking the user at the splash.
      return RouteNames.verifyEmail;
    }

    return _resolveSavedRoute() ?? RouteNames.discover;
  }

  /// Resumes whatever screen was saved on the last [AppLifecycleState.paused]
  /// (see StorageService.saveNavState), if any. Returns null — falling back
  /// to Discover — when nothing was saved or it can't be rehydrated safely.
  String? _resolveSavedRoute() {
    final savedRoute = storageService.lastRoute;
    if (savedRoute == null) return null;

    if (_restorableRegistrationRoutes.contains(savedRoute)) {
      final draftJson = storageService.savedProfileDraftJson;
      final modeStr = storageService.savedProfileFlowMode;
      if (draftJson == null || modeStr == null) return null;
      try {
        final draft = ProfileDraft.fromJson(
          jsonDecode(draftJson) as Map<String, dynamic>,
        );
        final step = storageService.savedRegistrationStep ?? draft.currentStep;
        final mode = ProfileFlowMode.values.byName(modeStr);
        ref
            .read(registrationProvider.notifier)
            .restore(draft.copyWith(currentStep: step), mode);
        return savedRoute;
      } catch (_) {
        return null;
      }
    }

    if (_restorableTabRoutes.contains(savedRoute)) {
      return savedRoute;
    }

    return null;
  }
}

final splashControllerProvider =
    NotifierProvider<SplashController, void>(SplashController.new);
