import '../../domain/entities/compatibility_entity.dart';
import '../../domain/entities/discovery_profile_entity.dart';

/// Wire model for [DiscoveryProfileEntity]. `fromJson`/`toJson` are the seam
/// a real `GET /api/home-feed` response will plug into — nothing else in
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
      };
}
