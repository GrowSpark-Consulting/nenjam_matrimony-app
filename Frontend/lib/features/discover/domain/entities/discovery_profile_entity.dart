import 'compatibility_entity.dart';

/// A discoverable matrimony profile shown in the Discover feed.
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

  /// Reserved and intentionally unpopulated: the backend sends `false` for
  /// every member, because exposing whether (or how) another member took the
  /// psychology quiz would let their answers be inferred. Parsed only for
  /// API compatibility — never render it, filter on it, or rank by it
  /// (enforced by test/psychology_privacy_guard_test.dart).
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
  /// 'Male' | 'Female' | '' (unknown) — matches the value shape used by
  /// registration's own gender field. Drives which gender-specific icon a
  /// "no photo yet" placeholder shows for this profile.
  final String gender;
  /// Full-profile completeness — distinct from Discover eligibility (which
  /// only requires the mandatory registration steps). `false` means this
  /// profile skipped some of the optional sections; the card shows a
  /// "Building profile" badge in that case.
  final bool profileComplete;
  /// When this member's profile was created (backend `joinedAt`). The only
  /// basis for showing them under "New Today" / "Recently Joined"; null when
  /// the backend did not send it, in which case they are never labelled new.
  final DateTime? joinedAt;

  // Additional backend-driven profile fields the card / detail view render.
  // Empty string / [] when the (optional) source field wasn't filled.
  final String maritalStatus;
  final String motherTongue;
  final String smoking;
  final String drinking;
  final String physicalStatus;
  final String company;
  final String annualIncome;
  final String bio;
  final List<String> languages;
  final List<String> hobbies;

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
    this.gender = '',
    this.profileComplete = false,
    this.joinedAt,
    this.maritalStatus = '',
    this.motherTongue = '',
    this.smoking = '',
    this.drinking = '',
    this.physicalStatus = '',
    this.company = '',
    this.annualIncome = '',
    this.bio = '',
    this.languages = const [],
    this.hobbies = const [],
  });
}
