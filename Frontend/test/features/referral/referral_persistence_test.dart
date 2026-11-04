import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/referral/data/services/pending_referral_store.dart';
import 'package:nenjam_matrimony/features/referral/domain/models/referral_models.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The pending referral code on disk: it survives a restart, belongs to the
/// member who entered it (sign-out removes it), and unusable text never gets
/// in. Real [StorageService] over an in-memory SharedPreferences.
void main() {
  late StorageService storage;
  late StoragePendingReferralStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
    store = StoragePendingReferralStore(storage);
  });

  const code = PendingReferralCode(
    code: 'NM7K2P9X',
    agentDisplayName: 'Ravi K.',
  );

  test(
    'a written code is still there for a fresh store (app restart)',
    () async {
      await store.write(code);

      // A new StorageService + store over the same prefs = a relaunch.
      final relaunched = StorageService();
      await relaunched.init();
      final read = StoragePendingReferralStore(relaunched).read();
      expect(read?.code, 'NM7K2P9X');
      expect(read?.agentDisplayName, 'Ravi K.');
    },
  );

  test('sign-out (clearUserData) removes a code that never attached', () async {
    await store.write(code);
    await storage.clearUserData();
    expect(store.read(), isNull);
  });

  test('sign-out leaves nothing for the next member on this device', () async {
    await store.write(code.withAttempt());
    await storage.clearUserData();
    await store.write(
      const PendingReferralCode(code: 'NM2P3Q4R', agentDisplayName: null),
    );
    // Only the new member's own code is there; no attempts carried over.
    expect(store.read()?.code, 'NM2P3Q4R');
    expect(store.read()?.attempts, 0);
  });

  test('a stored value that is not a valid code reads as no code', () async {
    SharedPreferences.setMockInitialValues({
      'pending_referral_code': '{"code":"hello","agentDisplayName":"X"}',
    });
    final s = StorageService();
    await s.init();
    expect(StoragePendingReferralStore(s).read(), isNull);
  });

  group('normalizeReferralCode on link-shaped input', () {
    // A future link would hand the app text taken from a URL. Whatever the
    // eventual URL shape is, the text must pass through this same gate and
    // only a well-formed code may come out.
    test('a percent-encoded or decorated value is not corrected', () {
      expect(normalizeReferralCode('NM7K2P9X&utm=a'), isNull);
      expect(normalizeReferralCode('NM7K2P9X%20'), isNull);
      expect(normalizeReferralCode('?code=NM7K2P9X'), isNull);
      expect(normalizeReferralCode('javascript:alert(1)'), isNull);
      expect(normalizeReferralCode('NM7K2P9X\u0000'), isNull);
    });

    test('lower-case and hyphenated link text normalises', () {
      expect(normalizeReferralCode('nm7k-2p9x'), 'NM7K2P9X');
      expect(normalizeReferralCode('  NM7K 2P9X '), 'NM7K2P9X');
    });

    test('a very long value is rejected, not truncated', () {
      expect(normalizeReferralCode('NM7K2P9X' * 100), isNull);
    });
  });
}
