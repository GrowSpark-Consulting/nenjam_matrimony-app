/// The answers each onboarding step collects, and the rule for when its
/// Continue may be tapped.
///
/// Onboarding is four screens — Profile For, Your Religion, Email + Mobile,
/// State + City — and this file owns the *required-field* rule for the two
/// that are plain forms. Stating it here rather than as a boolean inside a
/// widget's `build` is what lets `PostAuthDestination` gate on exactly the
/// same condition the screen enforces: one definition, so a member can never
/// be bounced to a step they have already satisfied, nor let past one they
/// have not.
///
/// None of these introduce a second representation of profile data. Every
/// value is a string the draft already stores, and the notifier
/// (`RegistrationNotifier.applyOnboardingReligion` /
/// `.applyProfileBasics`) maps them onto the sections that own them.
library;

/// Step 2 — "Your religion": religion, community, and the country the
/// member lives in.
class OnboardingReligionForm {
  /// Draft: `ReligionDetails.religion`. Required.
  final String religion;

  /// Draft: `ReligionDetails.community`. Required.
  final String community;

  /// "Living in" — draft: `LocationDetails.country`. Required. The country
  /// is asked here, a step before the state and city, because it decides
  /// whether those two are even the right questions.
  final String livingIn;

  /// "Not particular about my partner's community". Optional, and mapped
  /// onto the partner preference the app already has — see
  /// [casteNoBarPreference].
  final bool casteNoBar;

  const OnboardingReligionForm({
    this.religion = '',
    this.community = '',
    this.livingIn = '',
    this.casteNoBar = false,
  });

  /// The existing `PartnerPreference.castePref` value the checkbox stands
  /// for. Ticking it is not a new concept — it is the member saying "Any
  /// Caste", one of `partnerPrefCastes`, and exactly what the standalone
  /// Partner Preferences page would write. Unticking clears it back to
  /// unanswered rather than asserting the opposite: the member has not said
  /// they *do* care, only that they have not said they don't.
  static const String casteNoBarPreference = 'Any Caste';

  OnboardingReligionForm copyWith({
    String? religion,
    String? community,
    String? livingIn,
    bool? casteNoBar,
  }) {
    return OnboardingReligionForm(
      religion: religion ?? this.religion,
      community: community ?? this.community,
      livingIn: livingIn ?? this.livingIn,
      casteNoBar: casteNoBar ?? this.casteNoBar,
    );
  }

  /// The required fields still unanswered, in the order they appear on the
  /// step — so a validation message names them the way the member reads
  /// them down the screen.
  List<OnboardingReligionField> get missingFields => [
        if (religion.trim().isEmpty) OnboardingReligionField.religion,
        if (community.trim().isEmpty) OnboardingReligionField.community,
        if (livingIn.trim().isEmpty) OnboardingReligionField.livingIn,
      ];

  bool get isComplete => missingFields.isEmpty;
}

/// The required fields of [OnboardingReligionForm], for validation messages.
enum OnboardingReligionField { religion, community, livingIn }

/// Step 4 — "State & City". Sub-community is deliberately absent: it is not
/// required to get a member into the app, and the draft keeps the field for
/// Edit Profile to fill in later.
class ProfileBasicsForm {
  /// Draft: `LocationDetails.state`. Required.
  final String state;

  /// Draft: `LocationDetails.city`. Required.
  final String city;

  const ProfileBasicsForm({this.state = '', this.city = ''});

  ProfileBasicsForm copyWith({String? state, String? city}) {
    return ProfileBasicsForm(
      state: state ?? this.state,
      city: city ?? this.city,
    );
  }

  List<ProfileBasicsField> get missingFields => [
        if (state.trim().isEmpty) ProfileBasicsField.state,
        if (city.trim().isEmpty) ProfileBasicsField.city,
      ];

  bool get isComplete => missingFields.isEmpty;
}

/// The required fields of [ProfileBasicsForm], for validation messages.
enum ProfileBasicsField { state, city }

/// Step 5 — "Marital status". Height sits here too, as the reference screen
/// asks the two together; diet is offered alongside but optional.
class OnboardingMaritalForm {
  /// Draft: `BasicDetails.maritalStatus`. Required.
  final String maritalStatus;

  /// Draft: `PhysicalDetails.height`. Required.
  final String height;

  /// Draft: `LifestyleDetails.eatingHabit`. Optional — the reference marks
  /// only the first two with an asterisk.
  final String diet;

  const OnboardingMaritalForm({
    this.maritalStatus = '',
    this.height = '',
    this.diet = '',
  });

  OnboardingMaritalForm copyWith({
    String? maritalStatus,
    String? height,
    String? diet,
  }) {
    return OnboardingMaritalForm(
      maritalStatus: maritalStatus ?? this.maritalStatus,
      height: height ?? this.height,
      diet: diet ?? this.diet,
    );
  }

  List<OnboardingMaritalField> get missingFields => [
        if (maritalStatus.trim().isEmpty) OnboardingMaritalField.maritalStatus,
        if (height.trim().isEmpty) OnboardingMaritalField.height,
      ];

  bool get isComplete => missingFields.isEmpty;
}

enum OnboardingMaritalField { maritalStatus, height }

/// Step 6 — "Highest qualification". College is offered but optional.
class OnboardingEducationForm {
  /// Draft: `EducationDetails.qualification`. Required.
  final String qualification;

  /// Draft: `EducationDetails.college`. Optional.
  final String college;

  const OnboardingEducationForm({this.qualification = '', this.college = ''});

  OnboardingEducationForm copyWith({String? qualification, String? college}) {
    return OnboardingEducationForm(
      qualification: qualification ?? this.qualification,
      college: college ?? this.college,
    );
  }

  List<OnboardingEducationField> get missingFields => [
        if (qualification.trim().isEmpty)
          OnboardingEducationField.qualification,
      ];

  bool get isComplete => missingFields.isEmpty;
}

enum OnboardingEducationField { qualification }

/// Step 7 — "Annual income" plus work details. Only the income is required;
/// the three work fields are offered on the same screen but a member who
/// isn't working can still finish.
class OnboardingIncomeForm {
  /// Draft: `EducationDetails.annualIncome`. Required.
  final String annualIncome;

  /// "You work with" — draft: `EducationDetails.employmentType`.
  final String workWith;

  /// "You work as" — draft: `EducationDetails.occupation`.
  final String workAs;

  /// Draft: `EducationDetails.company`.
  final String companyName;

  const OnboardingIncomeForm({
    this.annualIncome = '',
    this.workWith = '',
    this.workAs = '',
    this.companyName = '',
  });

  OnboardingIncomeForm copyWith({
    String? annualIncome,
    String? workWith,
    String? workAs,
    String? companyName,
  }) {
    return OnboardingIncomeForm(
      annualIncome: annualIncome ?? this.annualIncome,
      workWith: workWith ?? this.workWith,
      workAs: workAs ?? this.workAs,
      companyName: companyName ?? this.companyName,
    );
  }

  List<OnboardingIncomeField> get missingFields => [
        if (annualIncome.trim().isEmpty) OnboardingIncomeField.annualIncome,
      ];

  bool get isComplete => missingFields.isEmpty;
}

enum OnboardingIncomeField { annualIncome }
