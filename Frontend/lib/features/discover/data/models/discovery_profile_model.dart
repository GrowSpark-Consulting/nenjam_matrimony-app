import '../../domain/entities/compatibility_entity.dart';
import '../../domain/entities/discovery_profile_entity.dart';

/// Wire model for [DiscoveryProfileEntity]. `fromJson`/`toJson` are the seam
/// a real `GET /api/discover-feed` response will plug into — nothing else in
/// the feature needs to change when the mock datasource is swapped for Dio.
class DiscoveryProfileModel extends DiscoveryProfileEntity {
  const DiscoveryProfileModel({
    required super.id,
    required super.matrimonyId,
    required super.name,
    required super.age,
    required super.location,
    required super.profession,
    required super.education,
    required super.photoUrls,
    super.isVerified,
    super.isPremium,
    super.isPsychologyCompleted,
    super.isOnline,
    super.horoscopeAvailable,
    super.photoProtected,
    super.phoneVerified,
    super.compatibility,
    super.tags,
    super.religion,
    super.caste,
    super.community,
    super.height,
    super.diet,
    super.distanceKm,
    super.gender,
    super.profileComplete,
    super.joinedAt,
    super.maritalStatus,
    super.motherTongue,
    super.smoking,
    super.drinking,
    super.physicalStatus,
    super.company,
    super.annualIncome,
    super.bio,
    super.languages,
    super.hobbies,
  });

  factory DiscoveryProfileModel.fromJson(Map<String, dynamic> json) {
    final compatibilityJson = json['compatibility'] as Map<String, dynamic>?;

    return DiscoveryProfileModel(
      id: json['id'] as String,
      matrimonyId: json['matrimonyId'] as String? ?? '',
      name: json['name'] as String,
      age: json['age'] as int,
      location: json['location'] as String,
      profession: json['profession'] as String,
      education: json['education'] as String? ?? '',
      photoUrls: (json['photoUrls'] as List).cast<String>(),
      isVerified: json['isVerified'] as bool? ?? false,
      isPremium: json['isPremium'] as bool? ?? false,
      // Always false from the backend, by design (privacy) — tolerated if
      // absent. See DiscoveryProfileEntity.isPsychologyCompleted.
      isPsychologyCompleted: json['isPsychologyCompleted'] as bool? ?? false,
      isOnline: json['isOnline'] as bool? ?? false,
      horoscopeAvailable: json['horoscopeAvailable'] as bool? ?? false,
      photoProtected: json['photoProtected'] as bool? ?? false,
      phoneVerified: json['phoneVerified'] as bool? ?? false,
      compatibility: compatibilityJson == null
          ? const CompatibilityEntity()
          : CompatibilityEntity(
              aiMatchPercent: compatibilityJson['aiMatchPercent'] as int? ?? 0,
              astroMatchPercent: compatibilityJson['astroMatchPercent'] as int? ?? 0,
              // Always 0 from the backend, by design (privacy).
              psychologyMatchPercent:
                  compatibilityJson['psychologyMatchPercent'] as int? ?? 0,
              overallCompatibility:
                  compatibilityJson['overallCompatibility'] as int? ?? 0,
            ),
      tags: (json['tags'] as List?)?.cast<String>() ?? const [],
      religion: json['religion'] as String? ?? '',
      caste: json['caste'] as String? ?? '',
      community: json['community'] as String? ?? '',
      height: json['height'] as String? ?? '',
      diet: json['diet'] as String? ?? '',
      distanceKm: (json['distanceKm'] as num?)?.toDouble(),
      gender: json['gender'] as String? ?? '',
      profileComplete: json['profileComplete'] as bool? ?? false,
      joinedAt: DateTime.tryParse(json['joinedAt'] as String? ?? ''),
      maritalStatus: json['maritalStatus'] as String? ?? '',
      motherTongue: json['motherTongue'] as String? ?? '',
      smoking: json['smoking'] as String? ?? '',
      drinking: json['drinking'] as String? ?? '',
      physicalStatus: json['physicalStatus'] as String? ?? '',
      company: json['company'] as String? ?? '',
      annualIncome: json['annualIncome'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      languages: (json['languages'] as List?)?.cast<String>() ?? const [],
      hobbies: (json['hobbies'] as List?)?.cast<String>() ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'matrimonyId': matrimonyId,
        'name': name,
        'age': age,
        'location': location,
        'profession': profession,
        'education': education,
        'photoUrls': photoUrls,
        'isVerified': isVerified,
        'isPremium': isPremium,
        'isPsychologyCompleted': isPsychologyCompleted,
        'isOnline': isOnline,
        'horoscopeAvailable': horoscopeAvailable,
        'photoProtected': photoProtected,
        'phoneVerified': phoneVerified,
        'compatibility': {
          'aiMatchPercent': compatibility.aiMatchPercent,
          'astroMatchPercent': compatibility.astroMatchPercent,
          'psychologyMatchPercent': compatibility.psychologyMatchPercent,
          'overallCompatibility': compatibility.overallCompatibility,
        },
        'tags': tags,
        'religion': religion,
        'caste': caste,
        'community': community,
        'height': height,
        'diet': diet,
        'distanceKm': distanceKm,
        'gender': gender,
        'profileComplete': profileComplete,
        'joinedAt': joinedAt?.toIso8601String(),
        'maritalStatus': maritalStatus,
        'motherTongue': motherTongue,
        'smoking': smoking,
        'drinking': drinking,
        'physicalStatus': physicalStatus,
        'company': company,
        'annualIncome': annualIncome,
        'bio': bio,
        'languages': languages,
        'hobbies': hobbies,
      };
}

/// Normalizes the backend's lowercase `gender` (`"male"` / `"female"`) to the
/// `'Male'` / `'Female'` casing the rest of the app uses — the gender-aware
/// "no photo yet" placeholder keys off exactly those strings, and registration
/// stores them that way too.
///
/// Lives here rather than inside `fromJson` because callers apply it to the
/// raw JSON before constructing the model, and here rather than privately in
/// one repository because every endpoint returning this card shape needs it —
/// `/discover`, `/discover/search` and `/profiles/nearby` alike. An unknown
/// value passes through untouched so a new backend gender never becomes the
/// wrong one.
String normalizeProfileGender(dynamic value) {
  final gender = value is String ? value : '';
  switch (gender.toLowerCase()) {
    case 'male':
      return 'Male';
    case 'female':
      return 'Female';
    default:
      return gender;
  }
}
