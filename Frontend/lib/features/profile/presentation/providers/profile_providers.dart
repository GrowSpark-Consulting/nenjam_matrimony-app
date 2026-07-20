import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/repositories/api_profile_repository.dart';
import '../../domain/models/profile.dart';

final profileRepositoryProvider = Provider<ApiProfileRepository>(
  (ref) => ApiProfileRepository(ref.watch(apiClientProvider)),
);

/// The caller's own finalized profile — the single source of truth for
/// [ProfilePage]. Invalidated after a wizard edit session finalizes (see
/// RegistrationNotifier.finalizeToBackend) so the profile screen reflects
/// edits immediately on return, and after photo mutations once those exist.
final myProfileProvider = FutureProvider<Profile>((ref) async {
  return ref.watch(profileRepositoryProvider).getMyProfile();
});
