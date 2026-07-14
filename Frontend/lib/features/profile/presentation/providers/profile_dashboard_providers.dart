import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../registration/domain/models/profile_draft.dart';
import '../../../registration/presentation/providers/registration_provider.dart';

/// Ambient (not-mid-session) snapshot of the signed-in user's saved profile
/// data, for read-only display on the Profile dashboard.
///
/// Deliberately calls [RegistrationRepository.getDraft] directly rather than
/// `RegistrationNotifier.startEditMode()`, so simply viewing the dashboard
/// never flips `profileFlowModeProvider` or overwrites an in-progress edit
/// session sitting in `registrationProvider` — same rationale documented on
/// `profileCompletenessSnapshotProvider`, which depends on this provider
/// instead of fetching the draft a second time.
final myProfileDraftProvider = FutureProvider.autoDispose<ProfileDraft>((
  ref,
) async {
  final json = await ref.watch(registrationRepositoryProvider).getDraft();
  return ProfileDraft.fromJson(json);
});
