import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/dummy_otp_session.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/local_auth_session.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_verify_mobile_page.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import 'onboarding_test_support.dart';

/// The last screen of signup: **a passed dummy OTP must produce a real
/// Firebase session, and nothing else counts as finishing.**
///
/// This is the seam the whole flow used to be missing. The dummy OTP verifies
/// nothing and mints no credential, so the step recorded a device-local
/// marker and walked the member into the app — with no Firebase account, no
/// `users` row, and every later request authenticating by header or not at
/// all. The exchange with `POST /auth/dummy-otp/session` is what turns a pass
/// into an account; these pin that it happens, that the answers are only sent
/// once it has, and that a failure stops the member here rather than letting
/// them in with nothing behind them.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await storageService.init();
  });

  setUp(() async {
    await storageService.clearLocalSession();
    await storageService.setPendingPhone('+919876543210');
    await storageService.setPendingEmail('member@example.com');
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
          GoRoute(
            path: RouteNames.onboardingContact,
            builder: (context, state) =>
                const Scaffold(body: Text('contact-reached')),
          ),
          GoRoute(
            path: RouteNames.onboardingAbout,
            builder: (context, state) =>
                const Scaffold(body: Text('about-reached')),
          ),
        ],
      );

  /// [signedIn] stands in for what a *successful* exchange leaves behind: a
  /// real Firebase user. The fake starter cannot mint one, and the flush is
  /// gated on there being a session, so a test about what gets sent has to
  /// supply it — see `RegistrationNotifier._hasSession`.
  /// [signedIn] still decides what the *flush* sees, but the auth service is
  /// now always faked: finishing onboarding asks [PostAuthDestination] where
  /// to go (it is the only thing that runs the face verification gate for a
  /// brand-new member — see that call site), and the resolver reads the
  /// Firebase user. Left unoverridden it reaches the real `FirebaseAuth
  /// .instance` and throws `core/no-app` in a test binding.
  ProviderContainer containerWith(
    RecordingRegistrationRepository repository,
    DummyOtpSessionStarter starter, {
    bool signedIn = false,
  }) {
    return ProviderContainer(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(repository),
        dummyOtpSessionStarterProvider.overrideWithValue(starter),
        firebaseAuthServiceProvider.overrideWithValue(
          signedIn ? SignedInAuthService() : SignedOutUntilExchangeAuthService(),
        ),
      ],
    );
  }

  /// Fills the four boxes. [NmOtpInput] submits itself on the last digit, so
  /// this is the whole interaction — the same one a member performs.
  Future<void> enterCode(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.pumpAndSettle();
  }

  testWidgets('a passed code provisions the account and opens Discover', (
    tester,
  ) async {
    useTallSurface(tester);
    final starter = _RecordingStarter();
    final repository = RecordingRegistrationRepository();
    // `signedIn`, because that is what the exchange this test just passed
    // actually leaves behind — and the destination resolver reads the
    // Firebase user to decide where the member goes. Without one it answers
    // "signed out → landing screen", which is right for a signed-out caller
    // but not for the case under test here.
    final container = containerWith(repository, starter, signedIn: true);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();
    await enterCode(tester);

    // The number and the address the member gave are both what the backend is
    // asked to provision — one account, not one per identifier.
    expect(starter.phones, ['+919876543210']);
    expect(starter.emails, ['member@example.com']);
    expect(find.text('discover-reached'), findsOneWidget);
  });

  testWidgets('the draft is flushed once the session is real', (tester) async {
    useTallSurface(tester);
    final starter = _RecordingStarter();
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository, starter, signedIn: true);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();

    // Nothing has been sent yet: onboarding ran signed out from end to end.
    expect(repository.savedSections, isEmpty);

    await enterCode(tester);

    // The flush runs after the exchange, so the answers go out with a real
    // credential attached — which is what finally gives them somewhere to
    // land, and what writes `user_profiles`.
    expect(repository.savedSections, contains('basicDetails'));
  });

  testWidgets('a failed exchange keeps the member here and sends nothing', (
    tester,
  ) async {
    useTallSurface(tester);
    final starter = _RecordingStarter(
      failure: DummyOtpSessionException(
        'Dummy-OTP sign-in is not enabled for this number on this server.',
        statusCode: 403,
      ),
    );
    final repository = RecordingRegistrationRepository();
    // Signed in as far as the flush is concerned, so that "nothing was sent"
    // below is the exchange's doing and not merely a missing session.
    final container = containerWith(repository, starter, signedIn: true);
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container, buildRouter()));
    await tester.pumpAndSettle();
    await enterCode(tester);

    // Not waved through: there is no account behind this member, so walking
    // them into the app is the exact silent half-signup this replaced.
    expect(find.text('discover-reached'), findsNothing);
    expect(repository.savedSections, isEmpty);
    // And they are told why, rather than left looking at a stalled button.
    expect(
      find.text(
        'Dummy-OTP sign-in is not enabled for this number on this server.',
      ),
      findsOneWidget,
    );
    // No fallback to the device-local marker the exchange replaced.
    expect(container.read(localAuthSessionProvider).isActive, isFalse);
  });
}

/// Stands in for the backend exchange, recording the identity it was asked to
/// provision and able to refuse.
class _RecordingStarter implements DummyOtpSessionStarter {
  _RecordingStarter({this.failure});

  final DummyOtpSessionException? failure;
  final List<String> phones = <String>[];
  final List<String?> emails = <String?>[];

  @override
  Future<String> start({required String phoneE164, String? email}) async {
    if (failure != null) throw failure!;
    phones.add(phoneE164);
    emails.add(email);
    return 'firebase-uid-1';
  }
}
