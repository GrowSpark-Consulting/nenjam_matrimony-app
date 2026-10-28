import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/dummy_otp_session.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/referral/presentation/providers/referral_providers.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_verify_mobile_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../registration/onboarding_test_support.dart';
import 'referral_test_support.dart';

/// Phone and email signups both mint their session on Verify Mobile, so this
/// is where a code entered on the name step attaches: after the session and
/// the save + finalize, never before, and never in the way of finishing.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await storageService.init();
  });

  setUp(() async {
    await storageService.setPendingPhone('+919876543210');
  });

  GoRouter buildRouter() => GoRouter(
    initialLocation: RouteNames.onboardingVerifyMobile,
    routes: [
      GoRoute(
        path: RouteNames.onboardingVerifyMobile,
        builder: (context, state) => const OnboardingVerifyMobilePage(),
      ),
      GoRoute(
        path: RouteNames.discover,
        builder: (context, state) =>
            const Scaffold(body: Text('discover-reached')),
      ),
    ],
  );

  late FakeReferralRepository referrals;
  late InMemoryPendingReferralStore store;

  setUp(() {
    referrals = FakeReferralRepository();
    store = InMemoryPendingReferralStore(kPendingRavi);
  });

  Future<void> finishSignup(
    WidgetTester tester, {
    DummyOtpSessionException? exchangeFailure,
  }) async {
    useTallSurface(tester);
    final container = ProviderContainer(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(
          RecordingRegistrationRepository(),
        ),
        dummyOtpSessionStarterProvider.overrideWithValue(
          _Starter(exchangeFailure),
        ),
        firebaseAuthServiceProvider.overrideWithValue(SignedInAuthService()),
        referralRepositoryProvider.overrideWithValue(referrals),
        pendingReferralStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.pumpAndSettle();
  }

  testWidgets('a finished signup attaches the stored code once', (
    tester,
  ) async {
    await finishSignup(tester);
    expect(find.text('discover-reached'), findsOneWidget);
    expect(referrals.attached, ['NM7K2P9X']);
    expect(store.value, isNull);
  });

  testWidgets('a failed session exchange attaches nothing and keeps the '
      'code', (tester) async {
    await finishSignup(
      tester,
      exchangeFailure: DummyOtpSessionException('refused', statusCode: 403),
    );
    expect(find.text('discover-reached'), findsNothing);
    expect(referrals.attached, isEmpty);
    expect(store.value?.code, 'NM7K2P9X');
  });

  testWidgets('an attach failure does not stop the member reaching the app', (
    tester,
  ) async {
    referrals.onAttach = (_) => throw Exception('offline');
    await finishSignup(tester);
    expect(find.text('discover-reached'), findsOneWidget);
    // Kept for a later retry (cold start), not dropped.
    expect(store.value?.attempts, 1);
    expect(
      find.text(
        "We couldn't apply your referral code yet. We'll try again later.",
      ),
      findsOneWidget,
    );
  });
}

class _Starter implements DummyOtpSessionStarter {
  _Starter(this.failure);

  final DummyOtpSessionException? failure;

  @override
  Future<String> start({required String phoneE164, String? email}) async {
    if (failure != null) throw failure!;
    return 'firebase-uid-1';
  }
}
