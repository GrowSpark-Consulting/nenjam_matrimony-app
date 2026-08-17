import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../domain/repositories/settings_repository.dart';

/// Wires the existing (previously dormant) [SettingsRepositoryImpl] into
/// Riverpod. `deleteAccount()` calls the real, working `DELETE
/// /settings/delete-account`; `getSettings()`/`updatePrivacySettings()` call
/// real endpoints too, but the backend's `settings` controller only
/// implements delete-account today, so those two currently 404 — surfaced
/// as a real error, never faked. Shared by Settings (Delete Account) and
/// Privacy (visibility toggles).
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepositoryImpl(ref.watch(apiClientProvider)),
);

/// The signed-in user's raw settings payload — shape is undefined until the
/// backend's `settings` controller grows beyond delete-account, so this
/// stays a raw map rather than a typed entity (see
/// [SettingsRepository.getSettings]'s doc comment).
final mySettingsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
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
});
