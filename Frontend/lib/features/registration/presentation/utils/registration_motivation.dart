import '../../../../l10n/app_localizations.dart';

/// A fixed, deterministic 1-per-step encouragement caption — no shuffling or
/// local state, so "changes every step" and "never repeats within one pass
/// through the wizard" both hold trivially.
String motivationCaption(AppLocalizations l10n, int stepIndex) {
  return switch (stepIndex) {
    0 => l10n.registrationMotivationStep1,
    1 => l10n.registrationMotivationStep2,
    2 => l10n.registrationMotivationStep3,
    3 => l10n.registrationMotivationStep4,
    4 => l10n.registrationMotivationStep5,
    5 => l10n.registrationMotivationStep6,
    6 => l10n.registrationMotivationStep7,
    7 => l10n.registrationMotivationStep8,
    8 => l10n.registrationMotivationStep9,
    9 => l10n.registrationMotivationStep10,
    10 => l10n.registrationMotivationStep11,
    _ => l10n.registrationMotivationStep12,
  };
}
