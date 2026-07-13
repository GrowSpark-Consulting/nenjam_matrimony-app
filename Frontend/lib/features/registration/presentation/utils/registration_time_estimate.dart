import '../../../../l10n/app_localizations.dart';

/// Rough seconds-to-complete for each of the 12 wizard steps, used only to
/// render an encouraging "About N min left" estimate. Purely presentational
/// — never persisted, never affects [ProfileDraft] or backend sync.
const List<int> _secondsPerStep = [
  70, // Basic Info
  40, // Religion
  30, // Language
  50, // Location
  60, // Education
  45, // Physical
  60, // Lifestyle
  60, // Family
  50, // Horoscope
  50, // Partner Preference
  40, // Photos
  25, // Verification
];

/// Estimated time left to finish the wizard from [currentStep] (0-indexed),
/// summing the current step and everything after it.
Duration estimatedTimeRemaining(int currentStep) {
  var totalSeconds = 0;
  for (var i = currentStep; i < _secondsPerStep.length; i++) {
    totalSeconds += _secondsPerStep[i];
  }
  return Duration(seconds: totalSeconds);
}

/// Formats [estimatedTimeRemaining] into a friendly label.
String estimatedTimeRemainingLabel(AppLocalizations l10n, int currentStep) {
  final remaining = estimatedTimeRemaining(currentStep);
  final minutes = (remaining.inSeconds / 60).round();
  if (minutes < 1) {
    return l10n.registrationTimeRemainingLessThanMinute;
  }
  return l10n.registrationTimeRemainingMinutes(minutes);
}
