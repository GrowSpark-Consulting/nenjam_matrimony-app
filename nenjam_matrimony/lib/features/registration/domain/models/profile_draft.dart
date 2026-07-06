/// Nenjam Matrimony — Profile Draft Domain Models
///
/// Immutable data classes for the 12-step registration wizard.
/// Plain Dart — no Flutter dependency, no code generation required.
library;

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
}

// ─── Partner Preference (Step 10) ────────────────────────────────────
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
}

// ─── Photo Gallery (Step 11) ─────────────────────────────────────────
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
}

// ─── Verification Status (Step 12) ───────────────────────────────────
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

  static const int totalSteps = 12;

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
