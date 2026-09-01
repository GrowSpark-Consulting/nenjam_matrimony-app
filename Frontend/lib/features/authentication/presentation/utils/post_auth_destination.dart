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
/// 5. The account lacks an email or a mobile number →
///    [RouteNames.onboardingContact].
/// 6. State or city missing → [RouteNames.profileBasics].
/// 7. Otherwise → Discover.
///
/// Each gate tests exactly the fields its screen writes — the same
/// `isComplete` rules the screens enforce, from
/// `registration/domain/models/onboarding_forms.dart` — so answering a step
/// is always what gets a member past it, and no gate can loop.
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

    // Step 3. Both channels live on the Firebase account, not the draft.
    // `pendingEmail` covers the window in which a member has been sent a
    // confirmation link but has not opened it: Firebase does not attach the
    // address until they do, and without the marker they would be sent
    // round to this step again every launch until then.
    final hasEmail =
        (user.email ?? '').isNotEmpty || _pendingEmail().isNotEmpty;
    final hasMobile = (user.phoneNumber ?? '').isNotEmpty;
    if (!hasEmail || !hasMobile) return RouteNames.onboardingContact;

    // Step 4.
    final basicsStep = ProfileBasicsForm(
      state: restored.locationDetails.state,
      city: restored.locationDetails.city,
    );
    if (!basicsStep.isComplete) return RouteNames.profileBasics;

    // Step 5 — marital status and height.
    final maritalStep = OnboardingMaritalForm(
      maritalStatus: restored.basicDetails.maritalStatus,
      height: restored.physicalDetails.height,
    );
    if (!maritalStep.isComplete) return RouteNames.onboardingMarital;

    // Step 6 — highest qualification.
    final educationStep = OnboardingEducationForm(
      qualification: restored.educationDetails.qualification,
    );
    if (!educationStep.isComplete) return RouteNames.onboardingEducation;

    // Step 7 — annual income.
    final incomeStep = OnboardingIncomeForm(
      annualIncome: restored.educationDetails.annualIncome,
    );
    if (!incomeStep.isComplete) return RouteNames.onboardingIncome;

    // Step 8 (photos) is deliberately not a gate — it is optional, and a
    // member who chose "Add Photos Later" must not be sent back to it every
    // launch. Step 9 is, since a description is part of a usable profile.
    if (restored.lifestyleDetails.aboutMe.trim().isEmpty) {
      return RouteNames.onboardingAbout;
    }

    // Step 10 — the number must actually be verified, which for Firebase
    // means linked to the account. `hasMobile` above already establishes
    // that, so reaching here means onboarding is genuinely finished.
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

  bool _isBrandNewAccount(DateTime? createdAt, DateTime? lastSignInAt) {
    if (createdAt == null || lastSignInAt == null) return false;
    return lastSignInAt.difference(createdAt).abs() < _brandNewAccountWindow;
  }
}

final postAuthDestinationProvider = Provider<PostAuthDestination>(
  PostAuthDestination.new,
);
