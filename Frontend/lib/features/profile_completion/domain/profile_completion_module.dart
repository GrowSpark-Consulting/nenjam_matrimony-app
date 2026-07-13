import '../../astro/domain/models/compatibility_result.dart';
import '../../psychology/domain/models/personality_result.dart';
import '../../registration/domain/models/profile_draft.dart';

/// Everything a [ProfileCompletionModule] might need to evaluate itself.
///
/// [personalityResult]/[horoscopeSummary] are unused by today's 5 modules —
/// they're threaded through now so a future module (e.g. a Psychology
/// Assessment module) can read them without changing this class's shape or
/// the aggregator that builds it.
class ProfileCompletionContext {
  final ProfileDraft draft;
  final PersonalityResult? personalityResult;
  final HoroscopeSummary? horoscopeSummary;

  const ProfileCompletionContext({
    required this.draft,
    this.personalityResult,
    this.horoscopeSummary,
  });
}

/// One module's evaluation result.
class ModuleStatus {
  final bool isComplete;

  /// 0.0-1.0 — partial credit toward this module's own weight.
  final double progress;

  /// Wizard step to jump into for "improve this", if applicable.
  final int? wizardStep;

  const ModuleStatus({
    required this.isComplete,
    required this.progress,
    this.wizardStep,
  });
}

/// A single, independently-scored slice of profile completeness.
///
/// Adding a new module (Psychology Assessment, Voice Introduction, ...)
/// means writing one small class implementing this and adding it to
/// [profileCompletionModules] — the aggregator never needs to change.
abstract class ProfileCompletionModule {
  const ProfileCompletionModule();

  /// Stable identifier, also used to resolve display copy in the UI layer.
  String get id;

  /// This module's share of the overall 0-100 score. All *active* modules'
  /// weights should sum to 100.
  double get weight;

  ModuleStatus evaluate(ProfileCompletionContext context);
}
