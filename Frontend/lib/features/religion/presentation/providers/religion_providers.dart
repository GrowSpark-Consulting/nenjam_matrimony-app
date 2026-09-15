import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/religion_repository.dart';
import '../../domain/models/religion_models.dart';

final religionRepositoryProvider = Provider<ReligionRepository>((ref) {
  return ReligionRepository(ref.watch(apiClientProvider));
});

/// The religion list. Reference data, so it is kept alive for the session
/// rather than re-fetched every time the Religion step is rebuilt.
final religionsProvider = FutureProvider<List<ReligionOption>>((ref) {
  ref.keepAlive();
  return ref.watch(religionRepositoryProvider).religions();
});

/// Communities within a religion, keyed by its code.
///
/// `.family` rather than one provider holding a map, for the same reasons the
/// location cascade uses it:
///
///  * Each religion's list loads, errors and retries independently.
///  * Riverpod caches them separately, so going back to a religion already
///    viewed is instant and issues no second request.
///  * **Stale responses cannot overwrite a newer selection.** The widget
///    watches `communitiesProvider(religionCode)`, so a slow response for
///    religion A resolves into A's provider, which nothing is watching any
///    more once the member has moved to B. There is no shared mutable slot
///    for a late reply to land in, and so no sequence-number bookkeeping to
///    get wrong.
///
/// An empty `religionCode` returns an empty list without touching the
/// network: the child level is only ever fetched once a parent is chosen.
final communitiesProvider =
    FutureProvider.family<List<ReligionOption>, String>((ref, religionCode) {
  if (religionCode.isEmpty) return Future.value(const <ReligionOption>[]);
  ref.keepAlive();
  return ref.watch(religionRepositoryProvider).communities(religionCode);
});
