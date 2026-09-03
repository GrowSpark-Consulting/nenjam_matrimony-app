import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/account_availability.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/pages/login_page.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/pages/registration_landing_page.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/utils/post_auth_destination.dart';
import 'package:nenjam_matrimony/features/profile/data/repositories/api_profile_repository.dart';
import 'package:nenjam_matrimony/features/profile/domain/models/profile.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_providers.dart';
import 'package:nenjam_matrimony/features/registration/data/repositories/registration_repository.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_contact_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import 'post_auth_google_support.dart';

/// "Sign up with Email must never land on Login."
///
/// The landing screen once pushed [LoginPage] from its sign-up buttons
/// (`context.push(RouteNames.login, extra: {'tab': 1, ...})`), so choosing
/// Sign up with Email genuinely did open the login form. That is gone — the
/// button routes into onboarding — and these are what stop it coming back,
/// through the real widgets and the real router rather than by reading the
/// source.
///
/// Login remains reachable from signup in exactly one place, deliberately:
/// the "Log In" button inside the Email + Mobile step's account-exists
/// notice, which is a member's own tap on a screen that has just been told
/// the address is taken. That case is pinned here too, so tightening the
/// rule can never take the existing-account escape hatch with it.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await storageService.init();
  });

  // ─── New Email Signup, and the paths that must stay unchanged ───────

  group('the sign-up buttons route into onboarding, not into Login', () {
    testWidgets('new Email Signup opens Profile For', (tester) async {
      final router = await _pumpLanding(tester);
      final l10n = await _l10n();

      await tester.tap(find.text(l10n.registrationLandingSignUpEmail));
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.createProfileFor);
    });

    testWidgets('new Email Signup NEVER resolves to Login', (tester) async {
      final router = await _pumpLanding(tester);
      final l10n = await _l10n();

      await tester.tap(find.text(l10n.registrationLandingSignUpEmail));
      await tester.pumpAndSettle();

      expect(
        router.state.matchedLocation,
        isNot(anyOf(RouteNames.login, RouteNames.loginForm)),
        reason: 'signup intent must survive the tap — this is the bug',
      );
      expect(find.byType(LoginPage), findsNothing);
    });

    testWidgets('Email Signup starts CREATE mode on a clean draft',
        (tester) async {
      // The intent is not only a route: onboarding has to begin on this
      // member's own draft rather than whatever the last session left in
      // memory. Both sign-up buttons call startCreateMode() for that.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(registrationProvider.notifier)
          .applyOnboardingAbout('left over from a previous session');

      final router = await _pumpLanding(tester, container: container);
      final l10n = await _l10n();
      await tester.tap(find.text(l10n.registrationLandingSignUpEmail));
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.createProfileFor);
      expect(container.read(registrationProvider).lifestyleDetails.aboutMe, '');
    });

    testWidgets('Mobile Signup still opens Profile For, unchanged',
        (tester) async {
      final router = await _pumpLanding(tester);
      final l10n = await _l10n();

      await tester.tap(find.text(l10n.registrationLandingSignUpMobile));
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.createProfileFor);
    });

    testWidgets('Log In is the only button that opens the login form',
        (tester) async {
      final router = await _pumpLanding(tester);
      final l10n = await _l10n();

      await tester.tap(find.text(l10n.authLogin));
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.loginForm);
      expect(find.byType(LoginPage), findsOneWidget);
    });
  });

  // ─── Email Signup against an account that already exists ────────────

  group('Email Signup against an existing account', () {
    testWidgets('is refused as an existing account, not silently continued',
        (tester) async {
      final router = await _pumpContactStep(
        tester,
        availability: _StubAvailability(
          const AccountAvailability(emailExists: true, phoneExists: false),
        ),
      );
      final l10n = await _l10n();

      await _fillContact(tester);
      await tester.tap(find.text(l10n.onboardingContactSubmit));
      await tester.pumpAndSettle();

      // Still on the step, told what is wrong, and NOT moved on to the next
      // one — moving on is what would create the duplicate.
      expect(router.state.matchedLocation, RouteNames.onboardingContact);
      expect(find.text(l10n.accountExistsTitle), findsOneWidget);
      expect(find.text(l10n.accountExistsEmail), findsOneWidget);
    });

    testWidgets('reaches Login only when the member taps Log In',
        (tester) async {
      final router = await _pumpContactStep(
        tester,
        availability: _StubAvailability(
          const AccountAvailability(emailExists: true, phoneExists: false),
        ),
      );
      final l10n = await _l10n();

      await _fillContact(tester);
      await tester.tap(find.text(l10n.onboardingContactSubmit));
      await tester.pumpAndSettle();
      // The notice is on screen and the route has not moved on its own.
      expect(router.state.matchedLocation, RouteNames.onboardingContact);

      await tester.tap(find.text(l10n.accountExistsLogIn));
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, RouteNames.loginForm);
    });

    testWidgets('a free address continues the signup instead', (tester) async {
      final router = await _pumpContactStep(
        tester,
        availability: _StubAvailability(
          const AccountAvailability(emailExists: false, phoneExists: false),
        ),
      );
      final l10n = await _l10n();

      await _fillContact(tester);
      await tester.tap(find.text(l10n.onboardingContactSubmit));
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.profileBasics);
      expect(find.text(l10n.accountExistsTitle), findsNothing);
    });

    testWidgets('a lookup that fails refuses rather than signing up',
        (tester) async {
      final router = await _pumpContactStep(
        tester,
        availability: _StubAvailability(null),
      );
      final l10n = await _l10n();

      await _fillContact(tester);
      await tester.tap(find.text(l10n.onboardingContactSubmit));
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.onboardingContact);
      expect(find.text(l10n.accountCheckFailed), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
    });
  });

  // ─── The resolver every authenticated path routes through ───────────

  group('the resolver an email login routes through', () {
    test('an established account goes to Discover', () async {
      expect(
        await _resolve(hasFinalizedProfile: true, draft: _unusedDraft),
        RouteNames.discover,
      );
    });

    test('a half-finished signup resumes its own step', () async {
      expect(
        await _resolve(
          hasFinalizedProfile: false,
          draft: () async => googleDraft(annualIncome: '', aboutMe: ''),
        ),
        RouteNames.onboardingIncome,
      );
    });

    test('an account that has answered nothing opens Profile For', () async {
      expect(
        await _resolve(
          hasFinalizedProfile: false,
          draft: () async => emptyDraft(),
        ),
        RouteNames.createProfileFor,
      );
    });

    test('no account state resolves to Login, ever', () async {
      // The resolver is the one place every authenticated path asks where to
      // go. If Login is not in its range then no post-auth navigation can
      // produce it — which is the invariant the reported bug would violate.
      final drafts = <Future<Map<String, dynamic>> Function()>[
        () async => emptyDraft(),
        () async => googleDraft(gender: ''),
        () async => googleDraft(firstName: '', lastName: '', dob: ''),
        () async => googleDraft(religion: '', community: '', livingIn: ''),
        () async => googleDraft(state: '', city: ''),
        () async => googleDraft(maritalStatus: '', height: ''),
        () async => googleDraft(qualification: ''),
        () async => googleDraft(annualIncome: ''),
        () async => googleDraft(aboutMe: ''),
        () async => googleDraft(),
        () async => throw Exception('backend unreachable'),
      ];

      for (final draft in drafts) {
        expect(
          await _resolve(hasFinalizedProfile: false, draft: draft),
          isNot(anyOf(RouteNames.login, RouteNames.loginForm)),
          reason: 'PostAuthDestination must never answer Login',
        );
      }
      expect(
        await _resolve(hasFinalizedProfile: true, draft: _unusedDraft),
        isNot(anyOf(RouteNames.login, RouteNames.loginForm)),
      );
    });
  });
}

// ─── Harness ──────────────────────────────────────────────────────────

Future<AppLocalizations> _l10n() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<Map<String, dynamic>> _unusedDraft() =>
    throw StateError('the draft must not be needed');

/// The landing screen under a router carrying the routes its buttons use,
/// plus `/login` → `/login/form` exactly as the real router redirects it —
/// so a regression that sends signup to either spelling is caught.
Future<GoRouter> _pumpLanding(
  WidgetTester tester, {
  ProviderContainer? container,
}) async {
  final router = GoRouter(
    initialLocation: RouteNames.registrationLanding,
    routes: [
      GoRoute(
        path: RouteNames.registrationLanding,
        builder: (_, __) => const RegistrationLandingPage(),
      ),
      GoRoute(
        path: RouteNames.createProfileFor,
        builder: (_, __) => const Scaffold(body: Text('profile for')),
      ),
      GoRoute(
        path: RouteNames.language,
        builder: (_, __) => const Scaffold(body: Text('language')),
      ),
      GoRoute(
        path: RouteNames.login,
        redirect: (_, __) => RouteNames.loginForm,
      ),
      GoRoute(
        path: RouteNames.loginForm,
        builder: (_, __) => const LoginPage(),
      ),
    ],
  );

  final app = MaterialApp.router(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
  );

  await tester.pumpWidget(
    container == null
        ? ProviderScope(child: app)
        : UncontrolledProviderScope(container: container, child: app),
  );
  await tester.pumpAndSettle();
  return router;
}

/// The Email + Mobile step with a canned account-exists verdict.
Future<GoRouter> _pumpContactStep(
  WidgetTester tester, {
  required AccountAvailabilityChecker availability,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      accountAvailabilityProvider.overrideWithValue(availability),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: RouteNames.onboardingContact,
    routes: [
      GoRoute(
        path: RouteNames.onboardingContact,
        builder: (_, __) => const OnboardingContactPage(),
      ),
      GoRoute(
        path: RouteNames.profileBasics,
        builder: (_, __) => const Scaffold(body: Text('basics')),
      ),
      GoRoute(
        path: RouteNames.onboardingReligion,
        builder: (_, __) => const Scaffold(body: Text('religion')),
      ),
      GoRoute(
        path: RouteNames.login,
        redirect: (_, __) => RouteNames.loginForm,
      ),
      GoRoute(
        path: RouteNames.loginForm,
        builder: (_, __) => const LoginPage(),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _fillContact(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'new.member@example.com');
  await tester.enterText(fields.at(1), '9876543210');
  await tester.pumpAndSettle();
}

Future<String> _resolve({
  required bool hasFinalizedProfile,
  required Future<Map<String, dynamic>> Function() draft,
}) async {
  final container = ProviderContainer(
    overrides: [
      registrationRepositoryProvider.overrideWithValue(_DraftOnly(draft)),
      profileRepositoryProvider
          .overrideWithValue(_MyProfile(hasFinalizedProfile)),
      firebaseAuthServiceProvider
          .overrideWithValue(GoogleSignedInAuthService()),
    ],
  );
  addTearDown(container.dispose);
  return container.read(postAuthDestinationProvider).resolve();
}

/// Answers whatever verdict the test wants; `null` models the lookup that
/// could not be completed, which must never read as "available".
class _StubAvailability implements AccountAvailabilityChecker {
  _StubAvailability(this._verdict);

  final AccountAvailability? _verdict;

  @override
  Future<AccountAvailability> check({
    required String email,
    required String phoneE164,
  }) async {
    final verdict = _verdict;
    if (verdict == null) throw const AccountAvailabilityUnavailable();
    return verdict;
  }
}

class _DraftOnly implements RegistrationRepository {
  _DraftOnly(this._draft);

  final Future<Map<String, dynamic>> Function() _draft;

  @override
  Future<Map<String, dynamic>> getDraft() => _draft();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MyProfile implements ApiProfileRepository {
  _MyProfile(this.exists);

  final bool exists;

  @override
  Future<Profile> getMyProfile() async {
    if (!exists) throw Exception('404 — no profile for this account');
    return Profile.fromJson(const {
      'firstName': 'Existing',
      'currentState': 'Karnataka',
      'currentCity': 'Bangalore',
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
