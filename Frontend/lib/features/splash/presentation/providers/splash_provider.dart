import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../../../core/network/backend_connectivity_checker.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../authentication/data/services/backend_sync_service.dart';
import '../../../authentication/domain/services/local_auth_session.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../authentication/presentation/utils/post_auth_destination.dart';
import '../../../registration/domain/models/profile_draft.dart';
import '../../../registration/domain/models/profile_flow_mode.dart';
import '../../../registration/presentation/providers/registration_provider.dart';

/// Routes that a screen paused on may be safely resumed into on the next
/// cold start — an Edit Profile session (data rehydrated from the saved
/// draft) or simply the last bottom-nav tab. Anything else (splash, auth
/// screens, OTP entry, ...) depends on ephemeral state that can't survive a
/// process restart, so those are never restored to.
///
/// Both entries below are Edit Profile's screens. Onboarding is deliberately
/// absent: its two steps are resolved from the backend draft by
/// [PostAuthDestination], which is authoritative and cannot be outvoted by
/// a stale local snapshot.
const _restorableRegistrationRoutes = {
  RouteNames.registrationWizard,
  RouteNames.profileReview,
};
const _restorableTabRoutes = {
  RouteNames.discover,
  RouteNames.matches,
  RouteNames.messages,
  RouteNames.premium,
};

/// Resolves where the app should navigate once the splash animation completes.
///
/// Order of precedence:
/// 1. First launch (no language chosen) → language selection.
/// 2. No Firebase session → the sign-up landing screen.
/// 3. Signed in but not fully verified → resume the verification flow.
/// 4. Signed in, verified, and an Edit Profile session (or last tab) was
///    saved before the process died → resume it exactly.
/// 5. Signed in and verified, with no local snapshot to resume → ask
///    [PostAuthDestination]: an unanswered onboarding step reopens that
///    step (from the backend's own copy of the draft), an answered one
///    opens Discover. This is what makes a reinstall, a new device, or a
///    process killed before the debounced save landed still pick up where
///    the user left off instead of dropping them into an empty Discover.
class SplashController extends Notifier<void> {
  @override
  void build() {}

  /// Confirms the backend is actually serving before the app commits to a
  /// route. Every screen behind the splash assumes it can fetch — sending a
  /// user into Discover against a dead backend produces a cascade of failed
  /// requests and empty states instead of one honest, retryable message.
  ///
  /// Never throws: [BackendConnectivityChecker] returns a result for every
  /// failure mode, including offline.
  Future<BackendConnectivityResult> checkServerHealth() =>
      ref.read(serverHealthCheckerProvider).check();

  Future<String> resolveInitialRoute() async {
    if (!storageService.hasSelectedLanguage) {
      return RouteNames.language;
    }

    // Waits for Firebase's own session-restoration signal (the stream's
    // first emission) instead of reading `currentUser` synchronously —
    // Firebase may still be restoring a persisted session at this point,
    // and reading synchronously here is the race that used to send a
    // signed-in user briefly through auth-selection on cold start.
    final user = await ref.read(authStateChangesProvider.future);
    final repo = ref.read(authRepositoryProvider);
    if (user == null) {
      // A mobile login (OTP or password) opens a LocalAuthSession rather
      // than a Firebase one — see that class for why. Without this the
      // router would let the member in but the splash would send them
      // back to the landing screen on the next cold start, so the login
      // would look like it had not stuck.
      if (ref.read(localAuthSessionProvider).isActive) {
        return RouteNames.discover;
      }
      await storageService.clearNavState();
      return RouteNames.registrationLanding;
    }

    // Best-effort: refreshes this session's mirror in the NestJS + Postgres
    // backend on app resume. Never awaited — must not block the splash.
    unawaited(syncUserWithBackend(ref.read(apiClientProvider)));

    // Phone OTP verification is disabled for now, so email is the only thing
    // gated on — and only for an account that actually carries an address.
    //
    // `emailVerified` alone is the wrong question. A phone-only account (every
    // dummy-OTP signup, which mints a phone-provider Firebase user and keeps
    // the member's address on the `users` row instead) has nothing to verify
    // and can never make that flag true, so gating on it sent a member who had
    // just finished signing up to a verify-email screen with no address to
    // resend to and no way past. This is the same rule PostAuthDestination
    // already applies, for the same reason — stated there in the same words.
    final email = user.email;
    if (email != null && email.isNotEmpty) {
      try {
        final emailVerified = await repo.checkEmailVerified();
        if (!emailVerified) return RouteNames.verifyEmail;
      } catch (_) {
        // Network hiccup while refreshing — fall back to the verify-email step
        // rather than blocking the user at the splash.
        return RouteNames.verifyEmail;
      }
    }

    // The local snapshot wins when there is one — it is exact (the very
    // step and field values the user last saw) and needs no network.
    // Otherwise fall back to the backend's view of how far they got.
    return _resolveSavedRoute() ??
        await ref.read(postAuthDestinationProvider).resolve();
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

        // A snapshot is the one way into these screens that doesn't pass
        // through PostAuthDestination, so it needs the same gate. Both of
        // them belong to Edit Profile now, which acts on an
        // already-finalized profile; a CREATE-mode snapshot is either a
        // leftover from the removed 13-step signup wizard or stray
        // hygiene state, and resuming it would drop the user back into a
        // flow that no longer exists. Falling through to null hands the
        // decision to PostAuthDestination, which reads the backend draft
        // and reopens whichever onboarding step is genuinely unanswered.
        if (mode != ProfileFlowMode.edit) return null;

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

final splashControllerProvider = NotifierProvider<SplashController, void>(
  SplashController.new,
);
