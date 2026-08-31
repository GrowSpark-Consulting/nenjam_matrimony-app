import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../psychology/domain/models/personality_result.dart';
import 'family_info_entity.dart';
import 'horoscope_info_entity.dart';
import 'lifestyle_info_entity.dart';
import 'partner_preferences_entity.dart';
import 'timeline_event_entity.dart';
import 'verification_checklist_entity.dart';

/// Full read-only detail view of ANOTHER member's profile.
///
/// Wraps [DiscoveryProfileEntity] (the same base data already flowing
/// through Discover/Matches/Search) via [base] rather than duplicating its
/// fields, and adds only what a detail screen needs that a feed card never
/// did — mirrors how [DiscoveryProfileEntity] itself already composes
/// `CompatibilityEntity` rather than inlining score fields.
class ProfileDetailEntity {
  final DiscoveryProfileEntity base;
  final String maritalStatus;
  final String motherTongue;
  final List<String> interests;
  final List<String> coreValues;
  final String? bio;
  final FamilyInfoEntity family;
  final LifestyleInfoEntity lifestyle;
  final HoroscopeInfoEntity horoscope;
  final PartnerPreferencesEntity partnerPreferences;
  final VerificationChecklistEntity verification;
  final PersonalityResult? personality;
  final List<TimelineEventEntity> timeline;

  const ProfileDetailEntity({
    required this.base,
    this.maritalStatus = '',
    this.motherTongue = '',
    this.interests = const [],
    this.coreValues = const [],
    this.bio,
    this.family = const FamilyInfoEntity(),
    this.lifestyle = const LifestyleInfoEntity(),
    this.horoscope = const HoroscopeInfoEntity(),
    this.partnerPreferences = const PartnerPreferencesEntity(),
    this.verification = const VerificationChecklistEntity(),
    this.personality,
    this.timeline = const [],
  });
}
