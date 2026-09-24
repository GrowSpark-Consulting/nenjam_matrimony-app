import 'package:flutter/material.dart';

import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../domain/entities/family_info_entity.dart';
import '../../domain/entities/horoscope_info_entity.dart';
import '../../domain/entities/lifestyle_info_entity.dart';
import '../../domain/entities/partner_preferences_entity.dart';
import '../../domain/entities/profile_detail_entity.dart';
import '../../domain/entities/timeline_event_entity.dart';
import '../../domain/entities/verification_checklist_entity.dart';
import '../../../../core/l10n/app_l10n.dart';

/// In-memory stand-in for a future `GET /api/profiles/:id` call.
///
/// Synthesizes a full [ProfileDetailEntity] from a [DiscoveryProfileEntity]
/// already loaded by any feed (Discover/Search/Matches/…) — no separate
/// mock profile pool, no id-based re-fetch. Every field is derived
/// deterministically from `base.id`, so the same card always expands to
/// the same detail data across visits within a session, rather than
/// reshuffling on every rebuild the way `Random()` would.
class ProfileDetailMockDataSource {
  // Label strings below come from AppL10n rather than a passed-in
  // AppLocalizations: this is a data-layer source with no BuildContext,
  // and threading one through the repository would change its contract.
  Future<ProfileDetailEntity> fetchProfileDetail(
    DiscoveryProfileEntity base,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));

    final seed = base.id.hashCode.abs();
    T pick<T>(List<T> pool) => pool[seed % pool.length];
    int pickInt(int min, int max) => min + (seed % (max - min + 1));

    final interestsPool = [
      'Reading', 'Travelling', 'Cooking', 'Music', 'Sports', 'Gaming',
      'Photography', 'Painting', 'Dancing', 'Yoga', 'Movies', 'Gardening',
    ];
    final interests = <String>{
      for (var i = 0; i < 6; i++) interestsPool[(seed + i) % interestsPool.length],
    }.toList();

    return ProfileDetailEntity(
      base: base,
      maritalStatus: pick(const ['Never Married', 'Divorced', 'Widowed']),
      motherTongue: base.community.isNotEmpty
          ? base.community
          : pick(const ['Tamil', 'Telugu', 'Hindi', 'Kannada']),
      interests: interests,
      coreValues: const ['Family Oriented', 'Honesty', 'Ambitious'],
      bio: 'A ${base.profession.toLowerCase()} based in ${base.location} who '
          'believes intellectual compatibility and shared values matter as '
          'much as first impressions. Looking for a partner who values '
          'growth, empathy, and building a life together.',
      family: FamilyInfoEntity(
        fatherName: 'Mr. ${pick(const [
              'Ramesh',
              'Suresh',
              'Anand',
              'Vijay',
            ])} ${base.name.split(' ').last}',
        fatherOccupation:
            pick(const ['Retired Government Officer', 'Business Owner', 'Private Sector Employee']),
        motherName: 'Mrs. ${pick(const ['Lakshmi', 'Kamala', 'Radha', 'Priya'])} ${base.name.split(' ').last}',
        motherOccupation: pick(const ['Homemaker', 'Teacher', 'Doctor']),
        familyType: pick(const ['Joint Family', 'Nuclear Family']),
        familyValues: pick(const ['Traditional', 'Moderate', 'Liberal']),
        familyStatus: pick(const ['Middle Class', 'Upper Middle Class', 'Affluent']),
        brothers: pickInt(0, 2),
        sisters: pickInt(0, 2),
      ),
      lifestyle: LifestyleInfoEntity(
        eatingHabit: base.diet.isNotEmpty ? base.diet : pick(const ['Vegetarian', 'Non-Vegetarian']),
        smoking: pick(const ['No', 'Occasionally']),
        drinking: pick(const ['No', 'Occasionally']),
        fitness: pick(const ['Daily', 'Regularly', 'Occasionally']),
        physicalStatus: 'Normal',
        hobbies: interests.take(4).toList(),
        aboutMe: 'Enjoys ${interests.take(2).join(' and ').toLowerCase()} on weekends.',
      ),
      horoscope: HoroscopeInfoEntity(
        rasi: pick(const ['Mesha', 'Vrishabha', 'Mithuna', 'Simha', 'Kanya', 'Thula']),
        nakshatra: pick(const ['Ashwini', 'Bharani', 'Rohini', 'Magha', 'Chitra', 'Swati']),
        dosham: pick(const ['NONE', 'Mild Dosham']),
        matchingEnabled: base.horoscopeAvailable,
        matchingPoints: const [
          'Strong emotional alignment between Moon signs',
          'Complementary family values and long-term goals',
        ],
      ),
      partnerPreferences: PartnerPreferencesEntity(
        preferredAgeRange: pick(const ['24-30', '26-32', '28-34']),
        preferredHeightRange: pick(const ["5'2\"-5'8\"", "5'4\"-6'0\""]),
        religionPref: base.religion.isNotEmpty ? base.religion : 'Any',
        castePref: pick(const ['Same Caste', 'Any Caste', 'Inter-Caste OK']),
        educationPref: pick(const ['Masters / PhD', 'Any Degree', 'B.E / B.Tech+']),
        occupationPref: pick(const ['Software / IT', 'Doctor', 'Any']),
        incomePref: pick(const ['10-20 Lakhs', '20-50 Lakhs', 'Any']),
        locationPref: pick(const ['Same City', 'Same State', 'Anywhere in India']),
        motherTonguePref: pick(const ['Same Mother Tongue', 'Any']),
        maritalStatusPref: 'Never Married',
      ),
      verification: VerificationChecklistEntity(
        items: [
          VerificationItemEntity(
            icon: Icons.phone_iphone_rounded,
            label: AppL10n.current.fieldPhone,
            status: base.phoneVerified
                ? VerificationItemStatus.verified
                : VerificationItemStatus.incomplete,
          ),
          VerificationItemEntity(
            icon: Icons.mail_rounded,
            label: AppL10n.current.fieldEmail,
            status: VerificationItemStatus.verified,
          ),
          VerificationItemEntity(
            icon: Icons.badge_rounded,
            label: AppL10n.current.fieldGovernmentId,
            status: base.isVerified
                ? VerificationItemStatus.verified
                : VerificationItemStatus.pending,
          ),
          VerificationItemEntity(
            icon: Icons.face_rounded,
            label: AppL10n.current.fieldFaceMatch,
            status: base.isVerified
                ? VerificationItemStatus.verified
                : VerificationItemStatus.incomplete,
          ),
        ],
      ),
      timeline: [
        TimelineEventEntity(
          icon: Icons.celebration_rounded,
          label: AppL10n.current.profileDetailJoinedNenjam,
          timeAgo: AppL10n.current.profileDetailTimeAgoMonths8,
        ),
        TimelineEventEntity(
          icon: Icons.edit_rounded,
          label: AppL10n.current.profileDetailProfileUpdated,
          timeAgo: AppL10n.current.profileDetailTimeAgoWeeks2,
        ),
        if (base.isVerified)
          TimelineEventEntity(
            icon: Icons.verified_rounded,
            label: AppL10n.current.profileDetailIdentityVerified,
            timeAgo: AppL10n.current.profileDetailTimeAgoMonth1,
          ),
        if (base.isOnline)
          TimelineEventEntity(
            icon: Icons.circle,
            label: AppL10n.current.profileDetailActiveNow,
            timeAgo: AppL10n.current.profileDetailTimeAgoJustNow,
          ),
      ],
    );
  }
}
