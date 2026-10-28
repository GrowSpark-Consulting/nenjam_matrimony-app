import 'dart:convert';

import '../../../../core/services/storage_service.dart';
import '../../domain/models/referral_models.dart';

/// Where a validated referral code waits between the name and date of birth
/// step and the member's first authenticated call.
///
/// It has to outlive the remaining signup steps, a process kill and the
/// sign-in itself, so it is on disk — the code only, never anything about
/// the member. Cleared on sign-out (`StorageService.clearUserData`).
abstract class PendingReferralStore {
  PendingReferralCode? read();
  Future<void> write(PendingReferralCode code);
  Future<void> clear();
}

/// [PendingReferralStore] over the app's [StorageService].
///
/// Never throws: a storage that is unavailable reads as "no code" and drops
/// writes, because a referral code must never be the reason a signup step
/// fails.
class StoragePendingReferralStore implements PendingReferralStore {
  StoragePendingReferralStore(this._storage);

  final StorageService _storage;

  @override
  PendingReferralCode? read() {
    try {
      final json = _storage.pendingReferralCodeJson;
      if (json == null) return null;
      return PendingReferralCode.tryFromJson(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(PendingReferralCode code) async {
    try {
      await _storage.setPendingReferralCodeJson(jsonEncode(code.toJson()));
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.clearPendingReferralCode();
    } catch (_) {}
  }
}
