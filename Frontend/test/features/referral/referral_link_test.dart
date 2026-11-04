import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/firebase_auth_service.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/referral/data/services/link_referral_store.dart';
import 'package:nenjam_matrimony/features/referral/data/services/referral_link_capture.dart';
import 'package:nenjam_matrimony/features/referral/domain/models/referral_models.dart';
import 'package:nenjam_matrimony/features/referral/presentation/providers/referral_providers.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_name_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import '../registration/onboarding_test_support.dart';
import 'referral_test_support.dart';

/// A shared link (`/?ref=CODE`) feeding the existing "Have a referral code?"
/// box. Fake repository and in-memory stores: this proves the app logic, not
/// the live backend or a real browser's sessionStorage.
void main() {
  group('referralFromQuery', () {
    test('reads a plain code', () {
      expect(
        referralFromQuery({
          'ref': ['NM7K2P9X'],
        }),
        'NM7K2P9X',
      );
    });

    test('missing, empty and blank are ignored', () {
      expect(referralFromQuery({}), isNull);
      expect(referralFromQuery({'ref': <String>[]}), isNull);
      expect(
        referralFromQuery({
          'ref': [''],
        }),
        isNull,
      );
      expect(
        referralFromQuery({
          'ref': ['   '],
        }),
        isNull,
      );
    });

    test('duplicates: the first value wins', () {
      expect(
        referralFromQuery({
          'ref': ['NM7K2P9X', 'NM222222'],
        }),
        'NM7K2P9X',
      );
      // A blank first value is not skipped over to a later one.
      expect(
        referralFromQuery({
          'ref': ['', 'NM7K2P9X'],
        }),
        isNull,
      );
    });

    test('markup, over-long and odd characters are dropped', () {
      expect(
        referralFromQuery({
          'ref': ['<script>alert(1)</script>'],
        }),
        isNull,
      );
      expect(
        referralFromQuery({
          'ref': ['NM' * 20],
        }),
        isNull,
      );
      expect(
        referralFromQuery({
          'ref': ['NM7K2P9X/../x'],
        }),
        isNull,
      );
    });

    test('a well-shaped but wrong code is passed on (the box reports it)', () {
      expect(
        referralFromQuery({
          'ref': ['NM-PRIYA'],
        }),
        'NM-PRIYA',
      );
    });
  });

  test('captureReferralFromUrl stores the first ref, nothing without one', () {
    final store = MemoryLinkReferralStore();
    captureReferralFromUrl(Uri.parse('https://x.test/?utm=a'), store);
    expect(store.read(), isNull);
    captureReferralFromUrl(
      Uri.parse('https://x.test/?ref=NM7K2P9X&ref=NM222222'),
      store,
    );
    expect(store.read(), 'NM7K2P9X');
  });

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
  late MemoryLinkReferralStore linkStore;

  setUp(() {
    repository = FakeReferralRepository(
      onValidate: (code) => ReferralCodeValidation(
        valid: code == 'NM7K2P9X',
        agentDisplayName: code == 'NM7K2P9X' ? 'Ravi K.' : null,
      ),
    );
    store = InMemoryPendingReferralStore();
    linkStore = MemoryLinkReferralStore();
  });

  ProviderContainer containerWith({bool signedIn = false}) {
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
        linkReferralStoreProvider.overrideWithValue(linkStore),
        referralCodeEntryEnabledProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// A fresh container/widget tree over the SAME stores = a page refresh.
  Future<void> open(WidgetTester tester, {bool signedIn = false}) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      harness(containerWith(signedIn: signedIn), buildRouter()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a valid ?ref fills the box and applies it with the normal '
      'validate call, once', (tester) async {
    linkStore.write('NM7K2P9X');
    await open(tester);

    expect(repository.validated, ['NM7K2P9X']);
    expect(find.text('Referred by Ravi K.'), findsOneWidget);
    expect(store.value?.code, 'NM7K2P9X');
    // Handed over to the persistent store; no second copy to re-apply.
    expect(linkStore.read(), isNull);
  });

  testWidgets('an invalid ?ref shows the normal error, does not block '
      'signup and is not re-validated on return', (tester) async {
    linkStore.write('NM222222');
    await open(tester);

    expect(repository.validated, ['NM222222']);
    expect(find.text("This code isn't valid"), findsOneWidget);
    expect(store.value, isNull);

    await fillNameStep(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('religion-reached'), findsOneWidget);

    // Back to the step (refresh): no second validation of the bad code.
    await open(tester);
    expect(repository.validated, ['NM222222']);
  });

  testWidgets('a malformed ?ref (wrong shape) shows the error without an '
      'API call', (tester) async {
    linkStore.write('NM-PRIYA');
    await open(tester);

    expect(repository.validated, isEmpty);
    expect(find.text("This code isn't valid"), findsOneWidget);
    expect(linkStore.read(), isNull);
  });

  testWidgets('when the check cannot run, the link code survives a refresh '
      'and is applied once it can', (tester) async {
    repository.onValidate = (_) => throw Exception('offline');
    linkStore.write('NM7K2P9X');
    await open(tester);

    expect(find.textContaining("couldn't check this code"), findsOneWidget);
    expect(linkStore.read(), 'NM7K2P9X');

    // Refresh with the network back.
    repository.onValidate = (c) =>
        const ReferralCodeValidation(valid: true, agentDisplayName: 'Ravi K.');
    await open(tester);
    expect(find.text('Referred by Ravi K.'), findsOneWidget);
    expect(store.value?.code, 'NM7K2P9X');
    expect(linkStore.read(), isNull);
  });

  testWidgets('a code the member changed is not overwritten by the link', (
    tester,
  ) async {
    repository.onValidate = (_) => throw ApiException(
      429,
      'x',
      code: 'RATE_LIMITED',
      retryAfterSeconds: 5,
    );
    linkStore.write('NM7K2P9X');
    await open(tester);
    expect(linkStore.read(), 'NM7K2P9X');

    await tester.enterText(find.byType(TextFormField).last, 'NM222222');
    await tester.pumpAndSettle();
    expect(linkStore.read(), isNull);

    repository.onValidate = (_) =>
        const ReferralCodeValidation(valid: true, agentDisplayName: 'Ravi K.');
    final before = repository.validated.length;
    await open(tester);
    expect(repository.validated.length, before);
    expect(find.text('Referred by Ravi K.'), findsNothing);
  });

  testWidgets('a code already applied is not replaced by a link', (
    tester,
  ) async {
    store.value = kPendingRavi;
    linkStore.write('NM222222');
    await open(tester);

    expect(repository.validated, isEmpty);
    expect(find.text('Referred by Ravi K.'), findsOneWidget);
    expect(store.value?.code, 'NM7K2P9X');
  });

  testWidgets('the link copy is cleared once signup attaches the code', (
    tester,
  ) async {
    store.value = kPendingRavi;
    linkStore.write('NM7K2P9X');
    await open(tester, signedIn: true);

    await fillNameStep(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(repository.attached, ['NM7K2P9X']);
    expect(store.value, isNull);
    expect(linkStore.read(), isNull);
  });

  testWidgets('a lower-case ?ref is normalised and validated once', (
    tester,
  ) async {
    linkStore.write('nm7k2p9x');
    await open(tester);
    expect(repository.validated, ['NM7K2P9X']);
    expect(find.text('Referred by Ravi K.'), findsOneWidget);
  });

  test('contract format: NM + 6 of [2-9A-HJKMNP-Z], case-insensitive', () {
    expect(normalizeReferralCode('NM7K2P9X'), 'NM7K2P9X');
    expect(normalizeReferralCode('nm7k2p9x'), 'NM7K2P9X');
    expect(normalizeReferralCode('NM0K2P9X'), isNull); // 0 excluded
    expect(normalizeReferralCode('NM1K2P9X'), isNull); // 1 excluded
    expect(normalizeReferralCode('NMOK2P9X'), isNull); // O excluded
    expect(normalizeReferralCode('NM7K2P9'), isNull); // too short
  });

  testWidgets('no ?ref: box stays collapsed and nothing is validated', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Have a referral code?'), findsOneWidget);
    expect(repository.validated, isEmpty);
  });
}

class _SignedOutAuthService implements FirebaseAuthService {
  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
