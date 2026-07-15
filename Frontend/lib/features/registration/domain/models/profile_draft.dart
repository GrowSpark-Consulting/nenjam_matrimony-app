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

/// Reads a nested JSON object safely — the draft endpoint omits keys for
/// sections the user hasn't reached yet.
Map<String, dynamic> _section(Map<String, dynamic> data, String key) {
  final value = data[key];
  return value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};
}

List<String> _stringList(dynamic value) =>
    value is List ? value.map((e) => e.toString()).toList() : const [];

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
  final String profileCreatedFor;

  const BasicDetails({
    this.firstName = '',
    this.lastName = '',
    this.gender = '',
    this.dob,
    this.maritalStatus = '',
    this.profileCreatedFor = 'Myself',
  });

  int? get age {
    if (dob == null) return null;
    final now = DateTime.now();
    int years = now.year - dob!.year;
    if (now.month < dob!.month || (now.month == dob!.month && now.day < dob!.day)) {
      years--;
    }
    return years;
  }

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
        dob: json['dob'] != null
            ? DateTime.tryParse(json['dob'] as String)
            : null,
        maritalStatus: _fromEnumValue(
            json['maritalStatus'] as String?, _maritalStatusReverseMap),
        profileCreatedFor:
            json['profileCreatedFor'] as String? ?? 'Myself',
      );

  Map<String, dynamic> toJson() => {
        if (firstName.isNotEmpty) 'firstName': firstName,
        if (lastName.isNotEmpty) 'lastName': lastName,
        if (gender.isNotEmpty) 'gender': _toEnumValue(gender),
        if (dob != null) 'dob': dob!.toIso8601String(),
        if (maritalStatus.isNotEmpty)
          'maritalStatus': _toEnumValue(maritalStatus),
        if (profileCreatedFor.isNotEmpty)
          'profileCreatedFor': profileCreatedFor,
      };
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
}

// ─── Physical Details (Step 6) ───────────────────────────────────────
class PhysicalDetails {
  final String height;
  final String weight;
  final String bodyType;
  final String complexion;
  final String bloodGroup;
  final String disability;

  const PhysicalDetails({
    this.height = '',
    this.weight = '',
    this.bodyType = '',
    this.complexion = '',
    this.bloodGroup = '',
    this.disability = 'None',
  });

  PhysicalDetails copyWith({
    String? height,
    String? weight,
    String? bodyType,
    String? complexion,
    String? bloodGroup,
    String? disability,
  }) {
    return PhysicalDetails(
      height: height ?? this.height,
      weight: weight ?? this.weight,
      bodyType: bodyType ?? this.bodyType,
      complexion: complexion ?? this.complexion,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      disability: disability ?? this.disability,
    );
  }

  factory PhysicalDetails.fromJson(Map<String, dynamic> json) =>
      PhysicalDetails(
        height: json['height'] as String? ?? '',
        weight: json['weight'] as String? ?? '',
        bodyType: json['bodyType'] as String? ?? '',
        complexion: json['complexion'] as String? ?? '',
        bloodGroup: json['bloodGroup'] as String? ?? '',
        disability: json['disability'] as String? ?? 'None',
      );

  Map<String, dynamic> toJson() => {
        if (height.isNotEmpty) 'height': height,
        if (weight.isNotEmpty) 'weight': weight,
        if (bodyType.isNotEmpty) 'bodyType': bodyType,
        if (complexion.isNotEmpty) 'complexion': complexion,
        if (bloodGroup.isNotEmpty) 'bloodGroup': bloodGroup,
        if (disability.isNotEmpty) 'disability': disability,
      };
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
}

// ─── Family Details (Step 8) ─────────────────────────────────────────
class FamilyDetails {
  final String fatherName;
  final String fatherOccupation;
  final String motherName;
  final String motherOccupation;
  final String familyType;
  final String familyValues;
  final String familyStatus;
  final int brothers;
  final int sisters;

  const FamilyDetails({
    this.fatherName = '',
    this.fatherOccupation = '',
    this.motherName = '',
    this.motherOccupation = '',
    this.familyType = '',
    this.familyValues = '',
    this.familyStatus = '',
    this.brothers = 0,
    this.sisters = 0,
  });

  FamilyDetails copyWith({
    String? fatherName,
    String? fatherOccupation,
    String? motherName,
    String? motherOccupation,
    String? familyType,
    String? familyValues,
    String? familyStatus,
    int? brothers,
    int? sisters,
  }) {
    return FamilyDetails(
      fatherName: fatherName ?? this.fatherName,
      fatherOccupation: fatherOccupation ?? this.fatherOccupation,
      motherName: motherName ?? this.motherName,
      motherOccupation: motherOccupation ?? this.motherOccupation,
      familyType: familyType ?? this.familyType,
      familyValues: familyValues ?? this.familyValues,
      familyStatus: familyStatus ?? this.familyStatus,
      brothers: brothers ?? this.brothers,
      sisters: sisters ?? this.sisters,
    );
  }

  factory FamilyDetails.fromJson(Map<String, dynamic> json) => FamilyDetails(
        fatherName: json['fatherName'] as String? ?? '',
        fatherOccupation: json['fatherOccupation'] as String? ?? '',
        motherName: json['motherName'] as String? ?? '',
        motherOccupation: json['motherOccupation'] as String? ?? '',
        familyType: json['familyType'] as String? ?? '',
        familyValues: json['familyValues'] as String? ?? '',
        familyStatus: json['familyStatus'] as String? ?? '',
        brothers: (json['brothers'] as num?)?.toInt() ?? 0,
        sisters: (json['sisters'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        if (fatherName.isNotEmpty) 'fatherName': fatherName,
        if (fatherOccupation.isNotEmpty) 'fatherOccupation': fatherOccupation,
        if (motherName.isNotEmpty) 'motherName': motherName,
        if (motherOccupation.isNotEmpty) 'motherOccupation': motherOccupation,
        if (familyType.isNotEmpty) 'familyType': familyType,
        if (familyValues.isNotEmpty) 'familyValues': familyValues,
        if (familyStatus.isNotEmpty) 'familyStatus': familyStatus,
        'brothers': brothers,
        'sisters': sisters,
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
      };
}

// ─── Photo Gallery (Step 12) ─────────────────────────────────────────
class PhotoGallery {
  final String? primaryPhotoPath;
  final List<String> galleryPaths;

  const PhotoGallery({
    this.primaryPhotoPath,
    this.galleryPaths = const [],
  });

  PhotoGallery copyWith({
    String? primaryPhotoPath,
    List<String>? galleryPaths,
  }) {
    return PhotoGallery(
      primaryPhotoPath: primaryPhotoPath ?? this.primaryPhotoPath,
      galleryPaths: galleryPaths ?? this.galleryPaths,
    );
  }

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
class VerificationStatus {
  final bool mobileVerified;
  final bool emailVerified;
  final bool faceVerified;
  final bool aadhaarVerified;
  final bool govIdVerified;

  const VerificationStatus({
    this.mobileVerified = false,
    this.emailVerified = false,
    this.faceVerified = false,
    this.aadhaarVerified = false,
    this.govIdVerified = false,
  });

  VerificationStatus copyWith({
    bool? mobileVerified,
    bool? emailVerified,
    bool? faceVerified,
    bool? aadhaarVerified,
    bool? govIdVerified,
  }) {
    return VerificationStatus(
      mobileVerified: mobileVerified ?? this.mobileVerified,
      emailVerified: emailVerified ?? this.emailVerified,
      faceVerified: faceVerified ?? this.faceVerified,
      aadhaarVerified: aadhaarVerified ?? this.aadhaarVerified,
      govIdVerified: govIdVerified ?? this.govIdVerified,
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
      );

  Map<String, dynamic> toJson() => {
        'mobileVerified': mobileVerified,
        'emailVerified': emailVerified,
        'faceVerified': faceVerified,
        'aadhaarVerified': aadhaarVerified,
        'govIdVerified': govIdVerified,
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
