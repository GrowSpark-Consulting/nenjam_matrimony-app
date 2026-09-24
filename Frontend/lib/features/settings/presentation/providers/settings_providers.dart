import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../domain/repositories/settings_repository.dart';

/// Wires [SettingsRepositoryImpl] into Riverpod: `DELETE
/// /settings/delete-account`, `GET /settings` and `PATCH /settings/privacy`.
/// Shared by Settings (Delete Account) and Privacy (visibility toggles).
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepositoryImpl(ref.watch(apiClientProvider)),
);

/// The signed-in user's raw settings payload, kept as a map (see
/// [SettingsRepository.getSettings]'s doc comment). Today:
/// `{ isPremium, hideMyProfile, hidePhotosFromNonConnections }` — `isPremium`
/// is derived server-side from the member's subscription, and both privacy
/// flags are the values the backend actually enforces (always false without
/// premium). An older key, `profileVisibleToPremiumOnly`, mirrors
/// `hideMyProfile` for older app builds.
class MySettingsNotifier
    extends AutoDisposeAsyncNotifier<Map<String, dynamic>> {
  @override
  Future<Map<String, dynamic>> build() {
    final cancelToken = CancelToken();
    // Cancels the in-flight request when this provider is disposed — i.e. the
    // moment the screen that asked for it is popped. Without this the response
    // still arrives and is still parsed, only to be discarded, which on a slow
    // connection also keeps competing for bandwidth with whatever the user
    // navigated to instead.
    ref.onDispose(cancelToken.cancel);
    return ref
        .watch(settingsRepositoryProvider)
        .getSettings(cancelToken: cancelToken);
  }

  /// `PATCH /settings/privacy` with only [changes], then adopts the server's
  /// response — the values it confirmed and enforces — as the new state, so
  /// there's no follow-up `GET`. Throws on failure and leaves the state
  /// untouched, so the screen keeps showing what the server last confirmed.
  Future<void> updatePrivacy(Map<String, dynamic> changes) async {
    final confirmed = await ref
        .read(settingsRepositoryProvider)
        .updatePrivacySettings(changes);
    if (confirmed.isEmpty) {
      // No body to adopt — fall back to re-reading rather than guessing.
      ref.invalidateSelf();
      return;
    }
    state = AsyncValue.data(confirmed);
  }
}

final mySettingsProvider =
    AsyncNotifierProvider.autoDispose<MySettingsNotifier, Map<String, dynamic>>(
      MySettingsNotifier.new,
    );
