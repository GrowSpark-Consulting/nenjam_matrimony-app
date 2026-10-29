import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/firebase_auth_service.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/referral/domain/models/referral_models.dart';
import 'package:nenjam_matrimony/features/referral/presentation/providers/referral_providers.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_name_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import '../registration/onboarding_test_support.dart';
import 'referral_test_support.dart';

/// "Have a referral code?" on the name and date of birth step, against a
/// fake repository — not the backend (its endpoints are not built yet).
void main() {
  GoRouter buildRouter() => GoRouter(
    initialLocation: RouteNames.onboardingNameDob,
    routes: [
      GoRoute(
        path: RouteNames.onboardingNameDob,
        builder: (context, state) => const OnboardingNamePage(),
      ),
      GoRoute(
        path: RouteNames.onboardingReligion,
        builder: (context, state) =>
            const Scaffold(body: Text('religion-reached')),
      ),
    ],
  );

  late FakeReferralRepository repository;
  late InMemoryPendingReferralStore store;

  setUp(() {
    repository = FakeReferralRepository(
      onValidate: (code) => ReferralCodeValidation(
        valid: code == 'NM7K2P9X',
        agentDisplayName: code == 'NM7K2P9X' ? 'Ravi K.' : null,
      ),
    );
    store = InMemoryPendingReferralStore();
  });

  ProviderContainer containerWith({required bool signedIn}) {
    final container = ProviderContainer(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(
          RecordingRegistrationRepository(),
        ),
        firebaseAuthServiceProvider.overrideWithValue(
          signedIn ? SignedInAuthService() : _SignedOutAuthService(),
        ),
        referralRepositoryProvider.overrideWithValue(repository),
        pendingReferralStoreProvider.overrideWithValue(store),
        referralCodeEntryEnabledProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> open(WidgetTester tester, ProviderContainer container) async {
    useTallSurface(tester);
    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();
  }

  Future<void> applyCode(WidgetTester tester, String typed) async {
    await tester.tap(find.text('Have a referral code?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, typed);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
  }

  testWidgets('no referral code entered: collapsed, and Continue works with '
      'nothing validated, stored or attached', (tester) async {
    final container = containerWith(signedIn: true);
    await open(tester, container);

    expect(find.text('Have a referral code?'), findsOneWidget);
    await fillNameStep(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('religion-reached'), findsOneWidget);
    expect(repository.validated, isEmpty);
    expect(repository.attached, isEmpty);
    expect(store.value, isNull);
  });

  testWidgets('a valid code typed with spaces and hyphens is normalised, '
      'validated once and kept', (tester) async {
    await open(tester, containerWith(signedIn: false));

    await applyCode(tester, ' nm-7k2 p9x ');

    expect(repository.validated, ['NM7K2P9X']);
    expect(find.text('Referred by Ravi K.'), findsOneWidget);
    expect(store.value?.code, 'NM7K2P9X');
    expect(store.value?.agentDisplayName, 'Ravi K.');
  });

  testWidgets('an invalid code shows the one generic message and is not '
      'kept', (tester) async {
    await open(tester, containerWith(signedIn: false));

    await applyCode(tester, 'NM2222222');
    // Too long: never sent.
    expect(repository.validated, isEmpty);
    expect(find.text("This code isn't valid"), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).last, 'NM222222');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(repository.validated, ['NM222222']);
    expect(find.text("This code isn't valid"), findsOneWidget);
    expect(store.value, isNull);
  });

  testWidgets('429 says to wait, with the Retry-After seconds', (tester) async {
    repository.onValidate = (_) => throw ApiException(
      429,
      'x',
      code: 'RATE_LIMITED',
      retryAfterSeconds: 30,
    );
    await open(tester, containerWith(signedIn: false));

    await applyCode(tester, 'NM7K2P9X');
    expect(find.text('Too many tries, please wait 30 seconds'), findsOneWidget);
    expect(store.value, isNull);
  });

  testWidgets('a code check that cannot reach the server does not block '
      'Continue', (tester) async {
    repository.onValidate = (_) => throw Exception('offline');
    await open(tester, containerWith(signedIn: false));

    await applyCode(tester, 'NM7K2P9X');
    expect(find.textContaining("couldn't check this code"), findsOneWidget);

    await fillNameStep(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('religion-reached'), findsOneWidget);
  });

  testWidgets('phone / email signup (no session yet): Continue keeps the '
      'code and attaches nothing', (tester) async {
    await open(tester, containerWith(signedIn: false));

    await applyCode(tester, 'NM7K2P9X');
    await fillNameStep(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('religion-reached'), findsOneWidget);
    expect(repository.attached, isEmpty);
    expect(store.value?.code, 'NM7K2P9X');
  });

  testWidgets('Google signup (already signed in): Continue attaches the code '
      'once and clears it', (tester) async {
    await open(tester, containerWith(signedIn: true));

    await applyCode(tester, 'NM7K2P9X');
    await fillNameStep(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('religion-reached'), findsOneWidget);
    expect(repository.attached, ['NM7K2P9X']);
    expect(store.value, isNull);
    expect(find.text('Referral code applied.'), findsOneWidget);
  });

  testWidgets('an attach failure is a gentle message and signup carries on', (
    tester,
  ) async {
    repository.onAttach = (_) =>
        throw ApiException(409, 'x', code: 'ALREADY_ATTRIBUTED');
    await open(tester, containerWith(signedIn: true));

    await applyCode(tester, 'NM7K2P9X');
    await fillNameStep(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('religion-reached'), findsOneWidget);
    expect(
      find.text('Your account is already linked to a referral code.'),
      findsOneWidget,
    );
  });

  testWidgets('reopening the step (Back, or a relaunch) shows the code kept, '
      'and Remove forgets it', (tester) async {
    store.value = kPendingRavi;
    await open(tester, containerWith(signedIn: false));

    expect(find.text('Referred by Ravi K.'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(store.value, isNull);
    expect(find.text('Referred by Ravi K.'), findsNothing);
  });

  testWidgets('hidden when referral entry is disabled (release builds until '
      'the endpoints are live)', (tester) async {
    final container = ProviderContainer(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(
          RecordingRegistrationRepository(),
        ),
        firebaseAuthServiceProvider.overrideWithValue(SignedInAuthService()),
        pendingReferralStoreProvider.overrideWithValue(store),
        referralCodeEntryEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);
    await open(tester, container);
    expect(find.text('Have a referral code?'), findsNothing);
  });
}

class _SignedOutAuthService implements FirebaseAuthService {
  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
