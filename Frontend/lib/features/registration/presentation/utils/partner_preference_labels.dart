/// Display-label lookups for the 10 base `PartnerPreference` fields'
/// canonical English values (e.g. `'Same Caste'`, `'Any'`). Values
/// themselves stay English (they're what's PATCHed to the backend and
/// parsed by `parseIntRange`/`toStringArray` there) — only the on-screen
/// label is localized.
///
/// Shared by both editing surfaces for these fields — the registration
/// wizard's step 10 (`StepPartnerPref`, chip UI) and the standalone Partner
/// Preferences page (`features/partner_preferences`, sheet UI) — so the two
/// never drift out of sync.
library;

import '../../../../l10n/app_localizations.dart';

// ─── Canonical option lists for the 10 base fields ─────────────────────
// Shared for the same reason as the label functions below — both editing
// surfaces must offer identical choices for identical backend fields.
const List<String> partnerPrefAgeRanges = ['18-22', '22-26', '26-30', '30-35', '35-40', '40-50', 'Any'];
const List<String> partnerPrefHeightRanges = ['4\'6"-5\'0"', '5\'0"-5\'4"', '5\'4"-5\'8"', '5\'8"-6\'0"', '6\'0"+', 'Any'];
const List<String> partnerPrefReligions = ['Hindu', 'Christian', 'Muslim', 'Jain', 'Sikh', 'Any'];
const List<String> partnerPrefCastes = ['Same Caste', 'Any Caste', 'Inter-Caste OK'];
const List<String> partnerPrefEducations = ['B.E / B.Tech+', 'MBBS / MD+', 'MBA+', 'Any Degree', 'Any'];
const List<String> partnerPrefOccupations = ['Software / IT', 'Doctor', 'Government', 'Business', 'Any'];
const List<String> partnerPrefIncomes = ['5-10 Lakhs', '10-20 Lakhs', '20-50 Lakhs', '50 Lakhs+', 'Any'];
const List<String> partnerPrefLocations = ['Same City', 'Same State', 'Anywhere in India', 'NRI OK', 'Any'];
const List<String> partnerPrefMotherTongues = ['Same Mother Tongue', 'Tamil', 'Telugu', 'Hindi', 'Any'];
const List<String> partnerPrefMaritalStatuses = ['Never Married', 'Doesn\'t Matter', 'Any'];

String religionPrefLabel(AppLocalizations l10n, String v) => switch (v) {
      'Hindu' => l10n.religionHindu,
      'Christian' => l10n.religionChristian,
      'Muslim' => l10n.religionMuslim,
      'Jain' => l10n.religionJain,
      'Sikh' => l10n.religionSikh,
      'Any' => l10n.commonAny,
      _ => v,
    };

String castePrefLabel(AppLocalizations l10n, String v) => switch (v) {
      'Same Caste' => l10n.prefCasteSame,
      'Any Caste' => l10n.prefCasteAny,
      'Inter-Caste OK' => l10n.prefCasteInter,
      _ => v,
    };

String educationPrefLabel(AppLocalizations l10n, String v) => switch (v) {
      'Any Degree' => l10n.prefEduAnyDegree,
      'Any' => l10n.commonAny,
      _ => v, // degree acronyms stay English
    };

String occupationPrefLabel(AppLocalizations l10n, String v) => switch (v) {
      'Software / IT' => l10n.prefOccSoftwareIt,
      'Doctor' => l10n.occDoctor,
      'Government' => l10n.empGovernment,
      'Business' => l10n.empBusiness,
      'Any' => l10n.commonAny,
      _ => v,
    };

String locationPrefLabel(AppLocalizations l10n, String v) => switch (v) {
      'Same City' => l10n.prefLocSameCity,
      'Same State' => l10n.prefLocSameState,
      'Anywhere in India' => l10n.prefLocAnywhereIndia,
      'NRI OK' => l10n.prefLocNri,
      'Any' => l10n.commonAny,
      _ => v,
    };

String motherTonguePrefLabel(AppLocalizations l10n, String v) => switch (v) {
      'Same Mother Tongue' => l10n.prefTongueSame,
      'Tamil' => l10n.langTamil,
      'Telugu' => l10n.langTelugu,
      'Hindi' => l10n.langHindi,
      'Any' => l10n.commonAny,
      _ => v,
    };

String maritalStatusPrefLabel(AppLocalizations l10n, String v) => switch (v) {
      'Never Married' => l10n.maritalNeverMarried,
      'Doesn\'t Matter' => l10n.prefMaritalDoesntMatter,
      'Any' => l10n.commonAny,
      _ => v,
    };

/// `'Any'` -> localized, everything else (numeric ranges) kept as-is.
String anyOrSelfLabel(AppLocalizations l10n, String v) => v == 'Any' ? l10n.commonAny : v;
