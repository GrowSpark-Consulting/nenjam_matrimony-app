import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../profile/presentation/providers/profile_dashboard_providers.dart';
import '../../domain/profile_completion_aggregator.dart';

/// Ambient (not-mid-session) snapshot of profile completeness — for the
/// drawer, the Profile Completion screen, and the Profile dashboard. Built
/// directly from [profileDraftResponseProvider]'s raw `completionPercentage`
/// / `completionBreakdown` fields — the backend's ProfileCompletionService is
/// the only place that ever decides a weight or a completion rule; this
/// provider just shapes that same response for display, so it never fetches
/// the draft a second time and never disagrees with the Profile dashboard.
final profileCompletenessSnapshotProvider =
    FutureProvider.autoDispose<ProfileCompleteness>((ref) async {
  final json = await ref.watch(profileDraftResponseProvider.future);
  final percentage = (json['completionPercentage'] as num?)?.round() ?? 0;
  final breakdown =
      (json['completionBreakdown'] as List?)
          ?.cast<Map<String, dynamic>>() ??
      const <Map<String, dynamic>>[];
  // Both are absent from a response predating the field-level breakdown; the
  // aggregator treats that as "nothing to ask for" rather than nagging.
  final requiredFields =
      (json['requiredFields'] as List?)?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];
  final registrationComplete = json['registrationComplete'] as bool?;

  return profileCompletenessFromBackend(
    percentage,
    breakdown,
    requiredFieldsJson: requiredFields,
    registrationComplete: registrationComplete,
  );
});
