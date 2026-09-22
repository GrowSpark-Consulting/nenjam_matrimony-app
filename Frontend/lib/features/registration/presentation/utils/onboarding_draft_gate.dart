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
///
/// [gatePendingPhotos] adds the Add Photos step to the chain, gated on the
/// draft's *staged* photos. Off by default, and deliberately so: photos are
/// not a draft field. They are an independent resource the backend serves
/// from `GET /profiles/me/photos`, and `photoGallery` holds only the
/// pre-session staging queue — nothing ever writes it back from the server.
/// A caller that restored a backend draft therefore sees an empty gallery
/// for a member with six uploaded photos, so gating it there would send
/// every established member to the photo step instead of the app. Only a
/// caller whose draft IS the local snapshot (see [SplashController]) may
/// turn it on, because for that caller a staged photo is the whole truth.
/// Post-session, the requirement is enforced by the Add Photos screen
/// itself, which reads live photo state.
String? firstUnansweredOnboardingStep(
  ProfileDraft draft, {
  bool gatePendingPhotos = false,
}) {
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

  // At least one photo is required — but only a caller that opted in can be
  // asked this, and only about staged photos. See [gatePendingPhotos].
  if (gatePendingPhotos && draft.photoGallery.pendingPaths.isEmpty) {
    return RouteNames.onboardingPhotos;
  }

  if (draft.lifestyleDetails.aboutMe.trim().isEmpty) {
    return RouteNames.onboardingAbout;
  }

  return null;
}

/// Whether every draft-backed onboarding step has an answer, for the Email +
/// Mobile gate in `PostAuthDestination.resolve()`.
///
/// That gate is scoped to a signup that is still unfinished — see its comment
/// there for why it is a signup gate rather than a session gate — and
/// "unfinished" means exactly "some draft-backed step still owes an answer".
///
/// Deliberately NOT expressed as `firstUnansweredOnboardingStep(draft) == null`,
/// close as the two look. That chain routes the name step on
/// [OnboardingNameForm.isAnswered], which omits the age floor so a member who
/// registered under the previous floor of 18 is not sent back to a step no
/// answer of theirs can satisfy. This predicate keeps [isComplete], age floor
/// and all, because it is the condition the contact gate has always applied.
/// Collapsing the two would quietly change who that gate stops.
///
/// The religion step is likewise absent here, exactly as it was in the
/// original inline condition.
bool allOnboardingStepsAnswered(ProfileDraft draft) {
  final profileForStep = ProfileForForm(
    profileCreatedFor: draft.basicDetails.profileCreatedFor,
    gender: draft.basicDetails.gender,
  );
  final nameStep = OnboardingNameForm.fromDraft(
    firstName: draft.basicDetails.firstName,
    lastName: draft.basicDetails.lastName,
    dob: draft.basicDetails.dob,
  );
  final basicsStep = ProfileBasicsForm(
    state: draft.locationDetails.state,
    city: draft.locationDetails.city,
  );
  final maritalStep = OnboardingMaritalForm(
    maritalStatus: draft.basicDetails.maritalStatus,
    height: draft.physicalDetails.height,
  );
  final educationStep = OnboardingEducationForm(
    qualification: draft.educationDetails.qualification,
  );
  final incomeStep = OnboardingIncomeForm(
    annualIncome: draft.educationDetails.annualIncome,
  );

  return profileForStep.isComplete &&
      nameStep.isComplete &&
      basicsStep.isComplete &&
      maritalStep.isComplete &&
      educationStep.isComplete &&
      incomeStep.isComplete &&
      draft.lifestyleDetails.aboutMe.trim().isNotEmpty;
}
