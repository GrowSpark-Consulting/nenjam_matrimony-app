import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

/// Profile Completion module id → display copy. Extracted so both the
/// Profile Completion screen and the Nenjam hub's condensed "Improve Your
/// Match Quality" section can render the same modules consistently.
IconData moduleIcon(String moduleId) => switch (moduleId) {
      'registration' => Icons.person_rounded,
      'education' => Icons.school_rounded,
      'physical' => Icons.accessibility_new_rounded,
      'lifestyle' => Icons.spa_rounded,
      'family' => Icons.family_restroom_rounded,
      'psychology' => Icons.psychology_alt_rounded,
      'photos' => Icons.photo_library_rounded,
      'partnerPreference' => Icons.handshake_rounded,
      'horoscope' => Icons.stars_rounded,
      'verification' => Icons.verified_rounded,
      _ => Icons.circle_outlined,
    };

String moduleTitle(AppLocalizations l10n, String moduleId) => switch (moduleId) {
      'registration' => l10n.profileCompletionModuleRegistration,
      'education' => l10n.registrationStepEducation,
      'physical' => l10n.registrationStepPhysical,
      'lifestyle' => l10n.registrationStepLifestyle,
      'family' => l10n.registrationStepFamily,
      'psychology' => l10n.profileCompletionGrowthPsychology,
      'photos' => l10n.registrationStepPhotos,
      'partnerPreference' => l10n.registrationPartnerTitle,
      'horoscope' => l10n.registrationHoroscopeTitle,
      'verification' => l10n.registrationStepVerification,
      _ => '',
    };

String moduleTip(AppLocalizations l10n, String moduleId) => switch (moduleId) {
      'registration' => l10n.profileCompletionTipRegistration,
      'education' => l10n.registrationTipEducation,
      'physical' => l10n.registrationTipPhysical,
      'lifestyle' => l10n.registrationTipLifestyle,
      'family' => l10n.registrationTipFamily,
      'psychology' => l10n.profileCompletionGrowthPsychologySubtitle,
      'photos' => l10n.registrationTipPhotos,
      'partnerPreference' => l10n.registrationTipPartnerPref,
      'horoscope' => l10n.registrationTipHoroscope,
      'verification' => l10n.registrationTipVerification,
      _ => '',
    };

String moduleAction(AppLocalizations l10n, String moduleId) => switch (moduleId) {
      'registration' => l10n.profileCompletionActionRegistration,
      'education' => l10n.profileCompletionActionEducation,
      'physical' => l10n.profileCompletionActionPhysical,
      'lifestyle' => l10n.profileCompletionActionLifestyle,
      'family' => l10n.profileCompletionActionFamily,
      'psychology' => l10n.profileCompletionActionPsychology,
      'photos' => l10n.profileCompletionActionPhotos,
      'partnerPreference' => l10n.profileCompletionActionPartnerPref,
      'horoscope' => l10n.profileCompletionActionHoroscope,
      'verification' => l10n.profileCompletionActionVerification,
      _ => '',
    };
