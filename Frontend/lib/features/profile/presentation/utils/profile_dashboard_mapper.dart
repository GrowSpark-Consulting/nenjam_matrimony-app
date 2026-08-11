import 'package:flutter/foundation.dart' show VoidCallback;

import '../../../../l10n/app_localizations.dart';
import '../../../authentication/data/models/auth_user.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../profile_completion/domain/profile_completion_aggregator.dart';
import '../../../registration/domain/models/profile_draft.dart';
import '../widgets/discover_opportunities_card.dart';
import '../widgets/partner_preference_card.dart';

/// Pure, presentation-only adapters from the app's existing domain models
/// ([ProfileDraft], [AuthUser], [ProfileCompleteness],
/// [DiscoveryProfileEntity]) to the Profile dashboard's UI-only display
/// values. No business logic lives here — every value is read straight off
/// an existing model; nothing is invented.

String profileDisplayName(
  ProfileDraft? draft,
  AuthUser? authUser,
  AppLocalizations l10n,
) {
  final first = draft?.basicDetails.firstName.trim() ?? '';
  final last = draft?.basicDetails.lastName.trim() ?? '';
  final full = '$first $last'.trim();
  if (full.isNotEmpty) return full;
  final username = authUser?.username?.trim() ?? '';
  if (username.isNotEmpty) return username;
  return l10n.profileNewMember;
}

int? profileDisplayAge(ProfileDraft? draft) => draft?.basicDetails.age;

String profileDisplayLocation(ProfileDraft? draft, AppLocalizations l10n) {
  final city = draft?.locationDetails.city.trim() ?? '';
  final state = draft?.locationDetails.state.trim() ?? '';
  final country = draft?.locationDetails.country.trim() ?? '';
  final parts = [city, state, country].where((p) => p.isNotEmpty);
  if (parts.isEmpty) return l10n.profileLocationNotSet;
  return parts.join(', ');
}

String? profileDisplayFaith(ProfileDraft? draft) {
  final religion = draft?.religionDetails.religion.trim() ?? '';
  final caste = draft?.religionDetails.caste.trim() ?? '';
  if (religion.isNotEmpty && caste.isNotEmpty) return '$religion, $caste';
  if (religion.isNotEmpty) return religion;
  return null;
}

String? profileDisplayHeight(ProfileDraft? draft) {
  final height = draft?.physicalDetails.height.trim() ?? '';
  return height.isNotEmpty ? height : null;
}

String? profileDisplayProfession(ProfileDraft? draft) {
  final occupation = draft?.educationDetails.occupation.trim() ?? '';
  return occupation.isNotEmpty ? occupation : null;
}

String? profileDisplayMaritalStatus(ProfileDraft? draft) {
  final status = draft?.basicDetails.maritalStatus.trim() ?? '';
  return status.isNotEmpty ? status : null;
}

/// Compact, real identifier derived from the signed-in Firebase user.
///
/// TODO(backend): the backend doesn't define a dedicated "Matrimony ID"
/// field yet (not on [ProfileDraft] or [AuthUser]) — this shows a
/// truncated real uid rather than inventing a plausible-looking fake ID.
/// Replace with the real matrimony ID once the backend exposes one.
String profileDisplayId(AuthUser? authUser) {
  final uid = authUser?.uid ?? '';
  if (uid.isEmpty) return '—';
  return uid.length > 8 ? uid.substring(0, 8).toUpperCase() : uid.toUpperCase();
}

/// Maps real partner-preference fields to display rows, skipping any the
/// user hasn't filled in. Falls back to a single "not set yet" row rather
/// than inventing specific preference values when none exist.
List<NmPreferenceRow> profileDisplayPartnerPreferences(
  PartnerPreference pref,
  AppLocalizations l10n,
) {
  final rows = <NmPreferenceRow>[
    if (pref.preferredAgeRange.isNotEmpty)
      NmPreferenceRow(label: l10n.fieldAgeRange, value: pref.preferredAgeRange),
    if (pref.preferredHeightRange.isNotEmpty)
      NmPreferenceRow(label: l10n.fieldHeight, value: pref.preferredHeightRange),
    if (pref.religionPref.isNotEmpty)
      NmPreferenceRow(label: l10n.fieldReligion, value: pref.religionPref),
    if (pref.educationPref.isNotEmpty)
      NmPreferenceRow(label: l10n.fieldEducation, value: pref.educationPref),
    if (pref.locationPref.isNotEmpty)
      NmPreferenceRow(label: l10n.fieldLocation, value: pref.locationPref),
  ];
  if (rows.isEmpty) {
    return [
      NmPreferenceRow(
        label: l10n.profilePreferencesLabel,
        value: l10n.profilePreferencesNotSet,
      ),
    ];
  }
  return rows;
}

/// Real signals only. "Account Created" is implicit (the dashboard requires
/// an authenticated user); "Profile Completed" reflects the same
/// registration-completion module used by the Profile Completion screen;
/// "Verified" reflects real Firebase email+phone verification
/// ([AuthUser.isFullyVerified]).
///
/// TODO(backend): steps beyond "Verified" (Interests, Conversations,
/// Perfect Match) have no backing data anywhere yet — the Interests and
/// Messages features are still stubs — so this never advances past step 2.
/// Wire the remaining steps once those features expose real data.
int profileJourneyStep({
  required AuthUser? authUser,
  required ProfileCompleteness? completeness,
}) {
  if (authUser == null) return 0;
  final registrationDone =
      completeness?.completedModules.any(
        (m) => m.module.id == 'registration',
      ) ??
      false;
  if (!registrationDone) return 0;
  if (!authUser.isFullyVerified) return 1;
  return 2;
}

/// Maps a discover-feed profile into the dashboard's lightweight display
/// model, reusing the same overall compatibility score already shown on the
/// Discover/Matches screens rather than inventing a separate number here.
NmDiscoverMatch profileDisplayDiscoverMatch(
  DiscoveryProfileEntity profile, {
  VoidCallback? onTap,
}) {
  return NmDiscoverMatch(
    name: profile.name,
    age: profile.age,
    profession: profile.profession,
    compatibilityPct: profile.compatibility.overallCompatibility,
    imageUrl: profile.photoUrls.isNotEmpty ? profile.photoUrls.first : null,
    onTap: onTap,
  );
}
