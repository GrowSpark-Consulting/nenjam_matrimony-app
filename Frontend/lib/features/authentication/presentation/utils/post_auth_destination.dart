import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../domain/services/local_auth_session.dart';
import '../../../registration/domain/models/onboarding_forms.dart';
import '../../../registration/domain/models/profile_draft.dart';
import '../../../registration/domain/models/profile_flow_mode.dart';
import '../../../registration/presentation/providers/registration_provider.dart';
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
/// There is deliberately no branch into [RouteNames.registrationWizard].
/// That screen belongs to Edit Profile now: a member whose profile is merely
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

    if (user == null) return RouteNames.registrationLanding;

    // Phone-only accounts have no address to verify, so this gate must key
    // on "has an email that is unverified", not on `emailVerified` alone —
    // otherwise a phone signup loops forever on a verify-email screen with
    // nothing to resend to.
    final email = user.email;
    if (email != null && email.isNotEmpty && !user.emailVerified) {
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
    if (await _hasFinalizedProfile()) return RouteNames.discover;

    final Map<String, dynamic> draft;
    try {
      draft = await _ref
          .read(registrationRepositoryProvider)
          .getDraft()
          .timeout(_draftLookupTimeout);
    } catch (_) {
      return _isBrandNewAccount(user.metadata.creationTime,
              user.metadata.lastSignInTime)
          ? RouteNames.createProfileFor
          : RouteNames.discover;
    }

    final restored = ProfileDraft.fromJson(draft);

    // Rehydrating first is what lets each onboarding screen reopen on the
    // answers already given, rather than blank, when a member resumes on a
    // new device or after a reinstall.
    _ref
        .read(registrationProvider.notifier)
        .restore(restored, ProfileFlowMode.create);

    // Step 1 — "Profile For" and Gender, which that screen now asks together.
    // An empty value means the question has genuinely never been answered —
    // BasicDetails documents why neither field has a default.
    final profileForStep = ProfileForForm(
      profileCreatedFor: restored.basicDetails.profileCreatedFor,
      gender: restored.basicDetails.gender,
    );
    if (!profileForStep.isComplete) return RouteNames.createProfileFor;

    // Step 2 — name and date of birth. Reconstructed through
    // OnboardingNameForm.fromDraft so the gate applies the screen's own rule
    // (a stored date that is somehow not a real one re-asks the step) rather
    // than a second, looser "is it non-null" test written out here.
    final nameStep = OnboardingNameForm.fromDraft(
      firstName: restored.basicDetails.firstName,
      lastName: restored.basicDetails.lastName,
      dob: restored.basicDetails.dob,
    );
    if (!nameStep.isComplete) return RouteNames.onboardingNameDob;

    // Step 3 — the same fields OnboardingReligionForm.isComplete requires,
    // read back from the sections applyOnboardingReligion writes them to.
    final religionStep = OnboardingReligionForm(
      religion: restored.religionDetails.religion,
      community: restored.religionDetails.community,
      livingIn: restored.locationDetails.country,
    );
    if (!religionStep.isComplete) return RouteNames.onboardingReligion;

    // Steps 5-10, evaluated up front because step 4 has to consult them —
    // see below. Each tests exactly the fields its own screen requires, which
    // is why caste and mother tongue appear in no gate at all: onboarding no
    // longer collects them, and a gate on a field no screen asks for is a
    // gate a member cannot answer their way past. Sub-community is absent for
    // the same reason — asked, but not required.
    final basicsStep = ProfileBasicsForm(
      state: restored.locationDetails.state,
      city: restored.locationDetails.city,
    );
    final maritalStep = OnboardingMaritalForm(
      maritalStatus: restored.basicDetails.maritalStatus,
      height: restored.physicalDetails.height,
    );
    final educationStep = OnboardingEducationForm(
      qualification: restored.educationDetails.qualification,
    );
    final incomeStep = OnboardingIncomeForm(
      annualIncome: restored.educationDetails.annualIncome,
    );
    final hasAbout = restored.lifestyleDetails.aboutMe.trim().isNotEmpty;

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
    final onboardingAnswered = profileForStep.isComplete &&
        nameStep.isComplete &&
        basicsStep.isComplete &&
        maritalStep.isComplete &&
        educationStep.isComplete &&
        incomeStep.isComplete &&
        hasAbout;
    if (!onboardingAnswered && !_onboardingCompleted()) {
      // `pendingEmail`/`pendingPhone` cover the window between answering
      // this step and the account carrying the values: Firebase attaches an
      // address only once the member opens the link, and never attaches the
      // number at all.
      final hasEmail =
          (user.email ?? '').isNotEmpty || _pendingEmail().isNotEmpty;
      final hasMobile =
          (user.phoneNumber ?? '').isNotEmpty || _pendingPhone().isNotEmpty;
      if (!hasEmail || !hasMobile) return RouteNames.onboardingContact;
    }

    // Step 5.
    if (!basicsStep.isComplete) return RouteNames.profileBasics;

    // Step 6 — marital status and height.
    if (!maritalStep.isComplete) return RouteNames.onboardingMarital;

    // Step 7 — highest qualification.
    if (!educationStep.isComplete) return RouteNames.onboardingEducation;

    // Step 8 — annual income.
    if (!incomeStep.isComplete) return RouteNames.onboardingIncome;

    // Step 9 (photos) is deliberately not a gate — it is optional, and a
    // member who chose "Add Photos Later" must not be sent back to it every
    // launch. Step 10 is, since a description is part of a usable profile.
    if (!hasAbout) return RouteNames.onboardingAbout;

    // Every step that leaves a durable answer has one. Onboarding is done.
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
    if (await _hasFinalizedProfile()) return RouteNames.discover;

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

    final profileForStep = ProfileForForm(
      profileCreatedFor: restored.basicDetails.profileCreatedFor,
      gender: restored.basicDetails.gender,
    );
    if (!profileForStep.isComplete) return RouteNames.createProfileFor;

    final nameStep = OnboardingNameForm.fromDraft(
      firstName: restored.basicDetails.firstName,
      lastName: restored.basicDetails.lastName,
      dob: restored.basicDetails.dob,
    );
    if (!nameStep.isComplete) return RouteNames.onboardingNameDob;

    final religionStep = OnboardingReligionForm(
      religion: restored.religionDetails.religion,
      community: restored.religionDetails.community,
      livingIn: restored.locationDetails.country,
    );
    if (!religionStep.isComplete) return RouteNames.onboardingReligion;

    final basicsStep = ProfileBasicsForm(
      state: restored.locationDetails.state,
      city: restored.locationDetails.city,
    );
    if (!basicsStep.isComplete) return RouteNames.profileBasics;

    final maritalStep = OnboardingMaritalForm(
      maritalStatus: restored.basicDetails.maritalStatus,
      height: restored.physicalDetails.height,
    );
    if (!maritalStep.isComplete) return RouteNames.onboardingMarital;

    final educationStep = OnboardingEducationForm(
      qualification: restored.educationDetails.qualification,
    );
    if (!educationStep.isComplete) return RouteNames.onboardingEducation;

    final incomeStep = OnboardingIncomeForm(
      annualIncome: restored.educationDetails.annualIncome,
    );
    if (!incomeStep.isComplete) return RouteNames.onboardingIncome;

    if (restored.lifestyleDetails.aboutMe.trim().isEmpty) {
      return RouteNames.onboardingAbout;
    }

    return RouteNames.discover;
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

  bool _isBrandNewAccount(DateTime? createdAt, DateTime? lastSignInAt) {
    if (createdAt == null || lastSignInAt == null) return false;
    return lastSignInAt.difference(createdAt).abs() < _brandNewAccountWindow;
  }
}

final postAuthDestinationProvider = Provider<PostAuthDestination>(
  PostAuthDestination.new,
);
