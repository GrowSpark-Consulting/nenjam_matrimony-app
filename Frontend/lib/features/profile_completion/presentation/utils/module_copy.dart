import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

/// Profile Completion module id → display copy. Extracted so both the
/// Profile Completion screen and the Nenjam hub's condensed "Improve Your
/// Match Quality" section can render the same modules consistently.
IconData moduleIcon(String moduleId) => switch (moduleId) {
      'registration' => Icons.person_rounded,
      'photos' => Icons.photo_library_rounded,
      'partnerPreference' => Icons.handshake_rounded,
      'horoscope' => Icons.stars_rounded,
      'verification' => Icons.verified_rounded,
      _ => Icons.circle_outlined,
    };

String moduleTitle(AppLocalizations l10n, String moduleId) => switch (moduleId) {
      'registration' => l10n.profileCompletionModuleRegistration,
      'photos' => l10n.registrationStepPhotos,
      'partnerPreference' => l10n.registrationPartnerTitle,
      'horoscope' => l10n.registrationHoroscopeTitle,
      'verification' => l10n.registrationStepVerification,
      _ => '',
    };

String moduleTip(AppLocalizations l10n, String moduleId) => switch (moduleId) {
      'registration' => l10n.profileCompletionTipRegistration,
      'photos' => l10n.registrationTipPhotos,
      'partnerPreference' => l10n.registrationTipPartnerPref,
      'horoscope' => l10n.registrationTipHoroscope,
      'verification' => l10n.registrationTipVerification,
      _ => '',
    };

String moduleAction(AppLocalizations l10n, String moduleId) => switch (moduleId) {
      'registration' => l10n.profileCompletionActionRegistration,
      'photos' => l10n.profileCompletionActionPhotos,
      'partnerPreference' => l10n.profileCompletionActionPartnerPref,
      'horoscope' => l10n.profileCompletionActionHoroscope,
      'verification' => l10n.profileCompletionActionVerification,
      _ => '',
    };
