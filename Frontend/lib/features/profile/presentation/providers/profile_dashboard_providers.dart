import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../registration/domain/models/profile_draft.dart';
import '../../../registration/presentation/providers/registration_provider.dart';

/// Single fetch of the signed-in user's saved profile (`GET /profiles/draft`),
/// shared by every dashboard derivation below so the draft is never fetched
/// more than once per load. Invalidate THIS to refresh the whole dashboard
/// (draft fields + backend completion) in one shot — see ProfilePage.initState.
///
/// Deliberately calls [RegistrationRepository.getDraft] directly rather than
/// `RegistrationNotifier.startEditMode()`, so simply viewing the dashboard
/// never flips `profileFlowModeProvider` or overwrites an in-progress edit
/// session sitting in `registrationProvider`.
///
/// NOT `autoDispose`, deliberately. Its consumers are inherently transient —
/// ProfileMenuPage and ProfilePage both unmount on back — so under
/// `autoDispose` the last listener disappeared on every close and the next
/// open re-issued an identical `GET /profiles/draft`. Open the profile menu →
/// back → open Profile → back → open the menu was four requests for one
/// unchanged resource.
///
/// Freshness does not depend on that teardown: every path that actually
/// changes the draft invalidates this provider explicitly — ProfilePage's
/// initState, ProfileReviewPage, ProfileWizardPage's edit-mode save, and the
/// profile menu's own pull-to-refresh/retry.
final profileDraftResponseProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(registrationRepositoryProvider).getDraft();
});

/// Ambient (not-mid-session) snapshot of the user's saved profile data, for
/// read-only display on the Profile dashboard. Derived from the shared
/// [profileDraftResponseProvider] fetch.
final myProfileDraftProvider = FutureProvider.autoDispose<ProfileDraft>((
  ref,
) async {
  final json = await ref.watch(profileDraftResponseProvider.future);
  return ProfileDraft.fromJson(json);
});

/// The **backend-computed** profile completion percentage (the single source
/// of truth for "how complete am I"), read straight off the same
/// `GET /profiles/draft` response's `completionPercentage`. Displayed on the
/// Profile dashboard so the figure there always matches what the backend
/// computed — never a separately recomputed number.
final backendProfileCompletionProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final json = await ref.watch(profileDraftResponseProvider.future);
  return (json['completionPercentage'] as num?)?.round() ?? 0;
});
