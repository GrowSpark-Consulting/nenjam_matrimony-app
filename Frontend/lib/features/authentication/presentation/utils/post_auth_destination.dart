import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
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
/// Onboarding is four screens, and this resolves to the **first** of them
/// the member has not finished — so a session killed halfway resumes exactly
/// where it stopped, and a finished one never sees any of them again:
///
/// 1. Not signed in → the sign-up landing screen.
/// 2. Has an email address that isn't verified yet → the verify-email step.
/// 3. No "profile is for" choice → [RouteNames.createProfileFor].
/// 4. Religion, community or "living in" missing →
///    [RouteNames.onboardingReligion].
/// 5. An unfinished signup with no email or mobile on record →
///    [RouteNames.onboardingContact]. Only an unfinished signup: this
///    step's answers are stored nowhere the backend can see, so asking
///    it of an established account is unanswerable, and doing so was
///    the bug that sent every login into onboarding. The gate itself
///    carries the full account.
/// 6. State or city missing → [RouteNames.profileBasics].
/// 7. Otherwise → Discover.
///
/// Each gate tests exactly the fields its screen writes — the same
/// `isComplete` rules the screens enforce, from
/// `registration/domain/models/onboarding_forms.dart` — so answering a step
/// is always what gets a member past it, and no gate can loop. The
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
    if (user == null) return RouteNames.registrationLanding;

    // Phone-only accounts have no address to verify, so this gate must key
    // on "has an email that is unverified", not on `emailVerified` alone —
    // otherwise a phone signup loops forever on a verify-email screen with
    // nothing to resend to.
    final email = user.email;
    if (email != null && email.isNotEmpty && !user.emailVerified) {
      return RouteNames.verifyEmail;
    }

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

    // Step 1. An empty value means the question has genuinely never been
    // answered — BasicDetails documents why the field has no default.
    if (restored.basicDetails.profileCreatedFor.trim().isEmpty) {
      return RouteNames.createProfileFor;
    }

    // Step 2 — the same fields OnboardingReligionForm.isComplete requires,
    // read back from the sections applyOnboardingReligion writes them to.
    final religionStep = OnboardingReligionForm(
      religion: restored.religionDetails.religion,
      community: restored.religionDetails.community,
      livingIn: restored.locationDetails.country,
    );
    if (!religionStep.isComplete) return RouteNames.onboardingReligion;

    // Steps 4-9, evaluated up front because step 3 has to consult them —
    // see below. Each still tests exactly the fields its own screen writes.
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
    final onboardingAnswered = basicsStep.isComplete &&
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

    // Step 4.
    if (!basicsStep.isComplete) return RouteNames.profileBasics;

    // Step 5 — marital status and height.
    if (!maritalStep.isComplete) return RouteNames.onboardingMarital;

    // Step 6 — highest qualification.
    if (!educationStep.isComplete) return RouteNames.onboardingEducation;

    // Step 7 — annual income.
    if (!incomeStep.isComplete) return RouteNames.onboardingIncome;

    // Step 8 (photos) is deliberately not a gate — it is optional, and a
    // member who chose "Add Photos Later" must not be sent back to it every
    // launch. Step 9 is, since a description is part of a usable profile.
    if (!hasAbout) return RouteNames.onboardingAbout;

    // Every step that leaves a durable answer has one. Onboarding is done.
    return RouteNames.discover;
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
