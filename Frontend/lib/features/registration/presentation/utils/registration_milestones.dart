/// Pure UI mapping of wizard step indices to human-friendly journey
/// milestones. Purely presentational — never persisted, never read by
/// [RegistrationNotifier]/[ProfileDraft].
library;

import '../../../../l10n/app_localizations.dart';

/// The 6 milestones shown in [RegistrationJourneyHeader], in order.
enum RegistrationMilestone {
  gettingStarted,
  aboutYou,
  yourWorld,
  lifestyle,
  compatibility,
  ready,
}

/// Inclusive step-index ranges for each milestone, aligned with
/// [ProfileDraft.totalSteps] (13 steps, index 0-12).
///
/// `compatibility` spans Horoscope (8) and the Psychological Quiz (9) —
/// both optional, both about deeper-than-demographic matching.
const Map<RegistrationMilestone, (int, int)> registrationMilestoneStepRanges = {
  RegistrationMilestone.gettingStarted: (0, 0),
  RegistrationMilestone.aboutYou: (1, 2),
  RegistrationMilestone.yourWorld: (3, 5),
  RegistrationMilestone.lifestyle: (6, 7),
  RegistrationMilestone.compatibility: (8, 9),
  RegistrationMilestone.ready: (10, 12),
};

/// Returns which milestone a given wizard [step] index belongs to.
RegistrationMilestone milestoneForStep(int step) {
  for (final entry in registrationMilestoneStepRanges.entries) {
    final (start, end) = entry.value;
    if (step >= start && step <= end) return entry.key;
  }
  return RegistrationMilestone.ready;
}

/// Localized emoji + label for a [RegistrationMilestone].
(String, String) milestoneEmojiAndLabel(
  AppLocalizations l10n,
  RegistrationMilestone milestone,
) =>
    switch (milestone) {
      RegistrationMilestone.gettingStarted => (
          '🌱',
          l10n.registrationMilestoneGettingStarted
        ),
      RegistrationMilestone.aboutYou => ('👤', l10n.registrationMilestoneAboutYou),
      RegistrationMilestone.yourWorld => ('🏡', l10n.registrationMilestoneYourWorld),
      RegistrationMilestone.lifestyle => ('❤️', l10n.registrationMilestoneLifestyle),
      RegistrationMilestone.compatibility => (
          '✨',
          l10n.registrationMilestoneCompatibility
        ),
      RegistrationMilestone.ready => ('🎉', l10n.registrationMilestoneReady),
    };
