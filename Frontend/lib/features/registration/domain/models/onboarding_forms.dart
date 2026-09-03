/// The answers each onboarding step collects, and the rule for when its
/// Continue may be tapped.
///
/// Onboarding is a chain of single-purpose screens — Profile For + Gender,
/// Your Name, Your Religion, Email + Mobile, State + City, and the rest — and
/// this file owns the *required-field* rule for the ones that are plain
/// forms. Stating it here rather than as a boolean inside a
/// widget's `build` is what lets `PostAuthDestination` gate on exactly the
/// same condition the screen enforces: one definition, so a member can never
/// be bounced to a step they have already satisfied, nor let past one they
/// have not.
///
/// None of these introduce a second representation of profile data. Every
/// value is a string the draft already stores, and the notifier
/// (`RegistrationNotifier.applyProfileFor` / `.applyOnboardingName` /
/// `.applyOnboardingReligion` / `.applyProfileBasics`) maps them onto the
/// sections that own them.
library;

/// Step 1 — "Profile For" and "Gender".
///
/// Gender moved here from the State & City step. It is one question, asked
/// once, and it still lives on `BasicDetails.gender` — the same field the
/// wizard's Basic Info step writes and the same one `BasicDetails.toJson`
/// maps to the API's MALE / FEMALE. Nothing about where gender is stored,
/// validated on the server, or written to `user_profiles` changed; only the
/// screen that asks for it.
///
/// Asking it first is also what the rest of onboarding wants: gender decides
/// who a member is matched against, and every screen after this one is about
/// a profile that already has one.
class ProfileForForm {
  /// Draft: `BasicDetails.profileCreatedFor` ('Myself', 'Son', ...). Required.
  /// Empty means the question has genuinely never been answered — see
  /// [BasicDetails.profileCreatedFor] for why it has no default.
  final String profileCreatedFor;

  /// Draft: `BasicDetails.gender`. Required — NOT NULL on `user_profiles`.
  /// Held in the draft's own representation ('Male' / 'Female'); the mapping
  /// to MALE / FEMALE belongs to `BasicDetails.toJson`, so this must not
  /// pre-convert.
  final String gender;

  const ProfileForForm({this.profileCreatedFor = '', this.gender = ''});

  ProfileForForm copyWith({String? profileCreatedFor, String? gender}) {
    return ProfileForForm(
      profileCreatedFor: profileCreatedFor ?? this.profileCreatedFor,
      gender: gender ?? this.gender,
    );
  }

  List<ProfileForField> get missingFields => [
        if (profileCreatedFor.trim().isEmpty) ProfileForField.profileCreatedFor,
        if (gender.trim().isEmpty) ProfileForField.gender,
      ];

  bool get isComplete => missingFields.isEmpty;
}

/// The required fields of [ProfileForForm], for validation messages.
enum ProfileForField { profileCreatedFor, gender }

/// Step 2 — "Your name" and "Date of birth".
///
/// Its own screen rather than a block on the State + City step, because
/// `first_name`, `last_name` and `dob` are what every later screen's copy and
/// every Discover card lean on, and asking for them beside a location picker
/// buried the one thing the member came to answer. Nothing about where the
/// values *land* changed: all three are still `BasicDetails` fields written
/// by the same `PATCH /profiles/draft/basic-details`.
///
/// The date is held as three strings rather than a [DateTime] because that is
/// still the shape a half-answered date has: a draft restored with no date at
/// all is three empty strings, and [dob] is the parsed value — null whenever
/// the parts do not name a real, allowed date. The screen no longer asks the
/// member to *type* them (it opens a calendar and calls [withDob]), but the
/// validation below is unchanged and is still what `PostAuthDestination`
/// reconstructs to decide whether the step has been answered.
class OnboardingNameForm {
  /// Draft: `BasicDetails.firstName`. Required — NOT NULL on `user_profiles`.
  final String firstName;

  /// Draft: `BasicDetails.lastName`. Required — NOT NULL on `user_profiles`.
  final String lastName;

  /// The three date-of-birth boxes, exactly as typed.
  final String day;
  final String month;
  final String year;

  const OnboardingNameForm({
    this.firstName = '',
    this.lastName = '',
    this.day = '',
    this.month = '',
    this.year = '',
  });

  /// Rebuilds the form from a stored date — reopening the step shows the
  /// answer already given rather than three empty boxes.
  factory OnboardingNameForm.fromDraft({
    required String firstName,
    required String lastName,
    DateTime? dob,
  }) {
    return OnboardingNameForm(
      firstName: firstName,
      lastName: lastName,
      day: dob == null ? '' : dob.day.toString().padLeft(2, '0'),
      month: dob == null ? '' : dob.month.toString().padLeft(2, '0'),
      year: dob == null ? '' : dob.year.toString(),
    );
  }

  /// The same form with [date] as its date of birth — what the calendar
  /// picker returns, written back into the three parts the form has always
  /// held so that [dob] and [isComplete] are computed by exactly the rule
  /// below and not by a second, picker-only path.
  OnboardingNameForm withDob(DateTime date) {
    return copyWith(
      day: date.day.toString().padLeft(2, '0'),
      month: date.month.toString().padLeft(2, '0'),
      year: date.year.toString(),
    );
  }

  OnboardingNameForm copyWith({
    String? firstName,
    String? lastName,
    String? day,
    String? month,
    String? year,
  }) {
    return OnboardingNameForm(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      day: day ?? this.day,
      month: month ?? this.month,
      year: year ?? this.year,
    );
  }

  /// Youngest date of birth a matrimony profile may carry — the same floor
  /// the wizard's calendar enforces with its `lastDate`.
  static const int minimumAgeYears = 18;

  /// Oldest. Matches the wizard picker's `firstDate` of 1950 rather than
  /// inventing a second bound.
  static const int earliestBirthYear = 1950;

  /// The most recent date of birth this form accepts: [minimumAgeYears] ago
  /// to the day. Exposed because the step's calendar has to be bounded by the
  /// same rule that validates the result — a picker that offered a date [dob]
  /// then rejected would leave the member with no way to finish the step.
  static DateTime latestAllowedDob([DateTime? asOf]) {
    final now = asOf ?? DateTime.now();
    return DateTime(now.year - minimumAgeYears, now.month, now.day);
  }

  /// The earliest date this form accepts, as a date rather than a year — the
  /// calendar's `firstDate`.
  static DateTime earliestAllowedDob() => DateTime(earliestBirthYear);

  /// The date the three boxes name, or null when they do not name one.
  ///
  /// Rejects, in this order: a part that is not a number, a day/month outside
  /// its range, a day that does not exist in that month (31 February,
  /// 29 February of a common year — caught by round-tripping through
  /// [DateTime], which silently rolls those over), a date in the future, and a
  /// date outside the allowed age band. Every one of those is a date a member
  /// can type, and none of them may reach `user_profiles.dob`.
  DateTime? get dob {
    final d = int.tryParse(day.trim());
    final m = int.tryParse(month.trim());
    final y = int.tryParse(year.trim());
    if (d == null || m == null || y == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    if (y < earliestBirthYear) return null;

    final candidate = DateTime(y, m, d);
    // DateTime(2003, 2, 31) is 3 March — a rollover, not the date typed.
    if (candidate.year != y || candidate.month != m || candidate.day != d) {
      return null;
    }

    final now = DateTime.now();
    // Future dates, today included: nobody is born into the profile they are
    // filling in.
    if (!candidate.isBefore(DateTime(now.year, now.month, now.day))) {
      return null;
    }
    if (candidate.isAfter(latestAllowedDob(now))) return null;
    return candidate;
  }

  /// Whether the member has typed anything at all into the date boxes. Lets
  /// the screen stay quiet on a blank form and explain itself only once
  /// there is something to explain.
  bool get isDateTouched =>
      day.trim().isNotEmpty || month.trim().isNotEmpty || year.trim().isNotEmpty;

  /// Why [dob] is null, for the screen's inline message. Null when the date
  /// is either fine or not yet worth complaining about.
  OnboardingNameDateError? get dateError {
    if (dob != null) return null;
    if (!isDateTouched) return null;
    if (day.trim().isEmpty || month.trim().isEmpty || year.trim().length < 4) {
      return null;
    }

    final d = int.tryParse(day.trim());
    final m = int.tryParse(month.trim());
    final y = int.tryParse(year.trim());
    if (d == null || m == null || y == null) {
      return OnboardingNameDateError.invalid;
    }
    if (y < earliestBirthYear) return OnboardingNameDateError.tooOld;

    // A real calendar date that is simply too recent — the age floor, or a
    // date that has not happened yet. Told apart from "31 February" so the
    // message can say which.
    final valid = m >= 1 &&
        m <= 12 &&
        d >= 1 &&
        d <= 31 &&
        DateTime(y, m, d).month == m &&
        DateTime(y, m, d).day == d;
    return valid
        ? OnboardingNameDateError.tooYoung
        : OnboardingNameDateError.invalid;
  }

  List<OnboardingNameField> get missingFields => [
        if (firstName.trim().isEmpty) OnboardingNameField.firstName,
        if (lastName.trim().isEmpty) OnboardingNameField.lastName,
        if (dob == null) OnboardingNameField.dob,
      ];

  bool get isComplete => missingFields.isEmpty;
}

/// The required fields of [OnboardingNameForm], for validation messages.
enum OnboardingNameField { firstName, lastName, dob }

/// Why a typed date of birth was rejected — see [OnboardingNameForm.dateError].
enum OnboardingNameDateError {
  /// Not a real calendar date (31 February, letters, month 13).
  invalid,

  /// A real date, but under [OnboardingNameForm.minimumAgeYears] or still to
  /// come.
  tooYoung,

  /// Before [OnboardingNameForm.earliestBirthYear].
  tooOld,
}

/// Step 3 — "Your religion": religion, community, and the country the member
/// lives in.
///
/// Caste and mother tongue used to be asked here as well. They are no longer
/// collected anywhere in onboarding — see [ProfileBasicsForm] for what that
/// costs on the backend. Neither field was deleted: both remain on the draft,
/// in the DTOs and as columns, and the Edit Profile wizard's Religion and
/// Language steps still edit them.
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

/// Step 5 — "Now let's build your Profile": State, City and Sub-community.
///
/// Three questions, and only the first two required. Gender left this screen
/// for [ProfileForForm], which asks it first.
///
/// Caste and mother tongue are NOT asked here, and are not asked anywhere
/// else in onboarding either. That is a deliberate product decision, and it
/// has a cost worth stating where the next person will read it:
/// `user_profiles.caste` and `user_profiles.mother_tongue` are NOT NULL, and
/// the backend's `isMatchableFromDraft` requires both before it will write
/// the profile row — so an onboarding that collects neither cannot produce a
/// `user_profiles` row at all. Nothing about the two fields was deleted:
/// both are still on [ReligionDetails] / [LanguageDetails], still in the
/// DTOs, still columns, still edited by the Edit Profile wizard's Religion
/// and Language steps, and still rendered on Discover cards and profile
/// detail. They are simply no longer collected during signup.
///
/// Sub-community is asked but optional — `sub_caste` is a NULLABLE column and
/// the gate in [PostAuthDestination] does not test it, so requiring it would
/// block a member on a field the router will happily wave them past.
class ProfileBasicsForm {
  /// Draft: `LocationDetails.state`. Required.
  final String state;

  /// Draft: `LocationDetails.city`. Required.
  final String city;

  /// Draft: `ReligionDetails.subCaste`. Optional — see the class doc.
  final String subCommunity;

  const ProfileBasicsForm({
    this.state = '',
    this.city = '',
    this.subCommunity = '',
  });

  ProfileBasicsForm copyWith({
    String? state,
    String? city,
    String? subCommunity,
  }) {
    return ProfileBasicsForm(
      state: state ?? this.state,
      city: city ?? this.city,
      subCommunity: subCommunity ?? this.subCommunity,
    );
  }

  List<ProfileBasicsField> get missingFields => [
        if (state.trim().isEmpty) ProfileBasicsField.state,
        if (city.trim().isEmpty) ProfileBasicsField.city,
      ];

  bool get isComplete => missingFields.isEmpty;
}

/// The required fields of [ProfileBasicsForm], for validation messages.
/// Sub-community is absent because it is optional.
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
