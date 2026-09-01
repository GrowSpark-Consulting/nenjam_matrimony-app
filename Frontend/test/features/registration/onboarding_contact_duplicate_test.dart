import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/widgets/buttons/gradient_button.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/account_availability.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_contact_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import 'onboarding_test_support.dart';

/// The rule: **an email or mobile that already belongs to an account stops
/// signup at the Email + Mobile step**, before any profile is created, and
/// points the member at login instead.
///
/// The case that matters most is the third one — a lookup that *fails* must
/// also stop signup. Treating "could not check" as "available" is precisely
/// how duplicate accounts get created.
class _FakeChecker implements AccountAvailabilityChecker {
  _FakeChecker({
    this.emailExists = false,
    this.phoneExists = false,
    this.throws = false,
  });

  bool emailExists;
  bool phoneExists;
  bool throws;

  /// When set, lookups block until the test completes it — the only way to
  /// have two taps genuinely overlap rather than run back to back.
  Completer<void>? gate;

  /// Every lookup this checker was asked to perform, so a test can assert
  /// how many happened and with exactly what values.
  final List<({String email, String phone})> calls = [];

  @override
  Future<AccountAvailability> check({
    required String email,
    required String phoneE164,
  }) async {
    calls.add((email: email, phone: phoneE164));
    if (gate != null) await gate!.future;
    if (throws) throw const AccountAvailabilityUnavailable();
    return AccountAvailability(
      emailExists: emailExists,
      phoneExists: phoneExists,
    );
  }
}

void main() {
  GoRouter buildRouter() {
    return GoRouter(
      initialLocation: RouteNames.onboardingContact,
      routes: [
        GoRoute(
          path: RouteNames.onboardingContact,
          builder: (context, state) => const OnboardingContactPage(),
        ),
        GoRoute(
          path: RouteNames.profileBasics,
          builder: (context, state) =>
              const Scaffold(body: Text('next-step-reached')),
        ),
        GoRoute(
          path: RouteNames.login,
          builder: (context, state) =>
              const Scaffold(body: Text('login-reached')),
        ),
      ],
    );
  }

  ProviderContainer containerWith(_FakeChecker checker) => ProviderContainer(
        overrides: [
          accountAvailabilityProvider.overrideWithValue(checker),
          registrationRepositoryProvider
              .overrideWithValue(RecordingRegistrationRepository()),
        ],
      );

  Future<void> fillIn(
    WidgetTester tester, {
    String email = 'new@example.com',
    String mobile = '9876543210',
  }) async {
    await tester.enterText(find.byType(TextField).first, email);
    await tester.enterText(find.byType(TextField).last, mobile);
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
  }

  testWidgets('1 — a free email and mobile continue to the next step', (
    tester,
  ) async {
    useTallSurface(tester);
    final checker = _FakeChecker();
    final container = containerWith(checker);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();
    await fillIn(tester);
    await submit(tester);

    expect(checker.calls, hasLength(1));
    expect(find.text('next-step-reached'), findsOneWidget);
  });

  testWidgets('2 — an existing email stops signup and offers login', (
    tester,
  ) async {
    useTallSurface(tester);
    final container = containerWith(_FakeChecker(emailExists: true));
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();
    await fillIn(tester, email: 'existing@example.com');
    await submit(tester);

    expect(find.text('Account already exists'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('next-step-reached'), findsNothing);
  });

  testWidgets('3 — an existing mobile stops signup and offers login', (
    tester,
  ) async {
    useTallSurface(tester);
    final container = containerWith(_FakeChecker(phoneExists: true));
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();
    await fillIn(tester);
    await submit(tester);

    expect(find.text('Account already exists'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('next-step-reached'), findsNothing);
  });

  testWidgets('4 — both taken reads as one account, not two problems', (
    tester,
  ) async {
    useTallSurface(tester);
    final container =
        containerWith(_FakeChecker(emailExists: true, phoneExists: true));
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();
    await fillIn(tester);
    await submit(tester);

    expect(find.text('Account already exists'), findsOneWidget);
    expect(
      find.textContaining('email or mobile number is already registered'),
      findsOneWidget,
    );
    expect(find.text('next-step-reached'), findsNothing);
  });

  testWidgets('5 — a failed lookup blocks signup rather than assuming free', (
    tester,
  ) async {
    useTallSurface(tester);
    final container = containerWith(_FakeChecker(throws: true));
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();
    await fillIn(tester);
    await submit(tester);

    expect(
      find.textContaining('Unable to check your account'),
      findsOneWidget,
    );
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('next-step-reached'), findsNothing);
  });

  testWidgets('6 & 7 — the lookup gets normalized values', (tester) async {
    useTallSurface(tester);
    final checker = _FakeChecker();
    final container = containerWith(checker);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();
    await fillIn(tester, email: '  TestUser@Example.COM  ');
    await submit(tester);

    // The screen trims; the API layer lowercases to match what Firebase
    // stores, so both representations of the same address resolve alike.
    expect(checker.calls.single.email, 'TestUser@Example.COM');
    expect(
      ApiAccountAvailabilityChecker.normalizeEmail(checker.calls.single.email),
      'testuser@example.com',
    );
    // Mobile goes as E.164, the representation the whole app stores.
    expect(checker.calls.single.phone, '+919876543210');
  });

  testWidgets('8 — correcting a duplicate re-checks instead of reusing it', (
    tester,
  ) async {
    useTallSurface(tester);
    final checker = _FakeChecker(emailExists: true);
    final container = containerWith(checker);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();
    await fillIn(tester, email: 'existing@example.com');
    await submit(tester);
    expect(find.text('Account already exists'), findsOneWidget);

    // Editing the field clears the verdict about the old value...
    checker.emailExists = false;
    await tester.enterText(find.byType(TextField).first, 'new@example.com');
    await tester.pumpAndSettle();
    expect(find.text('Account already exists'), findsNothing);

    // ...and the next Continue asks again rather than reusing the answer.
    await submit(tester);
    expect(checker.calls, hasLength(2));
    expect(checker.calls.last.email, 'new@example.com');
    expect(find.text('next-step-reached'), findsOneWidget);
  });

  testWidgets('9 — rapid taps produce one lookup and one navigation', (
    tester,
  ) async {
    useTallSurface(tester);
    final checker = _FakeChecker();
    final container = containerWith(checker);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();
    await fillIn(tester);

    // Hold the first lookup open so the later taps land while it is still
    // in flight — which is the situation the guard exists for.
    final gate = Completer<void>();
    checker.gate = gate;

    // Found by type, not by label: the label changes to "Checking…" the
    // moment the first tap lands, and a label finder would simply stop
    // matching rather than proving the later taps were ignored.
    final submitButton = find.byType(NmGradientButton);
    await tester.tap(submitButton);
    await tester.pump();

    // The CTA is in its loading state, which is what tells the member the
    // tap registered — the label is replaced by a spinner.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Submit'), findsNothing);

    await tester.tap(submitButton, warnIfMissed: false);
    await tester.tap(submitButton, warnIfMissed: false);
    await tester.pump();

    // Still exactly one request, even though three taps were delivered.
    expect(checker.calls, hasLength(1));

    gate.complete();
    await tester.pumpAndSettle();

    expect(checker.calls, hasLength(1));
    expect(find.text('next-step-reached'), findsOneWidget);
  });

  testWidgets('the Log In button opens the existing login screen', (
    tester,
  ) async {
    useTallSurface(tester);
    final container = containerWith(_FakeChecker(emailExists: true));
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();
    await fillIn(tester);
    await submit(tester);

    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();
    expect(find.text('login-reached'), findsOneWidget);
  });
}
