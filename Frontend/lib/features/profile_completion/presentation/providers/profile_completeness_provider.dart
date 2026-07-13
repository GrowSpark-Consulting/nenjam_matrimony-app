import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../registration/domain/models/profile_draft.dart';
import '../../../registration/presentation/providers/registration_provider.dart';
import '../../domain/profile_completion_aggregator.dart';
import '../../domain/profile_completion_module.dart';

/// Ambient (not-mid-session) snapshot of profile completeness — for the
/// drawer and the Profile Completion screen. Deliberately calls
/// [RegistrationRepository.getDraft] directly rather than
/// `RegistrationNotifier.startEditMode()`, so it never flips
/// `profileFlowModeProvider` or overwrites an in-progress edit session
/// sitting in `registrationProvider`. See plan doc "Critical gap" section.
final profileCompletenessSnapshotProvider =
    FutureProvider.autoDispose<ProfileCompleteness>((ref) async {
  final json = await ref.read(registrationRepositoryProvider).getDraft();
  final draft = ProfileDraft.fromJson(json);
  return aggregateProfileCompletion(ProfileCompletionContext(draft: draft));
});
