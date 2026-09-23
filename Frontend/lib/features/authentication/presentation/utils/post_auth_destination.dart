import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/utils/auth_trace.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../domain/services/local_auth_session.dart';
import '../../../registration/domain/models/profile_draft.dart';
import '../../../registration/domain/models/profile_flow_mode.dart';
import '../../../registration/presentation/providers/registration_provider.dart';
import '../../../registration/presentation/utils/onboarding_draft_gate.dart';
import '../../../verification/presentation/providers/face_verification_providers.dart';
import '../providers/auth_providers.dart';

/// The draft lookup is a routing decision, not a screen the user is waiting
/// on with a spinner they can cancel — a stalled request must not hold the
/// splash (or a just-tapped sign-in button) open indefinitely. Past this,
/// [PostAuthDestination] falls back rather than waits.
const Duration _draftLookupTimeout = Duration(seconds: 6);

/// A Firebase account whose creation and last-sign-in timestamps are this
/// close together has never signed in before — this *is* the sign-up.
/// Used only to pick a safe fallback when the backend can't be reached.
const Duration _brandNewAccountWindow = Duration(minutes: 2);

/// Where an authenticated user belongs, in one place.
///
/// Every path that completes authentication asks this the same question:
/// email/password login, Google sign-in, phone OTP, and the splash's cold
/// start. Before this existed each of them hardcoded its own answer
/// ("Discover" for login, "registration wizard" for OTP), which is why a
/// half-registered user could land in Discover with no profile and a
/// brand-new Google user never saw the registration flow at all.
///
/// Onboarding is a chain of screens, and this resolves to the **first** of
/// them the member has not finished — so a session killed halfway resumes exactly
/// where it stopped, and a finished one never sees any of them again:
///
/// 1. Not signed in → the sign-up landing screen.
/// 2. Has an email address that isn't verified yet → the verify-email step.
/// 3. No "profile is for" choice, or no gender →
///    [RouteNames.createProfileFor]. Those two are one screen.
/// 4. Name or date of birth missing → [RouteNames.onboardingNameDob].
/// 5. Religion, community or "living in" missing →
///    [RouteNames.onboardingReligion]. Caste and mother tongue are
///    deliberately absent — onboarding does not collect them at all.
/// 6. An unfinished signup with no email or mobile on record →
///    [RouteNames.onboardingContact]. Only an unfinished signup: this
///    step's answers are stored nowhere the backend can see, so asking
///    it of an established account is unanswerable, and doing so was
///    the bug that sent every login into onboarding. The gate itself
///    carries the full account.
/// 7. State or city missing → [RouteNames.profileBasics].
/// 8. Otherwise → the remaining steps in order, then Discover.
///
/// Each gate tests exactly the fields its screen writes — the same
/// `isComplete` rules the screens enforce, from
/// `registration/domain/models/onboarding_forms.dart` — so answering a step
/// is always what gets a member past it, and no gate can loop. Optional
/// fields (sub-community, photos) are deliberately ungated for the same
/// reason: a gate on a field its screen does not require is a gate a member
/// cannot answer their way past. The
/// Email + Mobile step is the one whose answers the backend never sees,
/// which is why it alone is scoped to an unfinished signup rather than
/// asked of every session.
///
/// There is deliberately no branch into [RouteNames.editProfile] or its
/// section pages. Those belong to Edit Profile: a member whose profile is merely
/// *unfinished* belongs in the app, where Profile Strength invites them to
/// fill in the rest, not back at the start of a 13-step form. For the same
/// reason the old `isComplete` shortcut is gone — a draft marked complete by
/// the pre-onboarding wizard says nothing about whether these four steps
/// were answered, and trusting it would wave a half-onboarded member
/// straight through.
///
/// Never throws. A backend that can't be reached falls back to Discover for
/// an established account (which is where it always used to send them) and
/// to the "profile is for" step for an account created moments ago — that
/// user has no profile to show, so Discover would be an empty dead end.
class PostAuthDestination {
  PostAuthDestination(this._ref);

  final Ref _ref;

  Future<String> resolve() async {
    final user = _ref.read(firebaseAuthServiceProvider).currentUser;

    // DEBUG ONLY — a dev session (dummy OTP, no Firebase account) is a real
    // session as far as the backend is concerned, so it must not be sent to
    // the landing screen. It has no Firebase user to read an email or a
    // verified phone from, so the two account-derived gates below cannot be
    // asked; the draft-derived ones still apply in full, and the finalized
    // profile check does the rest. Compiled out of release.
    if (user == null && hasLocalAuthSession()) {
      return _resolveFromDraftOnly();
    }

    if (user == null) {
      AuthTrace.profileState('NEW (no session)');
      AuthTrace.destination(RouteNames.registrationLanding);
      return RouteNames.registrationLanding;
    }

    // Phone-only accounts have no address to verify, so this gate must key
    // on "has an email that is unverified", not on `emailVerified` alone —
    // otherwise a phone signup loops forever on a verify-email screen with
    // nothing to resend to.
    final email = user.email;
    if (email != null && email.isNotEmpty && !user.emailVerified) {
      AuthTrace.destination(RouteNames.verifyEmail);
      return RouteNames.verifyEmail;
    }

    // An existing member goes straight in.
    //
    // The onboarding gates below describe a REGISTRATION path: each asks
    // whether a particular signup step was answered. A member who registered
    // before those steps existed has answered none of them, so every gate
    // fails and login drops them back into signup — the "Account already
    // exists" they then hit is the Email + Mobile step's duplicate check
    // refusing the number their own account already owns. The gates are right
    // for someone still registering and wrong for someone who has finished.
    //
    // A finalized `user_profiles` row is what separates the two: the backend
    // only writes one once registration genuinely produced a profile, and it
    // is what Discover, matching and Near Me all read. Asking for it costs one
    // request and replaces the draft fetch below for exactly the members who
    // would otherwise be sent backwards.
    if (await _hasFinalizedProfile()) {
      final gated = await _faceVerificationGate();
      if (gated != null) return gated;
      AuthTrace.profileState('COMPLETED');
      AuthTrace.destination(RouteNames.discover);
      return RouteNames.discover;
    }

    final Map<String, dynamic> draft;
    try {
      draft = await _ref
          .read(registrationRepositoryProvider)
          .getDraft()
          .timeout(_draftLookupTimeout);
    } catch (_) {
      final fallback = _isBrandNewAccount(user.metadata.creationTime,
              user.metadata.lastSignInTime)
          ? RouteNames.createProfileFor
          : RouteNames.discover;
      AuthTrace.profileState('UNKNOWN (draft lookup failed)');
      AuthTrace.destination(fallback);
      return fallback;
    }

    final restored = ProfileDraft.fromJson(draft);

    // Rehydrating first is what lets each onboarding screen reopen on the
    // answers already given, rather than blank, when a member resumes on a
    // new device or after a reinstall.
    _ref
        .read(registrationProvider.notifier)
        .restore(restored, ProfileFlowMode.create);

    // Steps 1-3 — Profile For + Gender, Name + DOB, Religion. Walked by the
    // shared draft gate rather than written out again here: one definition of
    // each rule, and one definition of their order, for this path and the
    // dev-session one below alike. The chain stops at the first unanswered
    // step, so a route from it that is one of these three is that step.
    final draftStep = firstUnansweredOnboardingStep(restored);
    if (draftStep == RouteNames.createProfileFor) {
      AuthTrace.profileState('NEW');
      AuthTrace.destination(RouteNames.createProfileFor);
      return RouteNames.createProfileFor;
    }
    AuthTrace.profileState('PARTIAL');
    if (draftStep == RouteNames.onboardingNameDob ||
        draftStep == RouteNames.onboardingReligion) {
      AuthTrace.destination(draftStep!);
      return draftStep;
    }

    // Step 3 — Email + Mobile. **A signup gate, not a session gate.**
    //
    // Every other step is answered into the draft, which the backend keeps,
    // so any device can read back whether it was done. This one is not:
    // OnboardingContactPage stores `pendingEmail`/`pendingPhone` in local
    // storage and — as its own doc comment says — makes no Firebase Phone
    // Auth call, and the verify-mobile step that follows makes none either.
    // Nothing in the app has linked a phone credential since the mock OTP
    // replaced real phone auth, so `user.phoneNumber` is empty for *every*
    // account this app can create.
    //
    // Gating a session on it therefore sent every signed-in member here on
    // every login and every cold start, with no way out: submitting the
    // screen cannot set the field the gate read. That was the login bug.
    //
    // So it is asked only of a signup that is still unfinished. A member
    // whose draft already answers the later steps has been through this one
    // (the flow is linear), and an established account has contact details
    // by construction — a login is not the place to re-collect them. What
    // stays gated is exactly the case the step exists for: a half-finished
    // signup, on the device it was started on, that never reached the end.
    if (!allOnboardingStepsAnswered(restored) && !_onboardingCompleted()) {
      // `pendingEmail`/`pendingPhone` cover the window between answering
      // this step and the account carrying the values: Firebase attaches an
      // address only once the member opens the link, and never attaches the
      // number at all.
      final hasEmail =
          (user.email ?? '').isNotEmpty || _pendingEmail().isNotEmpty;
      final hasMobile =
          (user.phoneNumber ?? '').isNotEmpty || _pendingPhone().isNotEmpty;
      if (!hasEmail || !hasMobile) {
        AuthTrace.destination(RouteNames.onboardingContact);
        return RouteNames.onboardingContact;
      }
    }

    // Steps 5-10 — state/city, marital, education, income, about. The same
    // chain again, and the same [draftStep] answer: the three gates it could
    // have stopped at before this point have already been handled above, so
    // anything left is one of these. Step 9 (photos) is deliberately absent
    // from it — optional, and a member who chose "Add Photos Later" must not
    // be sent back every launch.
    if (draftStep != null) {
      AuthTrace.destination(draftStep);
      return draftStep;
    }

    // Every step that leaves a durable answer has one. Onboarding is done.
    final gated = await _faceVerificationGate();
    if (gated != null) return gated;
    AuthTrace.profileState('COMPLETED');
    AuthTrace.destination(RouteNames.discover);
    return RouteNames.discover;
  }

  /// DEBUG ONLY — the same gates as [resolve], minus the two that read the
  /// Firebase account.
  ///
  /// A dev session has no Firebase user, so "is this email verified?" and
  /// "is a mobile number linked?" have no answer here. Skipping them is
  /// correct rather than lenient: the dummy OTP the member just passed *is*
  /// this build's mobile verification, and there is no email address on a
  /// dev session to verify. Every gate that reads the draft — which is every
  /// gate that guards profile data — still applies exactly as it does for a
  /// real session.
  Future<String> _resolveFromDraftOnly() async {
    if (await _hasFinalizedProfile()) {
      return await _faceVerificationGate() ?? RouteNames.discover;
    }

    final Map<String, dynamic> draft;
    try {
      draft = await _ref
          .read(registrationRepositoryProvider)
          .getDraft()
          .timeout(_draftLookupTimeout);
    } catch (_) {
      // Unlike the real path there is no account age to consult, and a dev
      // session that cannot reach the backend has nothing to show in the app.
      return RouteNames.createProfileFor;
    }

    final restored = ProfileDraft.fromJson(draft);
    _ref
        .read(registrationProvider.notifier)
        .restore(restored, ProfileFlowMode.create);

    // See firstUnansweredOnboardingStep's doc comment: this is the same
    // draft-backed gate chain resolve() walks, shared rather than
    // reimplemented so the two paths cannot silently drift apart.
    final step = firstUnansweredOnboardingStep(restored);
    if (step != null) return step;
    return await _faceVerificationGate() ?? RouteNames.discover;
  }

  /// Whether the backend already holds a finalized profile for this member.
  ///
  /// `GET /profiles/me` answers with the row itself, or 404 when registration
  /// never produced one — so a plain success/failure is the whole signal. It
  /// shares [_draftLookupTimeout] for the same reason the draft lookup has
  /// one: this is a routing decision, not a screen the member is waiting on,
  /// and a stalled request must not hold the splash open.
  ///
  /// False on ANY failure — 404, timeout, offline, a malformed body. That is
  /// the safe direction: it falls through to the gates below, which send an
  /// established member to Discover anyway once the draft lookup also fails
  /// (see the catch clause). Never throws, because this resolver's contract
  /// is that it always returns a route.
  Future<bool> _hasFinalizedProfile() async {
    try {
      await _ref
          .read(profileRepositoryProvider)
          .getMyProfile()
          .timeout(_draftLookupTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The address the Email + Mobile step is waiting on confirmation for, or
  /// empty. Guarded because this resolver's contract is that it never
  /// throws: local storage is initialised during bootstrap, and a read
  /// before that (or from a harness that skipped it) means only that there
  /// is no pending address to know about.
  String _pendingEmail() {
    try {
      return storageService.pendingEmail ?? '';
    } catch (_) {
      return '';
    }
  }

  /// The number that step stored, or empty. Unlike the address this one is
  /// never promoted onto the Firebase account — nothing links a phone
  /// credential while the OTP is the development verifier — so it is the
  /// only record that the step was answered on this device. Guarded for the
  /// same reason as [_pendingEmail].
  String _pendingPhone() {
    try {
      return storageService.pendingPhone ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Whether onboarding finished on this device. The verify-mobile step
  /// clears the pending number when it sets this, so without it a member who
  /// completed signup would fall back through the Email + Mobile gate the
  /// moment they reached it. Guarded for the same reason as [_pendingEmail].
  bool _onboardingCompleted() {
    try {
      return storageService.onboardingCompleted;
    } catch (_) {
      return false;
    }
  }

  /// Whether the signed-in member must complete face verification before
  /// reaching Discover — [RouteNames.faceVerification] if so, else `null`.
  ///
  /// Reads the real backend state (`GET /verification/face` via
  /// [faceVerificationStatusProvider]) rather than any local flag: per
  /// docs/development/selfie-verification-frontend-handoff.md, "verified" is
  /// derived entirely server-side and can revert (a photo change revokes it),
  /// so a device-local cache could both wrongly block a verified member and
  /// wrongly admit a revoked one.
  ///
  /// `NOT_AVAILABLE` (the feature is off, unconfigured, or at its global
  /// daily cap — currently true everywhere, since `FACE_VERIFICATION_ENABLED`
  /// defaults to false) is a deliberate pass-through, not a bypass: the
  /// backend has not offered verification, so it cannot be a precondition
  /// for entry. The moment the backend turns the feature on this check
  /// starts gating automatically, with nothing to change here.
  ///
  /// On any failure to reach the backend, this falls through to Discover
  /// (returns `null`) rather than blocking a member on a state it could not
  /// confirm — matching this resolver's "never blocks on an unknown" policy
  /// elsewhere ([_hasFinalizedProfile]).
  Future<String?> _faceVerificationGate() async {
    try {
      final state = await _ref
          .read(faceVerificationStatusProvider.future)
          .timeout(_draftLookupTimeout);
      if (state.satisfiesEntryGate) return null;
      AuthTrace.destination(RouteNames.faceVerification);
      return RouteNames.faceVerification;
    } catch (_) {
      return null;
    }
  }

  bool _isBrandNewAccount(DateTime? createdAt, DateTime? lastSignInAt) {
    if (createdAt == null || lastSignInAt == null) return false;
    return lastSignInAt.difference(createdAt).abs() < _brandNewAccountWindow;
  }
}

final postAuthDestinationProvider = Provider<PostAuthDestination>(
  PostAuthDestination.new,
);
