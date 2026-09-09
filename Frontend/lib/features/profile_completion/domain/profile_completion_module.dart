/// One module's identity as scored by the backend's ProfileCompletionService
/// (see `backend/apps/api/src/modules/profiles/services/profile-completion.
/// service.ts`) — the single authoritative place weights and completion
/// rules are decided. This is a plain data holder, not a calculator: the
/// Flutter app never re-derives a weight or a completion rule of its own,
/// only displays whatever the backend's `completionBreakdown` already
/// computed.
class ModuleBreakdown {
  final String id;
  final double weight;

  const ModuleBreakdown({required this.id, required this.weight});
}

/// One module's evaluation result, as reported by the backend.
class ModuleStatus {
  final bool isComplete;

  /// Wizard step to jump into for "improve this", if applicable.
  final int? wizardStep;

  const ModuleStatus({required this.isComplete, this.wizardStep});
}

/// One registration answer, as reported by the backend's `requiredFields`.
///
/// The registration slice is scored over 21 items — the 20 counted draft
/// fields plus at least one profile photo — so this is what lets the screen
/// say *which* answers are missing instead of only that the slice is
/// incomplete, and open the step that fixes each.
///
/// Sub-community is the one [optional] entry: it is listed so it can be shown
/// in place, but it never counts toward the score in either direction.
class RequiredFieldStatus {
  /// Stable id: 'firstName', 'workIndustry', 'photo', ...
  final String id;

  /// Draft section it belongs to, or 'photos' for the profile photo.
  final String section;

  /// Wizard step page that edits it.
  final int wizardStep;

  final bool isComplete;
  final bool optional;

  const RequiredFieldStatus({
    required this.id,
    required this.section,
    required this.wizardStep,
    required this.isComplete,
    required this.optional,
  });

  /// Tolerant of a response that predates this field list: anything missing
  /// or mistyped yields a complete, non-optional entry rather than throwing,
  /// so an old server can never crash the completion screen.
  factory RequiredFieldStatus.fromJson(Map<String, dynamic> json) {
    return RequiredFieldStatus(
      id: json['id'] as String? ?? '',
      section: json['section'] as String? ?? '',
      wizardStep: (json['wizardStep'] as num?)?.toInt() ?? 0,
      isComplete: json['isComplete'] as bool? ?? true,
      optional: json['optional'] as bool? ?? false,
    );
  }
}
