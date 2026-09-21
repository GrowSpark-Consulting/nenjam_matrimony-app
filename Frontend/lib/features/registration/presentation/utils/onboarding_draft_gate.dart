import '../../../../core/router/route_names.dart';
import '../../domain/models/onboarding_forms.dart';
import '../../domain/models/profile_draft.dart';

/// The draft-backed half of onboarding's routing rule: given a [ProfileDraft],
/// which screen (if any) still owes an answer.
///
/// Extracted from `PostAuthDestination.resolve()` / `_resolveFromDraftOnly()`,
/// which both walked this exact chain inline and had begun to drift apart —
/// one definition here is what keeps a future field added to one path from
/// silently missing the other. It also lets a *pre-session* caller (no
/// Firebase user, no backend draft — see [SplashController]) apply the same
/// gates to the local on-disk snapshot, instead of duplicating the chain a
/// third time or discarding that snapshot for want of somewhere to resolve
/// it against.
///
/// Deliberately excludes the two gates that need a Firebase account
/// ([RouteNames.verifyEmail] and the Email + Mobile step's `hasEmail`/
/// `hasMobile` check) — those remain in `PostAuthDestination.resolve()`
/// itself, since only it has a `User` to read. A pre-session caller has
/// nothing to ask instead: the account those two gates describe does not
/// exist yet.
///
/// Returns `null` when every draft-backed step is answered — onboarding is
/// done, as far as the draft alone can say.
String? firstUnansweredOnboardingStep(ProfileDraft draft) {
  final profileForStep = ProfileForForm(
    profileCreatedFor: draft.basicDetails.profileCreatedFor,
    gender: draft.basicDetails.gender,
  );
  if (!profileForStep.isComplete) return RouteNames.createProfileFor;

  final nameStep = OnboardingNameForm.fromDraft(
    firstName: draft.basicDetails.firstName,
    lastName: draft.basicDetails.lastName,
    dob: draft.basicDetails.dob,
  );
  if (!nameStep.isAnswered) return RouteNames.onboardingNameDob;

  final religionStep = OnboardingReligionForm(
    religion: draft.religionDetails.religion,
    community: draft.religionDetails.community,
    livingIn: draft.locationDetails.country,
  );
  if (!religionStep.isComplete) return RouteNames.onboardingReligion;

  final basicsStep = ProfileBasicsForm(
    state: draft.locationDetails.state,
    city: draft.locationDetails.city,
  );
  if (!basicsStep.isComplete) return RouteNames.profileBasics;

  final maritalStep = OnboardingMaritalForm(
    maritalStatus: draft.basicDetails.maritalStatus,
    height: draft.physicalDetails.height,
  );
  if (!maritalStep.isComplete) return RouteNames.onboardingMarital;

  final educationStep = OnboardingEducationForm(
    qualification: draft.educationDetails.qualification,
  );
  if (!educationStep.isComplete) return RouteNames.onboardingEducation;

  final incomeStep = OnboardingIncomeForm(
    annualIncome: draft.educationDetails.annualIncome,
  );
  if (!incomeStep.isComplete) return RouteNames.onboardingIncome;

  if (draft.lifestyleDetails.aboutMe.trim().isEmpty) {
    return RouteNames.onboardingAbout;
  }

  return null;
}
