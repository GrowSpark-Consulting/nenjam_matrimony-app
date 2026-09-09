import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

/// Profile Completion module id → display copy. Extracted so both the
/// Profile Completion screen and the Nenjam hub's condensed "Improve Your
/// Match Quality" section can render the same modules consistently.
///
/// The backend now scores four modules — `registration`, `family`,
/// `horoscope`, `verification`. The `education`, `physical`, `lifestyle`,
/// `psychology`, `partnerPreference` and `photos` branches below are kept
/// deliberately: their content moved inside the registration slice, but a
/// client can still be handed a response from an older API, and every switch
/// here has a `_` fallback so an id nobody recognises renders blank rather
/// than throwing.
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


/// Required-field id → its label, for the "Registration information" group.
///
/// Reuses the label each field already carries on its own step, so the
/// completion screen names an answer exactly as the form that asks for it
/// does. Unknown ids render blank rather than throwing — a newer server may
/// name a field this build has never heard of.
String requiredFieldTitle(AppLocalizations l10n, String fieldId) =>
    switch (fieldId) {
      'profileCreatedFor' => l10n.registrationProfileForLabel,
      'gender' => l10n.registrationGenderLabel,
      'firstName' => l10n.registrationFirstNameLabel,
      'lastName' => l10n.registrationLastNameLabel,
      'dob' => l10n.registrationDobLabel,
      'religion' => l10n.registrationReligionLabel,
      'community' => l10n.registrationCommunityLabel,
      'country' => l10n.registrationCountryLabel,
      'state' => l10n.registrationStateLabel,
      'city' => l10n.registrationCityLabel,
      'subCommunity' => l10n.registrationSubCasteLabel,
      'maritalStatus' => l10n.registrationMaritalStatusLabel,
      'height' => l10n.registrationHeightLabel,
      'diet' => l10n.registrationEatingHabitLabel,
      'qualification' => l10n.registrationQualificationLabel,
      'college' => l10n.registrationCollegeLabel,
      'annualIncome' => l10n.registrationAnnualIncomeLabel,
      'employmentType' => l10n.registrationEmploymentTypeLabel,
      'workIndustry' => l10n.registrationIndustryLabel,
      'occupation' => l10n.registrationOccupationLabel,
      'company' => l10n.registrationCompanyLabel,
      'photo' => l10n.registrationStepPhotos,
      _ => '',
    };
