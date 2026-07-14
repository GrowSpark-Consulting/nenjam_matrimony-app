import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../profile/presentation/providers/profile_dashboard_providers.dart';
import '../../domain/profile_completion_aggregator.dart';
import '../../domain/profile_completion_module.dart';

/// Ambient (not-mid-session) snapshot of profile completeness — for the
/// drawer, the Profile Completion screen, and the Profile dashboard. Built
/// on [myProfileDraftProvider] (itself a direct `RegistrationRepository
/// .getDraft` call, bypassing `RegistrationNotifier.startEditMode()`) so it
/// never flips `profileFlowModeProvider` or overwrites an in-progress edit
/// session sitting in `registrationProvider`, and so the dashboard and this
/// screen never fetch the draft twice. See plan doc "Critical gap" section.
final profileCompletenessSnapshotProvider =
    FutureProvider.autoDispose<ProfileCompleteness>((ref) async {
  final draft = await ref.watch(myProfileDraftProvider.future);
  return aggregateProfileCompletion(ProfileCompletionContext(draft: draft));
});
