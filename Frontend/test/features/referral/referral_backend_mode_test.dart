import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/auth_token_service.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/referral/data/repositories/api_referral_repository.dart';
import 'package:nenjam_matrimony/features/referral/data/repositories/mock_referral_repository.dart';
import 'package:nenjam_matrimony/features/referral/data/repositories/unavailable_referral_repository.dart';
import 'package:nenjam_matrimony/features/referral/presentation/providers/referral_providers.dart';

/// `REFERRAL_ENDPOINTS_LIVE` across build configurations. `kDebugMode` can't
/// be flipped inside a test run, so the rule is a pure function and each
/// combination is asserted directly; the providers are then checked with the
/// mode overridden.
void main() {
  group('referralBackendMode', () {
    test('debug, flag off → mock', () {
      expect(
        referralBackendMode(endpointsLive: false, debugBuild: true),
        ReferralBackendMode.mock,
      );
    });

    test('release / profile, flag off → off (never the mock)', () {
      expect(
        referralBackendMode(endpointsLive: false, debugBuild: false),
        ReferralBackendMode.off,
      );
    });

    test('flag on → live, in any build', () {
      expect(
        referralBackendMode(endpointsLive: true, debugBuild: false),
        ReferralBackendMode.live,
      );
      expect(
        referralBackendMode(endpointsLive: true, debugBuild: true),
        ReferralBackendMode.live,
      );
    });
  });

  test('this test build does not have the flag set', () {
    // Guards against a CI or local config quietly turning it on.
    expect(kReferralEndpointsLive, isFalse);
  });

  ProviderContainer containerFor(ReferralBackendMode mode) {
    final container = ProviderContainer(
      overrides: [referralBackendModeProvider.overrideWithValue(mode)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('off: no box, no mock, and the repository refuses', () async {
    final c = containerFor(ReferralBackendMode.off);
    expect(c.read(referralCodeEntryEnabledProvider), isFalse);
    final repo = c.read(referralRepositoryProvider);
    expect(repo, isA<UnavailableReferralRepository>());
    await expectLater(repo.validateCode('NM7K2P9X'), throwsStateError);
    await expectLater(repo.attachCode('NM7K2P9X'), throwsStateError);
  });

  test('mock: box shown, mock repository', () {
    final c = containerFor(ReferralBackendMode.mock);
    expect(c.read(referralCodeEntryEnabledProvider), isTrue);
    expect(c.read(referralRepositoryProvider), isA<MockReferralRepository>());
  });

  test('live: box shown, API repository', () {
    // The real repository takes the shared API client, whose provider reads
    // `authTokenServiceProvider`; tests have no Firebase app, so stub it.
    final c = ProviderContainer(
      overrides: [
        referralBackendModeProvider.overrideWithValue(ReferralBackendMode.live),
        authTokenServiceProvider.overrideWithValue(_TokenService()),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(referralCodeEntryEnabledProvider), isTrue);
    expect(c.read(referralRepositoryProvider), isA<ApiReferralRepository>());
  });
}

/// Stands in for the Firebase-backed token service; the repository is only
/// constructed here, never called.
class _TokenService implements AuthTokenService {
  @override
  Future<String?> getFirebaseToken({bool forceRefresh = false}) async =>
      'a-token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
