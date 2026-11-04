import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/features/profile/presentation/pages/profile_page.dart';
import 'package:nenjam_matrimony/features/registration/data/repositories/registration_repository.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/features/verification/domain/models/face_verification.dart';
import 'package:nenjam_matrimony/features/verification/domain/repositories/face_verification_repository.dart';
import 'package:nenjam_matrimony/features/verification/presentation/pages/face_verification_page.dart';
import 'package:nenjam_matrimony/features/verification/presentation/providers/face_verification_providers.dart';
import 'package:nenjam_matrimony/features/verification/presentation/widgets/face_verification_card.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget-level coverage for the conditional selfie requirement: the profile
/// tile, the Verification Center card, and the face page itself, for Myself,
/// every other relation, and a referral-created profile.

class _Draft implements RegistrationRepository {
  _Draft(this.relation);
  final String relation;

  @override
  Future<Map<String, dynamic>> getDraft() async => {
    'data': {
      'basicDetails': {'profileCreatedFor': relation},
    },
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Counts every verification call so "no API for non-Myself" is observable.
class _Face implements FaceVerificationRepository {
  static int stateCalls = 0;
  static int sessionCalls = 0;

  @override
  Future<FaceVerificationState> getState() async {
    stateCalls++;
    return const FaceVerificationState(
      status: FaceVerificationStatus.unverified,
      verifiedAt: null,
      canStart: true,
      blockedReason: null,
      attemptsRemainingToday: 3,
      retryAfter: null,
    );
  }

  @override
  Future<LivenessSessionTicket> startSession({required bool consent}) {
    sessionCalls++;
    throw UnimplementedError();
  }

  @override
  Future<FaceVerificationResult> complete({
    required String attemptId,
    ClientLivenessOutcome? clientOutcome,
    String? clientErrorCode,
  }) => throw UnimplementedError();
}

List<Override> _overrides(String relation) => [
  registrationRepositoryProvider.overrideWithValue(_Draft(relation)),
  faceVerificationRepositoryProvider.overrideWithValue(_Face()),
];

Widget _app(Widget home, String relation, {GoRouter? router}) {
  const delegates = [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
  return ProviderScope(
    overrides: _overrides(relation),
    child: router == null
        ? MaterialApp(
            localizationsDelegates: delegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: home,
          )
        : MaterialApp.router(
            localizationsDelegates: delegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
  );
}

/// '/' is a stub home; [RouteNames.faceVerification] is the real page;
/// [RouteNames.discover] is where a redirect with nothing to pop lands.
GoRouter _router(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(path: '/', builder: (_, _) => const Text('home-stub')),
    GoRoute(
      path: RouteNames.discover,
      builder: (_, _) => const Text('discover-stub'),
    ),
    GoRoute(
      path: RouteNames.faceVerification,
      builder: (_, _) => const FaceVerificationPage(),
    ),
  ],
);

const _others = ['Son', 'Daughter', 'Brother', 'Sister', 'Friend', 'Relative'];

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await storageService.init();
  });
  setUp(() {
    _Face.stateCalls = 0;
    _Face.sessionCalls = 0;
  });
  tearDown(() async => storageService.setReferralCreatedProfile(false));

  group('Verification Center card', () {
    Future<void> pumpCard(WidgetTester t, String relation) async {
      await t.pumpWidget(
        _app(const Scaffold(body: FaceVerificationCard()), relation),
      );
      await t.pumpAndSettle();
    }

    testWidgets('Myself: shown, status requested (behaviour unchanged)', (
      t,
    ) async {
      await pumpCard(t, 'Myself');
      expect(find.byType(Card), findsOneWidget);
      expect(find.byIcon(Icons.face_rounded), findsOneWidget);
      expect(_Face.stateCalls, greaterThan(0));
    });

    for (final r in _others) {
      testWidgets('$r: hidden, no API', (t) async {
        await pumpCard(t, r);
        expect(find.byType(Card), findsNothing);
        expect(_Face.stateCalls, 0);
      });
    }

    testWidgets('referral-created (stored as Myself): hidden, no API', (
      t,
    ) async {
      await storageService.setReferralCreatedProfile(true);
      await pumpCard(t, 'Myself');
      expect(find.byType(Card), findsNothing);
      expect(_Face.stateCalls, 0);
    });
  });

  group('Face-verification page', () {
    testWidgets('Myself: stays on the page; nothing is called until tapped', (
      t,
    ) async {
      final router = _router(RouteNames.faceVerification);
      await t.pumpWidget(_app(const SizedBox(), 'Myself', router: router));
      await t.pumpAndSettle();
      expect(find.byType(FaceVerificationPage), findsOneWidget);
      expect(find.text('discover-stub'), findsNothing);
      expect(_Face.sessionCalls, 0);
    });

    for (final r in _others) {
      testWidgets('$r, direct navigation: sent on to Discover, no API', (
        t,
      ) async {
        final router = _router(RouteNames.faceVerification);
        await t.pumpWidget(_app(const SizedBox(), r, router: router));
        await t.pumpAndSettle();
        expect(find.byType(FaceVerificationPage), findsNothing);
        expect(find.text('discover-stub'), findsOneWidget);
        expect(_Face.stateCalls, 0);
        expect(_Face.sessionCalls, 0);
      });
    }

    testWidgets('Son, pushed from a screen: pops back to it', (t) async {
      final router = _router('/');
      await t.pumpWidget(_app(const SizedBox(), 'Son', router: router));
      await t.pumpAndSettle();
      unawaited(router.push(RouteNames.faceVerification));
      await t.pumpAndSettle();
      expect(find.byType(FaceVerificationPage), findsNothing);
      expect(find.text('home-stub'), findsOneWidget);
      expect(_Face.sessionCalls, 0);
    });

    testWidgets('referral-created, direct navigation: sent on, no API', (
      t,
    ) async {
      await storageService.setReferralCreatedProfile(true);
      final router = _router(RouteNames.faceVerification);
      await t.pumpWidget(_app(const SizedBox(), 'Myself', router: router));
      await t.pumpAndSettle();
      expect(find.byType(FaceVerificationPage), findsNothing);
      expect(find.text('discover-stub'), findsOneWidget);
      expect(_Face.stateCalls, 0);
    });
  });

  group('Profile page Face Match tile', () {
    Future<AppLocalizations> pumpProfile(WidgetTester t, String relation) async {
      t.view.physicalSize = const Size(900, 6000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(const ProfilePage(), relation));
      // The dashboard has endless shimmer/fade animations, so pumpAndSettle
      // never settles; a few bounded pumps let the async providers resolve.
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 500));
      }
      return AppLocalizations.of(t.element(find.byType(ProfilePage)));
    }

    testWidgets('Myself: tile present and status requested', (t) async {
      final l10n = await pumpProfile(t, 'Myself');
      expect(find.text(l10n.fieldFaceMatch, skipOffstage: false),
          findsOneWidget);
      expect(_Face.stateCalls, greaterThan(0));
    });

    for (final r in _others) {
      testWidgets('$r: tile absent, no API', (t) async {
        final l10n = await pumpProfile(t, r);
        expect(find.text(l10n.fieldFaceMatch, skipOffstage: false),
            findsNothing);
        expect(_Face.stateCalls, 0);
      });
    }

    testWidgets('referral-created: tile absent, no API', (t) async {
      await storageService.setReferralCreatedProfile(true);
      final l10n = await pumpProfile(t, 'Myself');
      expect(find.text(l10n.fieldFaceMatch, skipOffstage: false),
          findsNothing);
      expect(_Face.stateCalls, 0);
    });
  });
}
