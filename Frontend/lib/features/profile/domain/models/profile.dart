/// Nenjam Matrimony — Own Profile Domain Model
///
/// Mirrors `GET /profiles/me`'s response shape
/// (backend/apps/api/src/modules/profiles/entities/profile.entity.ts) —
/// field names match the Prisma `UserProfile` model, not the Flutter
/// registration wizard's field names (see profile_draft.dart for that side).
library;

List<String> _stringList(dynamic value) =>
    value is List ? value.map((e) => e.toString()).toList() : const [];

class ProfilePhotoInfo {
  final String id;
  final String cdnUrl;
  final bool isPrimary;
  final int order;
  final bool isApproved;

  const ProfilePhotoInfo({
    required this.id,
    required this.cdnUrl,
    required this.isPrimary,
    required this.order,
    required this.isApproved,
  });

  factory ProfilePhotoInfo.fromJson(Map<String, dynamic> json) =>
      ProfilePhotoInfo(
        id: json['id'] as String,
        cdnUrl: json['cdnUrl'] as String? ?? '',
        isPrimary: json['isPrimary'] as bool? ?? false,
        order: (json['order'] as num?)?.toInt() ?? 0,
        isApproved: json['isApproved'] as bool? ?? false,
      );
}

class PartnerPreferenceInfo {
  final int minAge;
  final int maxAge;
  final int minHeightCm;
  final int maxHeightCm;
  final List<String> preferredReligions;
  final List<String> preferredCastes;
  final String? minIncomeLakhs;
  final List<String> preferredCities;
  final List<String> preferredEducation;
  final List<String> preferredOccupations;
  final List<String> preferredMotherTongues;
  final List<String> maritalStatusPref;

  const PartnerPreferenceInfo({
    required this.minAge,
    required this.maxAge,
    required this.minHeightCm,
    required this.maxHeightCm,
    required this.preferredReligions,
    required this.preferredCastes,
    required this.minIncomeLakhs,
    required this.preferredCities,
    required this.preferredEducation,
    this.preferredOccupations = const [],
    this.preferredMotherTongues = const [],
    required this.maritalStatusPref,
  });

  factory PartnerPreferenceInfo.fromJson(Map<String, dynamic> json) =>
      PartnerPreferenceInfo(
        minAge: (json['minAge'] as num?)?.toInt() ?? 18,
        maxAge: (json['maxAge'] as num?)?.toInt() ?? 45,
        minHeightCm: (json['minHeightCm'] as num?)?.toInt() ?? 140,
        maxHeightCm: (json['maxHeightCm'] as num?)?.toInt() ?? 210,
        preferredReligions: _stringList(json['preferredReligions']),
        preferredCastes: _stringList(json['preferredCastes']),
        minIncomeLakhs: json['minIncomeLakhs'] as String?,
        preferredCities: _stringList(json['preferredCities']),
        preferredEducation: _stringList(json['preferredEducation']),
        preferredOccupations: _stringList(json['preferredOccupations']),
        preferredMotherTongues: _stringList(json['preferredMotherTongues']),
        maritalStatusPref: _stringList(json['maritalStatusPref']),
      );
}

class AstrologyInfo {
  final String? birthTime;
  final String? birthPlace;
  final String? rasi;
  final String? nakshatra;
  final String? gotram;
  final String dosham;
  final bool horoscopeAvailable;

  const AstrologyInfo({
    this.birthTime,
    this.birthPlace,
    this.rasi,
    this.nakshatra,
    this.gotram,
    this.dosham = 'NONE',
    this.horoscopeAvailable = false,
  });

  factory AstrologyInfo.fromJson(Map<String, dynamic> json) => AstrologyInfo(
        birthTime: json['birthTime'] as String?,
        birthPlace: json['birthPlace'] as String?,
        rasi: json['rasi'] as String?,
        nakshatra: json['nakshatra'] as String?,
        gotram: json['gotram'] as String?,
        dosham: json['dosham'] as String? ?? 'NONE',
        horoscopeAvailable: json['horoscopeAvailable'] as bool? ?? false,
      );
}

class ProfileCompletionInfo {
  final int percentage;
  final List<String> completedSections;
  final List<String> missingSections;

  const ProfileCompletionInfo({
    required this.percentage,
    required this.completedSections,
    required this.missingSections,
  });

  factory ProfileCompletionInfo.fromJson(Map<String, dynamic> json) =>
      ProfileCompletionInfo(
        percentage: (json['percentage'] as num?)?.toInt() ?? 0,
        completedSections: _stringList(json['completedSections']),
        missingSections: _stringList(json['missingSections']),
      );
}

/// The caller's own finalized profile, as returned by `GET /profiles/me`.
class Profile {
  final String firstName;
  final String lastName;
  final DateTime dob;
  final String gender;
  final String maritalStatus;
  final String religion;
  final String caste;
  final String? subCaste;
  final String? community;
  final String? denomination;
  final String motherTongue;
  final List<String> languagesKnown;
  final int heightCm;
  final int? weightKg;
  final String highestEducation;
  final String profession;
  final String? employerName;
  final String currentCity;
  final String currentState;
  final String? nativeCity;
  final String? country;
  final String? area;
  final String? pinCode;
  final String? bio;
  final String? dietaryHabits;
  final String? smokingHabits;
  final String? drinkingHabits;
  final String? fitness;
  final List<String> hobbies;
  final int? siblings;
  final bool isProfileComplete;
  final int profileCompletePct;
  final List<ProfilePhotoInfo> photos;
  final PartnerPreferenceInfo? partnerPreference;
  final AstrologyInfo? astrology;
  final ProfileCompletionInfo completion;

  const Profile({
    required this.firstName,
    required this.lastName,
    required this.dob,
    required this.gender,
    required this.maritalStatus,
    required this.religion,
    required this.caste,
    this.subCaste,
    this.community,
    this.denomination,
    required this.motherTongue,
    this.languagesKnown = const [],
    required this.heightCm,
    this.weightKg,
    required this.highestEducation,
    required this.profession,
    this.employerName,
    required this.currentCity,
    required this.currentState,
    this.nativeCity,
    this.country,
    this.area,
    this.pinCode,
    this.bio,
    this.dietaryHabits,
    this.smokingHabits,
    this.drinkingHabits,
    this.fitness,
    this.hobbies = const [],
    this.siblings,
    required this.isProfileComplete,
    required this.profileCompletePct,
    this.photos = const [],
    this.partnerPreference,
    this.astrology,
    required this.completion,
  });

  String get fullName => '$firstName $lastName'.trim();

  int get age {
    final now = DateTime.now();
    int years = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return years;
  }

  ProfilePhotoInfo? get primaryPhoto {
    if (photos.isEmpty) return null;
    return photos.firstWhere(
      (p) => p.isPrimary,
      orElse: () => photos.first,
    );
  }

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        dob: DateTime.tryParse(json['dob'] as String? ?? '') ?? DateTime(2000),
        gender: json['gender'] as String? ?? '',
        maritalStatus: json['maritalStatus'] as String? ?? '',
        religion: json['religion'] as String? ?? '',
        caste: json['caste'] as String? ?? '',
        subCaste: json['subCaste'] as String?,
        community: json['community'] as String?,
        denomination: json['denomination'] as String?,
        motherTongue: json['motherTongue'] as String? ?? '',
        languagesKnown: _stringList(json['languagesKnown']),
        heightCm: (json['heightCm'] as num?)?.toInt() ?? 0,
        weightKg: (json['weightKg'] as num?)?.toInt(),
        highestEducation: json['highestEducation'] as String? ?? '',
        profession: json['profession'] as String? ?? '',
        employerName: json['employerName'] as String?,
        currentCity: json['currentCity'] as String? ?? '',
        currentState: json['currentState'] as String? ?? '',
        nativeCity: json['nativeCity'] as String?,
        country: json['country'] as String?,
        area: json['area'] as String?,
        pinCode: json['pinCode'] as String?,
        bio: json['bio'] as String?,
        dietaryHabits: json['dietaryHabits'] as String?,
        smokingHabits: json['smokingHabits'] as String?,
        drinkingHabits: json['drinkingHabits'] as String?,
        fitness: json['fitness'] as String?,
        hobbies: _stringList(json['hobbies']),
        siblings: (json['siblings'] as num?)?.toInt(),
        isProfileComplete: json['isProfileComplete'] as bool? ?? false,
        profileCompletePct: (json['profileCompletePct'] as num?)?.toInt() ?? 0,
        photos: (json['photos'] as List?)
                ?.map((e) => ProfilePhotoInfo.fromJson(
                    (e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
        partnerPreference: json['partnerPreference'] != null
            ? PartnerPreferenceInfo.fromJson(
                (json['partnerPreference'] as Map).cast<String, dynamic>())
            : null,
        astrology: json['astrology'] != null
            ? AstrologyInfo.fromJson(
                (json['astrology'] as Map).cast<String, dynamic>())
            : null,
        completion: json['completion'] != null
            ? ProfileCompletionInfo.fromJson(
                (json['completion'] as Map).cast<String, dynamic>())
            : const ProfileCompletionInfo(
                percentage: 0, completedSections: [], missingSections: []),
      );
}
