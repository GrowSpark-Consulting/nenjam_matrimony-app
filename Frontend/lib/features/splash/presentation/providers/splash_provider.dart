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
import '../../../referral/presentation/providers/referral_providers.dart';
import '../../../authentication/presentation/utils/post_auth_destination.dart';
import '../../../registration/domain/models/profile_draft.dart';
import '../../../registration/domain/models/profile_flow_mode.dart';
import '../../../registration/presentation/providers/registration_provider.dart';
import '../../../registration/presentation/utils/onboarding_draft_gate.dart';

/// Routes that a screen paused on may be safely resumed into on the next
/// cold start via [SplashController._resolveSavedRoute] — an Edit Profile
/// session (data rehydrated from the saved draft) or simply the last
/// bottom-nav tab. Anything else (splash, auth screens, OTP entry, ...)
/// depends on ephemeral state that can't survive a process restart, so those
/// are never restored through this particular set.
///
/// Both entries below are profile-editing screens, and deliberately: an EDIT
/// snapshot is a signed-in member's own screen state and this set exists to
/// resume it exactly, unquestioned. Onboarding is absent from it for the
/// opposite reason — a CREATE-mode snapshot is a draft still being answered,
/// which is why it takes its own gate chain instead: [PostAuthDestination]
/// for a signed-in member (session exists, backend's copy of the draft is
/// authoritative), or [SplashController._resolvePreSessionOnboarding] for
/// one who has not signed in yet at all (no backend copy exists — the local
/// snapshot is the only one there is).
const _restorableRegistrationRoutes = {
  RouteNames.editProfile,
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
/// 2. No session of any kind, but a local onboarding draft has an unanswered
///    step → resume that step (see [_resolvePreSessionOnboarding]). This is
///    the only path a member mid-onboarding has: the backend has no draft
///    for them yet, because every onboarding step before Verify Mobile
///    persists locally only.
/// 3. No session, and nothing local is worth resuming → the sign-up landing
///    screen.
/// 4. Signed in but not fully verified → resume the verification flow.
/// 5. Signed in, verified, and an Edit Profile session (or last tab) was
///    saved before the process died → resume it exactly.
/// 6. Signed in and verified, with no local snapshot to resume → ask
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
      // No session at all, either kind — but that no longer means nothing
      // is worth resuming. Onboarding runs entirely before either kind of
      // session exists (see RegistrationNotifier's onboarding-persistence
      // comment), so a member who filled in several steps and then had the
      // process killed — an Android background reclaim, not a deliberate
      // exit — has no session to prove it, only the local snapshot
      // RegistrationNotifier._snapshot wrote after every step. Losing that
      // snapshot here used to be indistinguishable from the member never
      // having started, which is the bug this resumes instead of erasing.
      return _resolvePreSessionOnboarding() ??
          await _clearAndLandOnRegistration();
    }

    // Best-effort: refreshes this session's mirror in the NestJS + Postgres
    // backend on app resume. Never awaited — must not block the splash.
    unawaited(syncUserWithBackend(ref.read(apiClientProvider)));

    // A referral code entered during signup that has not attached yet — the
    // app was killed in between, or the last attempt failed and is due a
    // retry. Silent and never awaited: the splash must not wait on it, and
    // the controller itself decides whether there is anything to send.
    unawaited(ref.read(referralAttachmentControllerProvider).attachPending());

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

  /// Resumes an unfinished onboarding draft when there is no session of any
  /// kind to ask [PostAuthDestination] instead — the pre-session half of
  /// onboarding (Profile For through About) has nowhere else its answers are
  /// held; see [RegistrationNotifier._snapshot].
  ///
  /// Returns null when there is nothing safe to resume: no snapshot was
  /// written, it fails to decode (a corrupted or foreign-shaped value —
  /// treated as absent, never as a crash), or — the one case a draft alone
  /// cannot answer — every draft-backed step is already filled in. That last
  /// case is reached only when the member reached the Email + Mobile /
  /// Verify Mobile steps (which write no draft field of their own) and the
  /// process died there; [firstUnansweredOnboardingStep] has no field to gate
  /// on for either, so it would otherwise return null and this method would
  /// have to guess between two screens it cannot tell apart. Falling through
  /// to the landing screen is correct either way: nothing here ever mints a
  /// session, so this can only ever resume back into onboarding, never into
  /// the app itself — a member this far along answers Email + Mobile again
  /// from a clean start, at worst re-asking two fields already on this
  /// device ([StorageService.pendingEmail]/[pendingPhone], left untouched by
  /// this whole path).
  String? _resolvePreSessionOnboarding() {
    final draftJson = storageService.savedProfileDraftJson;
    if (draftJson == null) return null;
    try {
      final draft = ProfileDraft.fromJson(
        jsonDecode(draftJson) as Map<String, dynamic>,
      );
      final nextStep = firstUnansweredOnboardingStep(draft);
      if (nextStep == null) return null;

      // Rehydrates the same way PostAuthDestination.resolve() does for the
      // backend-draft case, so the onboarding screen reopens on the answers
      // already given rather than blank.
      ref
          .read(registrationProvider.notifier)
          .restore(draft, ProfileFlowMode.create);
      return nextStep;
    } catch (_) {
      return null;
    }
  }

  /// The pre-fix fallback: nothing worth resuming, so drop whatever local
  /// onboarding/nav bookkeeping exists and send the member to sign up fresh.
  /// Never reached when [_resolvePreSessionOnboarding] found an unfinished
  /// draft — only when there genuinely is none, or it could not be read.
  Future<String> _clearAndLandOnRegistration() async {
    await storageService.clearNavState();
    return RouteNames.registrationLanding;
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
