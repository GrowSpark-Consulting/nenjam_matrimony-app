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

/// Step 2 — "Your religion": religion, caste, community, mother tongue, and
/// the country the member lives in.
///
/// Caste and mother tongue are asked here because `user_profiles.caste` and
/// `user_profiles.mother_tongue` are both NOT NULL. Onboarding used to skip
/// them, so `isMatchableFromDraft` could never pass and the backend never
/// wrote a profile row at all — the member finished onboarding, landed on
/// Discover, and `GET /profiles/me` answered 404 for the rest of the account's
/// life. A step that collects them is the only fix that does not mean
/// inventing a value into someone's profile.
class OnboardingReligionForm {
  /// Draft: `ReligionDetails.religion`. Required.
  final String religion;

  /// Draft: `ReligionDetails.caste`. Required — NOT NULL on `user_profiles`.
  /// Free text, like the wizard's own caste field: there is no authoritative
  /// caste list in this app and inventing one is not an option.
  final String caste;

  /// Draft: `ReligionDetails.community`. Required.
  final String community;

  /// Draft: `LanguageDetails.motherTongue`. Required — NOT NULL on
  /// `user_profiles`.
  final String motherTongue;

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
    this.caste = '',
    this.community = '',
    this.motherTongue = '',
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
    String? caste,
    String? community,
    String? motherTongue,
    String? livingIn,
    bool? casteNoBar,
  }) {
    return OnboardingReligionForm(
      religion: religion ?? this.religion,
      caste: caste ?? this.caste,
      community: community ?? this.community,
      motherTongue: motherTongue ?? this.motherTongue,
      livingIn: livingIn ?? this.livingIn,
      casteNoBar: casteNoBar ?? this.casteNoBar,
    );
  }

  /// The required fields still unanswered, in the order they appear on the
  /// step — so a validation message names them the way the member reads
  /// them down the screen.
  List<OnboardingReligionField> get missingFields => [
        if (religion.trim().isEmpty) OnboardingReligionField.religion,
        if (caste.trim().isEmpty) OnboardingReligionField.caste,
        if (community.trim().isEmpty) OnboardingReligionField.community,
        if (motherTongue.trim().isEmpty) OnboardingReligionField.motherTongue,
        if (livingIn.trim().isEmpty) OnboardingReligionField.livingIn,
      ];

  bool get isComplete => missingFields.isEmpty;
}

/// The required fields of [OnboardingReligionForm], for validation messages.
enum OnboardingReligionField {
  religion,
  caste,
  community,
  motherTongue,
  livingIn,
}

/// Step 4 — "Now let's build your Profile": name, gender, date of birth,
/// state and city. Sub-community is deliberately absent: it is not required
/// to get a member into the app, and the draft keeps the field for Edit
/// Profile to fill in later.
///
/// Name, gender and date of birth are asked here for the same reason caste
/// and mother tongue moved onto the religion step: `first_name`, `last_name`,
/// `gender` and `dob` are all NOT NULL on `user_profiles`, so without them the
/// backend cannot write the row and the member's profile never exists. They
/// also happen to be what Discover renders — a card has to show a name and an
/// age — so this is the screen that owes them.
class ProfileBasicsForm {
  /// Draft: `BasicDetails.firstName`. Required — NOT NULL.
  final String firstName;

  /// Draft: `BasicDetails.lastName`. Required — NOT NULL.
  final String lastName;

  /// Draft: `BasicDetails.gender`. Required — NOT NULL. Held in the draft's
  /// own representation ('Male' / 'Female'); `BasicDetails.toJson` is what
  /// maps it to the API's MALE / FEMALE, so this must not pre-convert.
  final String gender;

  /// Draft: `BasicDetails.dob`. Required — NOT NULL.
  final DateTime? dob;

  /// Draft: `LocationDetails.state`. Required.
  final String state;

  /// Draft: `LocationDetails.city`. Required.
  final String city;

  const ProfileBasicsForm({
    this.firstName = '',
    this.lastName = '',
    this.gender = '',
    this.dob,
    this.state = '',
    this.city = '',
  });

  ProfileBasicsForm copyWith({
    String? firstName,
    String? lastName,
    String? gender,
    DateTime? dob,
    String? state,
    String? city,
  }) {
    return ProfileBasicsForm(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      gender: gender ?? this.gender,
      dob: dob ?? this.dob,
      state: state ?? this.state,
      city: city ?? this.city,
    );
  }

  List<ProfileBasicsField> get missingFields => [
        if (firstName.trim().isEmpty) ProfileBasicsField.firstName,
        if (lastName.trim().isEmpty) ProfileBasicsField.lastName,
        if (gender.trim().isEmpty) ProfileBasicsField.gender,
        if (dob == null) ProfileBasicsField.dob,
        if (state.trim().isEmpty) ProfileBasicsField.state,
        if (city.trim().isEmpty) ProfileBasicsField.city,
      ];

  bool get isComplete => missingFields.isEmpty;
}

/// The required fields of [ProfileBasicsForm], for validation messages.
enum ProfileBasicsField { firstName, lastName, gender, dob, state, city }

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
