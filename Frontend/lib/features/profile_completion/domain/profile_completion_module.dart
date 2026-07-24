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
