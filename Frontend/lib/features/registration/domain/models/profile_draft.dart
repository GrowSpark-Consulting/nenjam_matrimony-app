/// Nenjam Matrimony — Profile Draft Domain Models
///
/// Immutable data classes for the 13-step registration wizard.
/// Plain Dart — no Flutter dependency, no code generation required.
///
/// Step 10 (Psychological Quiz) intentionally has no domain class here —
/// its answers/result are owned by the psychology feature
/// (features/psychology/domain/models, PersonalityRepository) and fetched
/// live via myPersonalityResultProvider, so the wizard step reads that
/// shared state instead of duplicating it into the draft.
library;

import '../../../../core/utils/birth_date.dart';
import '../../../partner_preferences/domain/models/partner_preference_extended.dart';

/// Reads a nested JSON object safely — the draft endpoint omits keys for
/// sections the user hasn't reached yet.
Map<String, dynamic> _section(Map<String, dynamic> data, String key) {
  final value = data[key];
  return value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};
}

List<String> _stringList(dynamic value) =>
    value is List ? value.map((e) => e.toString()).toList() : const [];

/// The literal string "Other" is never a valid, complete answer — it's
/// [OtherOptionField]'s chip-selection placeholder for fields with a custom
/// "Other" option (religion, country, state, qualification, occupation,
/// disability, annual income). The widget itself never emits this literal
/// value once wired correctly (selecting "Other" with no custom text yet
/// emits `''`), but every `isComplete`/`isValid` getter below checks through
/// this helper as the authoritative, single-point guard.
bool _hasValue(String value) => value.isNotEmpty && value != 'Other';

/// Reverses [BasicDetails._toEnumValue] — maps a backend enum value
/// ("MALE", "NEVER_MARRIED") back to this app's display value ("Male",
/// "Never Married"). Falls back to the raw value for anything unmapped.
String _fromEnumValue(String? raw, Map<String, String> reverseMap) {
  if (raw == null || raw.isEmpty) return '';
  return reverseMap[raw] ?? raw;
}

// ─── Basic Details (Step 1) ──────────────────────────────────────────
class BasicDetails {
  final String firstName;
  final String lastName;
  final String gender;
  final DateTime? dob;
  final String maritalStatus;

  /// Who the profile is being created for ('Myself', 'Son', ...).
  ///
  /// Empty means **the user has not chosen yet** — it is deliberately not
  /// defaulted to 'Myself'. CreateProfileForPage is the only writer, and
  /// routing (see PostAuthDestination.resolve) sends anyone whose value is
  /// still empty to that screen. A non-empty default would be
  /// indistinguishable from a real answer, which is exactly how a
  /// brand-new user used to skip the question and silently register as
  /// 'Myself'. `toJson` omits the field while it is empty, so an unset
  /// value is never sent to the backend as a choice either.
  final String profileCreatedFor;

  const BasicDetails({
    this.firstName = '',
    this.lastName = '',
    this.gender = '',
    this.dob,
    this.maritalStatus = '',
    this.profileCreatedFor = '',
  });

  /// Whole years old today, or null with no date of birth. Delegates to the
  /// one age calculation in the app rather than restating the
  /// birthday-not-yet-reached decrement a fourth time.
  int? get age => dob == null ? null : ageInYears(dob!);

  BasicDetails copyWith({
    String? firstName,
    String? lastName,
    String? gender,
    DateTime? dob,
    String? maritalStatus,
    String? profileCreatedFor,
  }) {
    return BasicDetails(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      gender: gender ?? this.gender,
      dob: dob ?? this.dob,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      profileCreatedFor: profileCreatedFor ?? this.profileCreatedFor,
    );
  }

  /// Maps this screen's display values ("Male", "Never Married") to the
  /// backend's enum values ("MALE", "NEVER_MARRIED") — see
  /// backend/apps/api/src/modules/profiles/dto/basic-details.dto.ts.
  static String _toEnumValue(String value) =>
      value.toUpperCase().replaceAll(' ', '_');

  static const _genderReverseMap = {'MALE': 'Male', 'FEMALE': 'Female'};
  static const _maritalStatusReverseMap = {
    'NEVER_MARRIED': 'Never Married',
    'DIVORCED': 'Divorced',
    'WIDOWED': 'Widowed',
    'AWAITING_DIVORCE': 'Awaiting Divorce',
  };

  factory BasicDetails.fromJson(Map<String, dynamic> json) => BasicDetails(
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        gender: _fromEnumValue(json['gender'] as String?, _genderReverseMap),
        // A calendar date, read for the date it names — never converted to
        // local time, which is how a birthdate loses a day either side of
        // midnight. Tolerates the ISO-8601 timestamps older builds wrote.
        dob: birthDateFromWire(json['dob']),
        maritalStatus: _fromEnumValue(
            json['maritalStatus'] as String?, _maritalStatusReverseMap),
        // Absent means the backend has never been told a choice — keep it
        // empty so the router can tell that apart from a real answer.
        profileCreatedFor: json['profileCreatedFor'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        if (firstName.isNotEmpty) 'firstName': firstName,
        if (lastName.isNotEmpty) 'lastName': lastName,
        if (gender.isNotEmpty) 'gender': _toEnumValue(gender),
        // `YYYY-MM-DD`: a date of birth has no time of day and no zone, and
        // sending one as a timestamp is what let the stored date drift by a
        // day. Matches BasicDetailsDto.dob on the server.
        if (dob != null) 'dob': birthDateToWire(dob!),
        if (maritalStatus.isNotEmpty)
          'maritalStatus': _toEnumValue(maritalStatus),
        if (profileCreatedFor.isNotEmpty)
          'profileCreatedFor': profileCreatedFor,
      };

  /// Step 1 is not skippable — every field is required. Mirrors
  /// backend/apps/api/src/modules/profiles/validation/registration-rules.ts
  /// -> isBasicDetailsComplete().
  bool get isComplete =>
      firstName.isNotEmpty &&
      lastName.isNotEmpty &&
      gender.isNotEmpty &&
      maritalStatus.isNotEmpty &&
      profileCreatedFor.isNotEmpty &&
      dob != null;
}

// ─── Religion Details (Step 2) ───────────────────────────────────────
class ReligionDetails {
  final String religion;
  final String caste;
  final String subCaste;
  final String gothra;
  final String denomination;
  final String community;

  const ReligionDetails({
    this.religion = '',
    this.caste = '',
    this.subCaste = '',
    this.gothra = '',
    this.denomination = '',
    this.community = '',
  });

  ReligionDetails copyWith({
    String? religion,
    String? caste,
    String? subCaste,
    String? gothra,
    String? denomination,
    String? community,
  }) {
    return ReligionDetails(
      religion: religion ?? this.religion,
      caste: caste ?? this.caste,
      subCaste: subCaste ?? this.subCaste,
      gothra: gothra ?? this.gothra,
      denomination: denomination ?? this.denomination,
      community: community ?? this.community,
    );
  }

  factory ReligionDetails.fromJson(Map<String, dynamic> json) =>
      ReligionDetails(
        religion: json['religion'] as String? ?? '',
        caste: json['caste'] as String? ?? '',
        subCaste: json['subCaste'] as String? ?? '',
        gothra: json['gothra'] as String? ?? '',
        denomination: json['denomination'] as String? ?? '',
        community: json['community'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        if (religion.isNotEmpty) 'religion': religion,
        if (caste.isNotEmpty) 'caste': caste,
        if (subCaste.isNotEmpty) 'subCaste': subCaste,
        if (gothra.isNotEmpty) 'gothra': gothra,
        if (denomination.isNotEmpty) 'denomination': denomination,
        if (community.isNotEmpty) 'community': community,
      };

  /// Step 2 is not skippable — religion, caste, sub caste, and community are
  /// required; the rest (gothra, denomination) stay optional.
  bool get isComplete =>
      _hasValue(religion) &&
      caste.isNotEmpty &&
      subCaste.isNotEmpty &&
      community.isNotEmpty;
}

// ─── Language Details (Step 3) ───────────────────────────────────────
class LanguageDetails {
  final String motherTongue;
  final List<String> languagesKnown;

  const LanguageDetails({
    this.motherTongue = '',
    this.languagesKnown = const [],
  });

  LanguageDetails copyWith({
    String? motherTongue,
    List<String>? languagesKnown,
  }) {
    return LanguageDetails(
      motherTongue: motherTongue ?? this.motherTongue,
      languagesKnown: languagesKnown ?? this.languagesKnown,
    );
  }

  factory LanguageDetails.fromJson(Map<String, dynamic> json) =>
      LanguageDetails(
        motherTongue: json['motherTongue'] as String? ?? '',
        languagesKnown: _stringList(json['languagesKnown']),
      );

  Map<String, dynamic> toJson() => {
        if (motherTongue.isNotEmpty) 'motherTongue': motherTongue,
        if (languagesKnown.isNotEmpty) 'languagesKnown': languagesKnown,
      };

  /// Step 3 is not skippable — every field is required.
  bool get isComplete => motherTongue.isNotEmpty && languagesKnown.isNotEmpty;
}

// ─── Location Details (Step 4) ───────────────────────────────────────
class LocationDetails {
  final String country;
  final String state;
  final String city;
  final String area;
  final String pinCode;
  final String nativePlace;

  const LocationDetails({
    this.country = 'India',
    this.state = '',
    this.city = '',
    this.area = '',
    this.pinCode = '',
    this.nativePlace = '',
  });

  LocationDetails copyWith({
    String? country,
    String? state,
    String? city,
    String? area,
    String? pinCode,
    String? nativePlace,
  }) {
    return LocationDetails(
      country: country ?? this.country,
      state: state ?? this.state,
      city: city ?? this.city,
      area: area ?? this.area,
      pinCode: pinCode ?? this.pinCode,
      nativePlace: nativePlace ?? this.nativePlace,
    );
  }

  factory LocationDetails.fromJson(Map<String, dynamic> json) =>
      LocationDetails(
        country: json['country'] as String? ?? 'India',
        state: json['state'] as String? ?? '',
        city: json['city'] as String? ?? '',
        area: json['area'] as String? ?? '',
        pinCode: json['pinCode'] as String? ?? '',
        nativePlace: json['nativePlace'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        if (country.isNotEmpty) 'country': country,
        if (state.isNotEmpty) 'state': state,
        if (city.isNotEmpty) 'city': city,
        if (area.isNotEmpty) 'area': area,
        if (pinCode.isNotEmpty) 'pinCode': pinCode,
        if (nativePlace.isNotEmpty) 'nativePlace': nativePlace,
      };

  /// Step 4 is not skippable — every field is required.
  bool get isComplete =>
      _hasValue(country) &&
      _hasValue(state) &&
      city.isNotEmpty &&
      area.isNotEmpty &&
      pinCode.isNotEmpty &&
      nativePlace.isNotEmpty;
}

// ─── Education Details (Step 5) ──────────────────────────────────────
class EducationDetails {
  final String qualification;
  final String college;
  final String occupation;
  final String company;
  final String employmentType;
  final String annualIncome;
  final String workLocation;

  const EducationDetails({
    this.qualification = '',
    this.college = '',
    this.occupation = '',
    this.company = '',
    this.employmentType = '',
    this.annualIncome = '',
    this.workLocation = '',
  });

  EducationDetails copyWith({
    String? qualification,
    String? college,
    String? occupation,
    String? company,
    String? employmentType,
    String? annualIncome,
    String? workLocation,
  }) {
    return EducationDetails(
      qualification: qualification ?? this.qualification,
      college: college ?? this.college,
      occupation: occupation ?? this.occupation,
      company: company ?? this.company,
      employmentType: employmentType ?? this.employmentType,
      annualIncome: annualIncome ?? this.annualIncome,
      workLocation: workLocation ?? this.workLocation,
    );
  }

  factory EducationDetails.fromJson(Map<String, dynamic> json) =>
      EducationDetails(
        qualification: json['qualification'] as String? ?? '',
        college: json['college'] as String? ?? '',
        occupation: json['occupation'] as String? ?? '',
        company: json['company'] as String? ?? '',
        employmentType: json['employmentType'] as String? ?? '',
        annualIncome: json['annualIncome'] as String? ?? '',
        workLocation: json['workLocation'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        if (qualification.isNotEmpty) 'qualification': qualification,
        if (college.isNotEmpty) 'college': college,
        if (occupation.isNotEmpty) 'occupation': occupation,
        if (company.isNotEmpty) 'company': company,
        if (employmentType.isNotEmpty) 'employmentType': employmentType,
        if (annualIncome.isNotEmpty) 'annualIncome': annualIncome,
        if (workLocation.isNotEmpty) 'workLocation': workLocation,
      };

  /// Step 5 is skippable, but once the user engages with any field, every
  /// field is required — see registration-rules.ts's isEducationDetailsValid.
  bool get isTouched =>
      qualification.isNotEmpty ||
      college.isNotEmpty ||
      occupation.isNotEmpty ||
      company.isNotEmpty ||
      employmentType.isNotEmpty ||
      annualIncome.isNotEmpty ||
      workLocation.isNotEmpty;

  bool get isValid =>
      !isTouched ||
      (_hasValue(qualification) &&
          college.isNotEmpty &&
          _hasValue(occupation) &&
          company.isNotEmpty &&
          employmentType.isNotEmpty &&
          _hasValue(annualIncome) &&
          workLocation.isNotEmpty);
}

// ─── Physical Details (Step 6) ───────────────────────────────────────
// Body Type and Complexion were removed from the product — do not
// reintroduce them here or in any DTO/UI.
class PhysicalDetails {
  final String height;
  final String weight;
  final String bloodGroup;
  final String disability;

  const PhysicalDetails({
    this.height = '',
    this.weight = '',
    this.bloodGroup = '',
    this.disability = 'None',
  });

  PhysicalDetails copyWith({
    String? height,
    String? weight,
    String? bloodGroup,
    String? disability,
  }) {
    return PhysicalDetails(
      height: height ?? this.height,
      weight: weight ?? this.weight,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      disability: disability ?? this.disability,
    );
  }

  factory PhysicalDetails.fromJson(Map<String, dynamic> json) =>
      PhysicalDetails(
        height: json['height'] as String? ?? '',
        weight: json['weight'] as String? ?? '',
        bloodGroup: json['bloodGroup'] as String? ?? '',
        disability: json['disability'] as String? ?? 'None',
      );

  Map<String, dynamic> toJson() => {
        if (height.isNotEmpty) 'height': height,
        if (weight.isNotEmpty) 'weight': weight,
        if (bloodGroup.isNotEmpty) 'bloodGroup': bloodGroup,
        if (disability.isNotEmpty) 'disability': disability,
      };

  /// Step 6 is skippable, but once the user engages with any field, height,
  /// weight, and disability are all required (blood group stays optional).
  /// `disability` defaults to `'None'` (always non-empty), so touched-ness is
  /// judged only by height/weight — see registration-rules.ts's
  /// isPhysicalSectionTouched.
  bool get isComplete =>
      height.isNotEmpty && weight.isNotEmpty && _hasValue(disability);

  bool get isTouched => height.isNotEmpty || weight.isNotEmpty;

  bool get isValid => !isTouched || isComplete;
}

// ─── Lifestyle Details (Step 7) ──────────────────────────────────────
class LifestyleDetails {
  final String eatingHabit;
  final String smoking;
  final String drinking;
  final String fitness;
  final List<String> hobbies;
  final String aboutMe;

  const LifestyleDetails({
    this.eatingHabit = '',
    this.smoking = '',
    this.drinking = '',
    this.fitness = '',
    this.hobbies = const [],
    this.aboutMe = '',
  });

  LifestyleDetails copyWith({
    String? eatingHabit,
    String? smoking,
    String? drinking,
    String? fitness,
    List<String>? hobbies,
    String? aboutMe,
  }) {
    return LifestyleDetails(
      eatingHabit: eatingHabit ?? this.eatingHabit,
      smoking: smoking ?? this.smoking,
      drinking: drinking ?? this.drinking,
      fitness: fitness ?? this.fitness,
      hobbies: hobbies ?? this.hobbies,
      aboutMe: aboutMe ?? this.aboutMe,
    );
  }

  factory LifestyleDetails.fromJson(Map<String, dynamic> json) =>
      LifestyleDetails(
        eatingHabit: json['eatingHabit'] as String? ?? '',
        smoking: json['smoking'] as String? ?? '',
        drinking: json['drinking'] as String? ?? '',
        fitness: json['fitness'] as String? ?? '',
        hobbies: _stringList(json['hobbies']),
        aboutMe: json['aboutMe'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        if (eatingHabit.isNotEmpty) 'eatingHabit': eatingHabit,
        if (smoking.isNotEmpty) 'smoking': smoking,
        if (drinking.isNotEmpty) 'drinking': drinking,
        if (fitness.isNotEmpty) 'fitness': fitness,
        if (hobbies.isNotEmpty) 'hobbies': hobbies,
        if (aboutMe.isNotEmpty) 'aboutMe': aboutMe,
      };

  /// Step 7 is skippable, but once the user engages with any field, every
  /// field is required — see registration-rules.ts's isLifestyleDetailsValid.
  bool get isTouched =>
      eatingHabit.isNotEmpty ||
      smoking.isNotEmpty ||
      drinking.isNotEmpty ||
      fitness.isNotEmpty ||
      hobbies.isNotEmpty ||
      aboutMe.isNotEmpty;

  bool get isValid =>
      !isTouched ||
      (eatingHabit.isNotEmpty &&
          smoking.isNotEmpty &&
          drinking.isNotEmpty &&
          fitness.isNotEmpty &&
          hobbies.isNotEmpty &&
          aboutMe.isNotEmpty);
}

// ─── Family Details (Step 8) ─────────────────────────────────────────

/// A single family member's name/age/occupation — used for Father and
/// Mother in [FamilyDetails]. Step 8 has no required-if-filled rule (unlike
/// Education/Lifestyle), so partially-filled members are fine.
class FamilyMember {
  final String name;
  final int? age;
  final String occupation;

  const FamilyMember({this.name = '', this.age, this.occupation = ''});

  bool get isEmpty => name.isEmpty && age == null && occupation.isEmpty;

  FamilyMember copyWith({String? name, int? age, String? occupation}) {
    return FamilyMember(
      name: name ?? this.name,
      age: age ?? this.age,
      occupation: occupation ?? this.occupation,
    );
  }

  factory FamilyMember.fromJson(Map<String, dynamic> json) => FamilyMember(
        name: json['name'] as String? ?? '',
        age: (json['age'] as num?)?.toInt(),
        occupation: json['occupation'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        if (name.isNotEmpty) 'name': name,
        if (age != null) 'age': age,
        if (occupation.isNotEmpty) 'occupation': occupation,
      };
}

enum SiblingRelation { brother, sister }

/// A single dynamically-added sibling row (Step 8's Brothers/Sisters list).
class SiblingMember {
  final SiblingRelation relation;
  final String name;
  final int? age;
  final String occupation;

  const SiblingMember({
    this.relation = SiblingRelation.brother,
    this.name = '',
    this.age,
    this.occupation = '',
  });

  SiblingMember copyWith({
    SiblingRelation? relation,
    String? name,
    int? age,
    String? occupation,
  }) {
    return SiblingMember(
      relation: relation ?? this.relation,
      name: name ?? this.name,
      age: age ?? this.age,
      occupation: occupation ?? this.occupation,
    );
  }

  factory SiblingMember.fromJson(Map<String, dynamic> json) => SiblingMember(
        relation: (json['relation'] as String?) == 'SISTER'
            ? SiblingRelation.sister
            : SiblingRelation.brother,
        name: json['name'] as String? ?? '',
        age: (json['age'] as num?)?.toInt(),
        occupation: json['occupation'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'relation':
            relation == SiblingRelation.sister ? 'SISTER' : 'BROTHER',
        if (name.isNotEmpty) 'name': name,
        if (age != null) 'age': age,
        if (occupation.isNotEmpty) 'occupation': occupation,
      };
}

class FamilyDetails {
  final FamilyMember father;
  final FamilyMember mother;
  final List<SiblingMember> siblings;
  final String familyType;
  final String familyValues;
  final String familyStatus;

  const FamilyDetails({
    this.father = const FamilyMember(),
    this.mother = const FamilyMember(),
    this.siblings = const [],
    this.familyType = '',
    this.familyValues = '',
    this.familyStatus = '',
  });

  FamilyDetails copyWith({
    FamilyMember? father,
    FamilyMember? mother,
    List<SiblingMember>? siblings,
    String? familyType,
    String? familyValues,
    String? familyStatus,
  }) {
    return FamilyDetails(
      father: father ?? this.father,
      mother: mother ?? this.mother,
      siblings: siblings ?? this.siblings,
      familyType: familyType ?? this.familyType,
      familyValues: familyValues ?? this.familyValues,
      familyStatus: familyStatus ?? this.familyStatus,
    );
  }

  factory FamilyDetails.fromJson(Map<String, dynamic> json) => FamilyDetails(
        father: json['father'] is Map
            ? FamilyMember.fromJson(
                (json['father'] as Map<dynamic, dynamic>).cast<String, dynamic>())
            : const FamilyMember(),
        mother: json['mother'] is Map
            ? FamilyMember.fromJson(
                (json['mother'] as Map<dynamic, dynamic>).cast<String, dynamic>())
            : const FamilyMember(),
        siblings: json['siblings'] is List
            ? (json['siblings'] as List)
                .whereType<Map<dynamic, dynamic>>()
                .map((e) => SiblingMember.fromJson(e.cast<String, dynamic>()))
                .toList()
            : const [],
        familyType: json['familyType'] as String? ?? '',
        familyValues: json['familyValues'] as String? ?? '',
        familyStatus: json['familyStatus'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        if (!father.isEmpty) 'father': father.toJson(),
        if (!mother.isEmpty) 'mother': mother.toJson(),
        if (siblings.isNotEmpty)
          'siblings': siblings.map((s) => s.toJson()).toList(),
        if (familyType.isNotEmpty) 'familyType': familyType,
        if (familyValues.isNotEmpty) 'familyValues': familyValues,
        if (familyStatus.isNotEmpty) 'familyStatus': familyStatus,
      };
}

// ─── Horoscope Details (Step 9) ──────────────────────────────────────
class HoroscopeDetails {
  final String birthTime;
  final String birthPlace;
  final String rashi;
  final String nakshatra;
  final String star;
  final String manglik;
  final String dosham;
  final bool horoscopeAvailable;

  const HoroscopeDetails({
    this.birthTime = '',
    this.birthPlace = '',
    this.rashi = '',
    this.nakshatra = '',
    this.star = '',
    this.manglik = '',
    this.dosham = '',
    this.horoscopeAvailable = false,
  });

  HoroscopeDetails copyWith({
    String? birthTime,
    String? birthPlace,
    String? rashi,
    String? nakshatra,
    String? star,
    String? manglik,
    String? dosham,
    bool? horoscopeAvailable,
  }) {
    return HoroscopeDetails(
      birthTime: birthTime ?? this.birthTime,
      birthPlace: birthPlace ?? this.birthPlace,
      rashi: rashi ?? this.rashi,
      nakshatra: nakshatra ?? this.nakshatra,
      star: star ?? this.star,
      manglik: manglik ?? this.manglik,
      dosham: dosham ?? this.dosham,
      horoscopeAvailable: horoscopeAvailable ?? this.horoscopeAvailable,
    );
  }

  factory HoroscopeDetails.fromJson(Map<String, dynamic> json) =>
      HoroscopeDetails(
        birthTime: json['birthTime'] as String? ?? '',
        birthPlace: json['birthPlace'] as String? ?? '',
        rashi: json['rashi'] as String? ?? '',
        nakshatra: json['nakshatra'] as String? ?? '',
        star: json['star'] as String? ?? '',
        manglik: json['manglik'] as String? ?? '',
        dosham: json['dosham'] as String? ?? '',
        horoscopeAvailable: json['horoscopeAvailable'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        if (birthTime.isNotEmpty) 'birthTime': birthTime,
        if (birthPlace.isNotEmpty) 'birthPlace': birthPlace,
        if (rashi.isNotEmpty) 'rashi': rashi,
        if (nakshatra.isNotEmpty) 'nakshatra': nakshatra,
        if (star.isNotEmpty) 'star': star,
        if (manglik.isNotEmpty) 'manglik': manglik,
        if (dosham.isNotEmpty) 'dosham': dosham,
        'horoscopeAvailable': horoscopeAvailable,
      };

  /// Step 9 is skippable, but once any horoscope field is filled, Rashi
  /// becomes required — see registration-rules.ts's isHoroscopeDetailsValid.
  bool get isTouched =>
      birthTime.isNotEmpty ||
      birthPlace.isNotEmpty ||
      rashi.isNotEmpty ||
      nakshatra.isNotEmpty ||
      star.isNotEmpty ||
      manglik.isNotEmpty ||
      dosham.isNotEmpty ||
      horoscopeAvailable;

  bool get isValid => !isTouched || rashi.isNotEmpty;
}

// ─── Partner Preference (Step 11) ────────────────────────────────────
class PartnerPreference {
  final String preferredAgeRange;
  final String preferredHeightRange;
  final String religionPref;
  final String castePref;
  final String educationPref;
  final String occupationPref;
  final String incomePref;
  final String locationPref;
  final String motherTonguePref;
  final String maritalStatusPref;

  /// Advanced fields (religion/community, education/career, family,
  /// lifestyle, location, special cases, verification filters) edited from
  /// the standalone Partner Preferences page — see
  /// features/partner_preferences. Kept nested so the 10 base fields above,
  /// and every existing call site that constructs a [PartnerPreference],
  /// stay untouched.
  final PartnerPreferenceExtended extended;

  const PartnerPreference({
    this.preferredAgeRange = '',
    this.preferredHeightRange = '',
    this.religionPref = '',
    this.castePref = '',
    this.educationPref = '',
    this.occupationPref = '',
    this.incomePref = '',
    this.locationPref = '',
    this.motherTonguePref = '',
    this.maritalStatusPref = '',
    this.extended = const PartnerPreferenceExtended(),
  });

  PartnerPreference copyWith({
    String? preferredAgeRange,
    String? preferredHeightRange,
    String? religionPref,
    String? castePref,
    String? educationPref,
    String? occupationPref,
    String? incomePref,
    String? locationPref,
    String? motherTonguePref,
    String? maritalStatusPref,
    PartnerPreferenceExtended? extended,
  }) {
    return PartnerPreference(
      preferredAgeRange: preferredAgeRange ?? this.preferredAgeRange,
      preferredHeightRange: preferredHeightRange ?? this.preferredHeightRange,
      religionPref: religionPref ?? this.religionPref,
      castePref: castePref ?? this.castePref,
      educationPref: educationPref ?? this.educationPref,
      occupationPref: occupationPref ?? this.occupationPref,
      incomePref: incomePref ?? this.incomePref,
      locationPref: locationPref ?? this.locationPref,
      motherTonguePref: motherTonguePref ?? this.motherTonguePref,
      maritalStatusPref: maritalStatusPref ?? this.maritalStatusPref,
      extended: extended ?? this.extended,
    );
  }

  factory PartnerPreference.fromJson(Map<String, dynamic> json) =>
      PartnerPreference(
        preferredAgeRange: json['preferredAgeRange'] as String? ?? '',
        preferredHeightRange: json['preferredHeightRange'] as String? ?? '',
        religionPref: json['religionPref'] as String? ?? '',
        castePref: json['castePref'] as String? ?? '',
        educationPref: json['educationPref'] as String? ?? '',
        occupationPref: json['occupationPref'] as String? ?? '',
        incomePref: json['incomePref'] as String? ?? '',
        locationPref: json['locationPref'] as String? ?? '',
        motherTonguePref: json['motherTonguePref'] as String? ?? '',
        maritalStatusPref: json['maritalStatusPref'] as String? ?? '',
        extended: PartnerPreferenceExtended.fromJson(
          (json['extended'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );

  Map<String, dynamic> toJson() => {
        if (preferredAgeRange.isNotEmpty)
          'preferredAgeRange': preferredAgeRange,
        if (preferredHeightRange.isNotEmpty)
          'preferredHeightRange': preferredHeightRange,
        if (religionPref.isNotEmpty) 'religionPref': religionPref,
        if (castePref.isNotEmpty) 'castePref': castePref,
        if (educationPref.isNotEmpty) 'educationPref': educationPref,
        if (occupationPref.isNotEmpty) 'occupationPref': occupationPref,
        if (incomePref.isNotEmpty) 'incomePref': incomePref,
        if (locationPref.isNotEmpty) 'locationPref': locationPref,
        if (motherTonguePref.isNotEmpty) 'motherTonguePref': motherTonguePref,
        if (maritalStatusPref.isNotEmpty)
          'maritalStatusPref': maritalStatusPref,
        if (!extended.isEmpty) 'extended': extended.toJson(),
      };

  /// Step 11 is skippable — used only to switch the entry-point card's
  /// copy/button label between "Set" and "Edit" (see
  /// PartnerPreferenceStepCard). Never gates Continue.
  bool get hasAnyPreference =>
      preferredAgeRange.isNotEmpty ||
      preferredHeightRange.isNotEmpty ||
      religionPref.isNotEmpty ||
      castePref.isNotEmpty ||
      educationPref.isNotEmpty ||
      occupationPref.isNotEmpty ||
      incomePref.isNotEmpty ||
      locationPref.isNotEmpty ||
      motherTonguePref.isNotEmpty ||
      maritalStatusPref.isNotEmpty ||
      !extended.isEmpty;
}

// ─── Photo Gallery (Step 12) ─────────────────────────────────────────
class PhotoGallery {
  final String? primaryPhotoPath;
  final List<String> galleryPaths;

  const PhotoGallery({
    this.primaryPhotoPath,
    this.galleryPaths = const [],
  });

  /// Sentinel meaning "argument not supplied", so a caller can pass an
  /// explicit `null` and have it stick.
  ///
  /// With the usual `primaryPhotoPath ?? this.primaryPhotoPath`, null is
  /// indistinguishable from omitted, so there is no way to clear the primary
  /// slot — `copyWith(primaryPhotoPath: null)` silently keeps the old path.
  /// That matters now the queue is drained one entry at a time: a primary
  /// that uploaded successfully has to be removable while the rest stay.
  static const Object _unset = Object();

  PhotoGallery copyWith({
    Object? primaryPhotoPath = _unset,
    List<String>? galleryPaths,
  }) {
    return PhotoGallery(
      primaryPhotoPath: identical(primaryPhotoPath, _unset)
          ? this.primaryPhotoPath
          : primaryPhotoPath as String?,
      galleryPaths: galleryPaths ?? this.galleryPaths,
    );
  }

  /// Local file paths waiting to be uploaded, primary first.
  ///
  /// Onboarding's Add Photos step runs before the member has a credential, so
  /// a photo picked there is held here until OTP mints a session and
  /// OnboardingVerifyMobilePage uploads it through PhotosController. Order
  /// matters: the first one becomes the avatar.
  List<String> get pendingPaths => [
        if (primaryPhotoPath != null) primaryPhotoPath!,
        ...galleryPaths,
      ];

  // Not part of the /profiles/draft response (photos are handled by
  // PhotoController) — kept for forward-compatibility with ProfileDraft.
  factory PhotoGallery.fromJson(Map<String, dynamic> json) => PhotoGallery(
        primaryPhotoPath: json['primaryPhotoPath'] as String?,
        galleryPaths: _stringList(json['galleryPaths']),
      );

  Map<String, dynamic> toJson() => {
        if (primaryPhotoPath != null) 'primaryPhotoPath': primaryPhotoPath,
        if (galleryPaths.isNotEmpty) 'galleryPaths': galleryPaths,
      };
}

// ─── Verification Status (Step 13) ───────────────────────────────────
//
// Mirrors, rather than owns, the real signals from elsewhere: mobileVerified/
// emailVerified reflect the Firebase auth session (AuthUser.phoneVerified/
// .emailVerified), and incomeVerified/assetVerified/aadhaarVerified/
// nriVerified reflect the independent document-verification resource (see
// features/verification — VerificationRepository/verificationStatusesProvider)
// once the backend reports a document as VERIFIED. Nothing here is ever
// set to true just because a document was *submitted* — only an actual
// VERIFIED status from the backend flips these. faceVerified/govIdVerified
// are kept for the shared Verification Center badges elsewhere in the app
// (features/profile's NmVerificationCard, features/verification's
// VerificationPage) that still read them — see step_verification.dart's
// header comment for why the registration step itself no longer sets
// faceVerified.
class VerificationStatus {
  final bool mobileVerified;
  final bool emailVerified;
  final bool faceVerified;
  final bool aadhaarVerified;
  final bool govIdVerified;
  final bool incomeVerified;
  final bool assetVerified;
  final bool nriVerified;

  const VerificationStatus({
    this.mobileVerified = false,
    this.emailVerified = false,
    this.faceVerified = false,
    this.aadhaarVerified = false,
    this.govIdVerified = false,
    this.incomeVerified = false,
    this.assetVerified = false,
    this.nriVerified = false,
  });

  VerificationStatus copyWith({
    bool? mobileVerified,
    bool? emailVerified,
    bool? faceVerified,
    bool? aadhaarVerified,
    bool? govIdVerified,
    bool? incomeVerified,
    bool? assetVerified,
    bool? nriVerified,
  }) {
    return VerificationStatus(
      mobileVerified: mobileVerified ?? this.mobileVerified,
      emailVerified: emailVerified ?? this.emailVerified,
      faceVerified: faceVerified ?? this.faceVerified,
      aadhaarVerified: aadhaarVerified ?? this.aadhaarVerified,
      govIdVerified: govIdVerified ?? this.govIdVerified,
      incomeVerified: incomeVerified ?? this.incomeVerified,
      assetVerified: assetVerified ?? this.assetVerified,
      nriVerified: nriVerified ?? this.nriVerified,
    );
  }

  // Not part of the /profiles/draft response — there is no verification
  // status endpoint yet (see backend/apps/api/src/modules/verification,
  // currently a stub). Defaults preserve today's behavior (mobile
  // auto-verified at signup/login) until that module is implemented.
  factory VerificationStatus.fromJson(Map<String, dynamic> json) =>
      VerificationStatus(
        mobileVerified: json['mobileVerified'] as bool? ?? true,
        emailVerified: json['emailVerified'] as bool? ?? false,
        faceVerified: json['faceVerified'] as bool? ?? false,
        aadhaarVerified: json['aadhaarVerified'] as bool? ?? false,
        govIdVerified: json['govIdVerified'] as bool? ?? false,
        incomeVerified: json['incomeVerified'] as bool? ?? false,
        assetVerified: json['assetVerified'] as bool? ?? false,
        nriVerified: json['nriVerified'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'mobileVerified': mobileVerified,
        'emailVerified': emailVerified,
        'faceVerified': faceVerified,
        'aadhaarVerified': aadhaarVerified,
        'govIdVerified': govIdVerified,
        'incomeVerified': incomeVerified,
        'assetVerified': assetVerified,
        'nriVerified': nriVerified,
      };
}

// ─── Profile Draft (Aggregate Root) ──────────────────────────────────
class ProfileDraft {
  final BasicDetails basicDetails;
  final ReligionDetails religionDetails;
  final LanguageDetails languageDetails;
  final LocationDetails locationDetails;
  final EducationDetails educationDetails;
  final PhysicalDetails physicalDetails;
  final LifestyleDetails lifestyleDetails;
  final FamilyDetails familyDetails;
  final HoroscopeDetails horoscopeDetails;
  final PartnerPreference partnerPreference;
  final PhotoGallery photoGallery;
  final VerificationStatus verificationStatus;
  final int currentStep;

  const ProfileDraft({
    this.basicDetails = const BasicDetails(),
    this.religionDetails = const ReligionDetails(),
    this.languageDetails = const LanguageDetails(),
    this.locationDetails = const LocationDetails(),
    this.educationDetails = const EducationDetails(),
    this.physicalDetails = const PhysicalDetails(),
    this.lifestyleDetails = const LifestyleDetails(),
    this.familyDetails = const FamilyDetails(),
    this.horoscopeDetails = const HoroscopeDetails(),
    this.partnerPreference = const PartnerPreference(),
    this.photoGallery = const PhotoGallery(),
    this.verificationStatus = const VerificationStatus(),
    this.currentStep = 0,
  });

  static const int totalSteps = 13;

  /// Hydrates a draft from `GET /profiles/draft`'s response shape:
  /// `{ currentStep, totalSteps, completedSteps, isComplete,
  ///   completionPercentage, data: { basicDetails: {...}, ... } }`.
  /// Also accepts a bare `data` map directly, for flexibility.
  factory ProfileDraft.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? (json['data'] as Map).cast<String, dynamic>()
        : json;
    return ProfileDraft(
      basicDetails: BasicDetails.fromJson(_section(data, 'basicDetails')),
      religionDetails:
          ReligionDetails.fromJson(_section(data, 'religionDetails')),
      languageDetails:
          LanguageDetails.fromJson(_section(data, 'languageDetails')),
      locationDetails:
          LocationDetails.fromJson(_section(data, 'locationDetails')),
      educationDetails:
          EducationDetails.fromJson(_section(data, 'educationDetails')),
      physicalDetails:
          PhysicalDetails.fromJson(_section(data, 'physicalDetails')),
      lifestyleDetails:
          LifestyleDetails.fromJson(_section(data, 'lifestyleDetails')),
      familyDetails: FamilyDetails.fromJson(_section(data, 'familyDetails')),
      horoscopeDetails:
          HoroscopeDetails.fromJson(_section(data, 'horoscopeDetails')),
      partnerPreference:
          PartnerPreference.fromJson(_section(data, 'partnerPreference')),
      photoGallery: PhotoGallery.fromJson(_section(data, 'photoGallery')),
      verificationStatus:
          VerificationStatus.fromJson(_section(data, 'verificationStatus')),
    );
  }

  Map<String, dynamic> toJson() => {
        'basicDetails': basicDetails.toJson(),
        'religionDetails': religionDetails.toJson(),
        'languageDetails': languageDetails.toJson(),
        'locationDetails': locationDetails.toJson(),
        'educationDetails': educationDetails.toJson(),
        'physicalDetails': physicalDetails.toJson(),
        'lifestyleDetails': lifestyleDetails.toJson(),
        'familyDetails': familyDetails.toJson(),
        'horoscopeDetails': horoscopeDetails.toJson(),
        'partnerPreference': partnerPreference.toJson(),
        'photoGallery': photoGallery.toJson(),
        'verificationStatus': verificationStatus.toJson(),
      };

  double get completionPercentage {
    int filled = 0;
    int total = 0;

    // Basic (6 fields)
    total += 6;
    if (basicDetails.firstName.isNotEmpty) filled++;
    if (basicDetails.lastName.isNotEmpty) filled++;
    if (basicDetails.gender.isNotEmpty) filled++;
    if (basicDetails.dob != null) filled++;
    if (basicDetails.maritalStatus.isNotEmpty) filled++;
    if (basicDetails.profileCreatedFor.isNotEmpty) filled++;

    // Religion (3 required)
    total += 3;
    if (religionDetails.religion.isNotEmpty) filled++;
    if (religionDetails.caste.isNotEmpty) filled++;
    if (religionDetails.community.isNotEmpty) filled++;

    // Language (1 required)
    total += 1;
    if (languageDetails.motherTongue.isNotEmpty) filled++;

    // Location (3 required)
    total += 3;
    if (locationDetails.country.isNotEmpty) filled++;
    if (locationDetails.state.isNotEmpty) filled++;
    if (locationDetails.city.isNotEmpty) filled++;

    // Education (2 required)
    total += 2;
    if (educationDetails.qualification.isNotEmpty) filled++;
    if (educationDetails.occupation.isNotEmpty) filled++;

    // Physical (1 required)
    total += 1;
    if (physicalDetails.height.isNotEmpty) filled++;

    // Lifestyle (0 required — all optional)

    // Family (2 required)
    total += 2;
    if (familyDetails.familyType.isNotEmpty) filled++;
    if (familyDetails.familyValues.isNotEmpty) filled++;

    if (total == 0) return 0;
    return (filled / total * 100).clamp(0, 100);
  }

  ProfileDraft copyWith({
    BasicDetails? basicDetails,
    ReligionDetails? religionDetails,
    LanguageDetails? languageDetails,
    LocationDetails? locationDetails,
    EducationDetails? educationDetails,
    PhysicalDetails? physicalDetails,
    LifestyleDetails? lifestyleDetails,
    FamilyDetails? familyDetails,
    HoroscopeDetails? horoscopeDetails,
    PartnerPreference? partnerPreference,
    PhotoGallery? photoGallery,
    VerificationStatus? verificationStatus,
    int? currentStep,
  }) {
    return ProfileDraft(
      basicDetails: basicDetails ?? this.basicDetails,
      religionDetails: religionDetails ?? this.religionDetails,
      languageDetails: languageDetails ?? this.languageDetails,
      locationDetails: locationDetails ?? this.locationDetails,
      educationDetails: educationDetails ?? this.educationDetails,
      physicalDetails: physicalDetails ?? this.physicalDetails,
      lifestyleDetails: lifestyleDetails ?? this.lifestyleDetails,
      familyDetails: familyDetails ?? this.familyDetails,
      horoscopeDetails: horoscopeDetails ?? this.horoscopeDetails,
      partnerPreference: partnerPreference ?? this.partnerPreference,
      photoGallery: photoGallery ?? this.photoGallery,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      currentStep: currentStep ?? this.currentStep,
    );
  }
}
