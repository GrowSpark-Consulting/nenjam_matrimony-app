import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/permissions/app_permission_service.dart';
import 'package:nenjam_matrimony/core/permissions/nm_permission.dart';
import 'package:nenjam_matrimony/core/services/face_liveness/face_liveness_launcher.dart';
import 'package:nenjam_matrimony/features/verification/domain/models/face_verification.dart';
import 'package:nenjam_matrimony/features/verification/domain/repositories/face_verification_repository.dart';
import 'package:nenjam_matrimony/features/verification/presentation/pages/face_verification_page.dart';
import 'package:nenjam_matrimony/features/verification/presentation/providers/face_verification_providers.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Pre-liveness page checks: one viewport, no scroll, and nothing
/// error-shaped before an attempt has actually finished.

class _FakeRepository implements FaceVerificationRepository {
  _FakeRepository({this.completeResult});

  final FaceVerificationResult? completeResult;

  @override
  Future<FaceVerificationState> getState() async => const FaceVerificationState(
    status: FaceVerificationStatus.unverified,
    verifiedAt: null,
    canStart: true,
    blockedReason: null,
    attemptsRemainingToday: 3,
    retryAfter: null,
  );

  @override
  Future<LivenessSessionTicket> startSession({required bool consent}) async {
    return LivenessSessionTicket.fromJson({
      'attemptId': 'attempt-1',
      'sessionId': 'session-1',
      'region': 'ap-south-1',
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 3))
          .toIso8601String(),
      'credentials': {
        'accessKeyId': 'a',
        'secretAccessKey': 'b',
        'sessionToken': 'c',
        'expiration': DateTime.now()
            .add(const Duration(minutes: 15))
            .toIso8601String(),
      },
    });
  }

  @override
  Future<FaceVerificationResult> complete({
    required String attemptId,
    ClientLivenessOutcome? clientOutcome,
    String? clientErrorCode,
  }) async =>
      completeResult ??
      const FaceVerificationResult(
        attemptId: 'attempt-1',
        verified: true,
        reason: null,
        canRetry: false,
        attemptsRemainingToday: 2,
      );
}

class _FakeLauncher implements FaceLivenessLauncher {
  int startCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Future<LivenessCaptureResult> start(LivenessSessionTicket ticket) async {
    startCalls++;
    return const LivenessCaptureResult(
      outcome: ClientLivenessOutcome.completed,
    );
  }
}

class _GrantedPermissions implements AppPermissionService {
  @override
  Future<NmPermissionStatus> statusOf(NmPermission permission) async =>
      NmPermissionStatus.granted;

  @override
  Future<NmPermissionStatus> request(NmPermission permission) async =>
      NmPermissionStatus.granted;

  @override
  Future<bool> openSettings() async => true;
}

Widget _harness({
  required FaceVerificationRepository repository,
  required FaceLivenessLauncher launcher,
}) {
  return ProviderScope(
    overrides: [
      faceVerificationRepositoryProvider.overrideWithValue(repository),
      faceLivenessLauncherProvider.overrideWithValue(launcher),
      appPermissionServiceProvider.overrideWithValue(_GrantedPermissions()),
    ],
    child: const MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: FaceVerificationPage(),
    ),
  );
}

/// Small and normal Android portrait viewports, in logical pixels.
const _viewports = <String, Size>{
  'small (320x568)': Size(320, 568),
  'small-tall (360x640)': Size(360, 640),
  'normal (411x731)': Size(411, 731),
  'normal-tall (412x915)': Size(412, 915),
  // A real 1080x2408 @461dpi device (Redmi Note 11) — the tall case where
  // an uncapped illustration grew to half the screen.
  'tall device (375x809)': Size(375, 809),
};

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(FaceVerificationPage)));

void main() {
  for (final entry in _viewports.entries) {
    testWidgets('fits one viewport with the CTA visible on ${entry.key}', (
      tester,
    ) async {
      _setViewport(tester, entry.value);
      await tester.pumpWidget(
        _harness(repository: _FakeRepository(), launcher: _FakeLauncher()),
      );
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);

      // No scrollable anywhere on the page.
      expect(find.byType(Scrollable), findsNothing);

      for (final text in [
        l10n.faceVerificationTitle,
        l10n.faceVerificationExplanation,
        l10n.faceVerificationConsentShort,
        l10n.faceVerificationCta,
        l10n.faceVerificationPrivacyNote,
      ]) {
        expect(find.text(text), findsOneWidget, reason: '"$text" missing');
      }

      final ctaRect = tester.getRect(find.text(l10n.faceVerificationCta));
      expect(
        ctaRect.bottom,
        lessThanOrEqualTo(entry.value.height),
        reason: 'CTA pushed below the fold on ${entry.key}',
      );
      expect(ctaRect.top, greaterThanOrEqualTo(0.0));

      // The illustration is a medium band, not a screen-filling slab: on a
      // tall device an Expanded slot hands down a tight height that would
      // otherwise override the card's own cap.
      final cardHeight = tester
          .getSize(
            find
                .descendant(
                  of: find.byType(FaceVerificationPage),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          )
          .height;
      expect(
        cardHeight,
        lessThanOrEqualTo(200.0),
        reason: 'illustration exceeded its cap on ${entry.key}',
      );

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no back arrow when the page is the post-OTP gate landing', (
    tester,
  ) async {
    _setViewport(tester, const Size(360, 640));
    await tester.pumpWidget(
      _harness(repository: _FakeRepository(), launcher: _FakeLauncher()),
    );
    await tester.pumpAndSettle();

    // Nothing to pop back to: showing an arrow here would either dead-end
    // or expose Discover behind the unsatisfied verification gate.
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
  });

  testWidgets('back arrow pops when the page was pushed', (tester) async {
    _setViewport(tester, const Size(360, 640));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          faceVerificationRepositoryProvider.overrideWithValue(
            _FakeRepository(),
          ),
          faceLivenessLauncherProvider.overrideWithValue(_FakeLauncher()),
          appPermissionServiceProvider.overrideWithValue(_GrantedPermissions()),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const FaceVerificationPage(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(FaceVerificationPage), findsOneWidget);

    final back = find.byIcon(Icons.arrow_back_rounded);
    expect(back, findsOneWidget);

    await tester.tap(back);
    await tester.pumpAndSettle();

    // Popped back to where it was pushed from — not onward to Discover.
    expect(find.byType(FaceVerificationPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('initial state shows no mismatch or error card', (tester) async {
    _setViewport(tester, const Size(360, 640));
    await tester.pumpWidget(
      _harness(repository: _FakeRepository(), launcher: _FakeLauncher()),
    );
    await tester.pumpAndSettle();

    final l10n = _l10n(tester);

    expect(find.text(l10n.faceVerificationFailedMatch), findsNothing);
    expect(find.text(l10n.faceVerificationFailedGeneric), findsNothing);
    expect(find.text(l10n.faceVerificationNetworkError), findsNothing);
    expect(find.text(l10n.faceVerificationCameraPermissionDenied), findsNothing);
    expect(find.text(l10n.faceVerificationUpdatePhoto), findsNothing);
  });

  testWidgets('mismatch card appears only after a FAILED_MATCH result', (
    tester,
  ) async {
    _setViewport(tester, const Size(360, 640));
    final launcher = _FakeLauncher();
    await tester.pumpWidget(
      _harness(
        repository: _FakeRepository(
          completeResult: const FaceVerificationResult(
            attemptId: 'attempt-1',
            verified: false,
            reason: FaceVerificationFailureReason.failedMatch,
            canRetry: true,
            attemptsRemainingToday: 2,
          ),
        ),
        launcher: launcher,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = _l10n(tester);
    expect(find.text(l10n.faceVerificationFailedMatch), findsNothing);

    // Consent gate, then the CTA launches the existing liveness flow.
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.faceVerificationCta));
    await tester.pumpAndSettle();

    expect(launcher.startCalls, 1, reason: 'AWS liveness flow not launched');
    expect(find.text(l10n.faceVerificationFailedMatch), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
