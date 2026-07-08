import 'compatibility_entity.dart';

/// A discoverable matrimony profile shown in the Home Feed.
///
/// Named `Discovery*` (not `Profile*`) so it doesn't collide with the
/// separate `features/profile` module's own profile model — this entity
/// only carries what the feed needs to render a card, not the full
/// user-profile domain.
class DiscoveryProfileEntity {
  final String id;
  final String matrimonyId;
  final String name;
  final int age;
  final String location;
  final String profession;
  final String education;
  final List<String> photoUrls;
  final bool isVerified;
  final bool isPremium;
  final bool isPsychologyCompleted;
  final bool isOnline;
  final bool horoscopeAvailable;
  final bool photoProtected;
  final bool phoneVerified;
  final CompatibilityEntity compatibility;
  final List<String> tags;
  final String religion;
  final String caste;
  final String community;
  final String height;
  final String diet;
  final double? distanceKm;

  const DiscoveryProfileEntity({
    required this.id,
    required this.matrimonyId,
    required this.name,
    required this.age,
    required this.location,
    required this.profession,
    required this.education,
    required this.photoUrls,
    this.isVerified = false,
    this.isPremium = false,
    this.isPsychologyCompleted = false,
    this.isOnline = false,
    this.horoscopeAvailable = false,
    this.photoProtected = false,
    this.phoneVerified = false,
    this.compatibility = const CompatibilityEntity(),
    this.tags = const [],
    this.religion = '',
    this.caste = '',
    this.community = '',
    this.height = '',
    this.diet = '',
    this.distanceKm,
  });
}
