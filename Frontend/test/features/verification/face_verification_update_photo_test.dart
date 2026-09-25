import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nenjam_matrimony/core/permissions/app_permission_service.dart';
import 'package:nenjam_matrimony/core/permissions/nm_permission.dart';
import 'package:nenjam_matrimony/core/services/face_liveness/face_liveness_launcher.dart';
import 'package:nenjam_matrimony/core/services/media/attachment_picker.dart';
import 'package:nenjam_matrimony/core/services/media/crop_service.dart';
import 'package:nenjam_matrimony/features/profile_photos/presentation/providers/primary_photo_updater.dart';
import 'package:nenjam_matrimony/features/verification/domain/models/face_verification.dart';
import 'package:nenjam_matrimony/features/verification/domain/repositories/face_verification_repository.dart';
import 'package:nenjam_matrimony/features/verification/presentation/pages/face_verification_page.dart';
import 'package:nenjam_matrimony/features/verification/presentation/providers/face_verification_providers.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// "Update main photo" on the mismatch card: runs the existing photo pipeline
/// in place, then clears the failed-match result — without leaving the page
/// or touching verification status.

class _FakeRepository implements FaceVerificationRepository {
  _FakeRepository({required this.completeResult});

  final FaceVerificationResult completeResult;

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
  }) async => completeResult;
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

/// Stands in for the real updater so the pick → crop → upload pipeline's
/// *contract* is asserted without driving platform channels.
class _FakeUpdater implements PrimaryPhotoUpdater {
  _FakeUpdater(this.result, {this.delay});

  final PrimaryPhotoUpdateResult result;
  final Duration? delay;

  int calls = 0;
  ImageSource? requestedSource;

  @override
  Future<PrimaryPhotoUpdateResult> pickAndUpload({
    required BuildContext context,
    ImageSource source = ImageSource.gallery,
    AttachmentPicker? picker,
    CropService cropService = const CropService(),
  }) async {
    calls++;
    requestedSource = source;
    if (delay != null) await Future<void>.delayed(delay!);
    return result;
  }
}

Widget _harness({
  required FaceVerificationRepository repository,
  required FaceLivenessLauncher launcher,
  required PrimaryPhotoUpdater updater,
}) {
  return ProviderScope(
    overrides: [
      faceVerificationRepositoryProvider.overrideWithValue(repository),
      faceLivenessLauncherProvider.overrideWithValue(launcher),
      appPermissionServiceProvider.overrideWithValue(_GrantedPermissions()),
      primaryPhotoUpdaterProvider.overrideWithValue(updater),
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

const _mismatch = FaceVerificationResult(
  attemptId: 'attempt-1',
  verified: false,
  reason: FaceVerificationFailureReason.failedMatch,
  canRetry: true,
  attemptsRemainingToday: 2,
);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(FaceVerificationPage)));

/// Drives a real attempt to a FAILED_MATCH so the mismatch card is showing.
Future<void> _reachMismatch(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final l10n = _l10n(tester);
  await tester.tap(find.byType(Checkbox));
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.faceVerificationCta));
  await tester.pumpAndSettle();
  expect(find.text(l10n.faceVerificationFailedMatch), findsOneWidget);
}

void main() {
  testWidgets('tapping Update main photo runs the photo flow from the gallery', (
    tester,
  ) async {
    final updater = _FakeUpdater(const PrimaryPhotoUpdateResult.success());
    await tester.pumpWidget(
      _harness(
        repository: _FakeRepository(completeResult: _mismatch),
        launcher: _FakeLauncher(),
        updater: updater,
      ),
    );
    await _reachMismatch(tester);
    final l10n = _l10n(tester);

    await tester.tap(find.text(l10n.faceVerificationUpdatePhoto));
    await tester.pumpAndSettle();

    expect(updater.calls, 1);
    // Straight to the gallery — no source-choice detour, no navigation.
    expect(updater.requestedSource, ImageSource.gallery);
  });

  testWidgets('successful update clears FAILED_MATCH and keeps the user here', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        repository: _FakeRepository(completeResult: _mismatch),
        launcher: _FakeLauncher(),
        updater: _FakeUpdater(const PrimaryPhotoUpdateResult.success()),
      ),
    );
    await _reachMismatch(tester);
    final l10n = _l10n(tester);

    await tester.tap(find.text(l10n.faceVerificationUpdatePhoto));
    await tester.pumpAndSettle();

    // Back to the initial state: no mismatch card, no error card at all.
    expect(find.text(l10n.faceVerificationFailedMatch), findsNothing);
    expect(find.text(l10n.faceVerificationUpdatePhoto), findsNothing);

    // Still on Face Verification, with the CTA available for another attempt.
    expect(find.byType(FaceVerificationPage), findsOneWidget);
    expect(find.text(l10n.faceVerificationCta), findsOneWidget);
  });

  testWidgets('successful update does not launch liveness by itself', (
    tester,
  ) async {
    final launcher = _FakeLauncher();
    await tester.pumpWidget(
      _harness(
        repository: _FakeRepository(completeResult: _mismatch),
        launcher: launcher,
        updater: _FakeUpdater(const PrimaryPhotoUpdateResult.success()),
      ),
    );
    await _reachMismatch(tester);
    expect(launcher.startCalls, 1, reason: 'the attempt that failed to match');

    await tester.tap(find.text(_l10n(tester).faceVerificationUpdatePhoto));
    await tester.pumpAndSettle();

    // The photo update must not trigger a new AWS session on its own.
    expect(launcher.startCalls, 1);
  });

  testWidgets('Verify with Selfie still works after a successful update', (
    tester,
  ) async {
    final launcher = _FakeLauncher();
    await tester.pumpWidget(
      _harness(
        repository: _FakeRepository(completeResult: _mismatch),
        launcher: launcher,
        updater: _FakeUpdater(const PrimaryPhotoUpdateResult.success()),
      ),
    );
    await _reachMismatch(tester);
    final l10n = _l10n(tester);

    await tester.tap(find.text(l10n.faceVerificationUpdatePhoto));
    await tester.pumpAndSettle();

    // reset() clears only the flow result; the consent tick is the widget's
    // own state and survives, so the CTA is immediately usable again.
    await tester.tap(find.text(l10n.faceVerificationCta));
    await tester.pumpAndSettle();

    expect(launcher.startCalls, 2);
  });

  testWidgets('failed upload keeps the user here, shows an error, allows retry', (
    tester,
  ) async {
    final updater = _FakeUpdater(
      const PrimaryPhotoUpdateResult(
        PrimaryPhotoUpdateStatus.failure,
        message: 'Cannot upload more than 6 photos.',
      ),
    );
    await tester.pumpWidget(
      _harness(
        repository: _FakeRepository(completeResult: _mismatch),
        launcher: _FakeLauncher(),
        updater: updater,
      ),
    );
    await _reachMismatch(tester);
    final l10n = _l10n(tester);

    await tester.tap(find.text(l10n.faceVerificationUpdatePhoto));
    await tester.pumpAndSettle();

    // Backend's own wording, surfaced verbatim.
    expect(find.text('Cannot upload more than 6 photos.'), findsOneWidget);

    // Verification status untouched: the mismatch card is still showing, and
    // the action is tappable again.
    expect(find.byType(FaceVerificationPage), findsOneWidget);
    expect(find.text(l10n.faceVerificationFailedMatch), findsOneWidget);

    await tester.tap(find.text(l10n.faceVerificationUpdatePhoto));
    await tester.pumpAndSettle();
    expect(updater.calls, 2, reason: 'retry must be allowed');
  });

  testWidgets('cancelling the picker leaves the mismatch card untouched', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        repository: _FakeRepository(completeResult: _mismatch),
        launcher: _FakeLauncher(),
        updater: _FakeUpdater(const PrimaryPhotoUpdateResult.cancelled()),
      ),
    );
    await _reachMismatch(tester);
    final l10n = _l10n(tester);

    await tester.tap(find.text(l10n.faceVerificationUpdatePhoto));
    await tester.pumpAndSettle();

    // A cancel is not an error: no snack bar, and nothing was cleared.
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text(l10n.faceVerificationFailedMatch), findsOneWidget);
  });

  testWidgets('upload in flight disables the action and blocks liveness', (
    tester,
  ) async {
    final launcher = _FakeLauncher();
    final updater = _FakeUpdater(
      const PrimaryPhotoUpdateResult.success(),
      delay: const Duration(milliseconds: 300),
    );
    await tester.pumpWidget(
      _harness(
        repository: _FakeRepository(completeResult: _mismatch),
        launcher: launcher,
        updater: updater,
      ),
    );
    await _reachMismatch(tester);
    final l10n = _l10n(tester);
    expect(launcher.startCalls, 1);

    await tester.tap(find.text(l10n.faceVerificationUpdatePhoto));
    await tester.pump(); // enter the uploading state, don't settle

    // Spinner replaces the label, so a second tap cannot find it.
    expect(find.text(l10n.faceVerificationUpdatePhoto), findsNothing);
    expect(
      find.descendant(
        of: find.byType(TextButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    // Starting liveness mid-upload must not be possible.
    await tester.tap(find.text(l10n.faceVerificationCta), warnIfMissed: false);
    await tester.pump();
    expect(launcher.startCalls, 1);

    await tester.pumpAndSettle();
    expect(updater.calls, 1, reason: 'no duplicate upload');
  });

  testWidgets('the page never navigates away during a photo update', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        repository: _FakeRepository(completeResult: _mismatch),
        launcher: _FakeLauncher(),
        updater: _FakeUpdater(const PrimaryPhotoUpdateResult.success()),
      ),
    );
    await _reachMismatch(tester);

    await tester.tap(find.text(_l10n(tester).faceVerificationUpdatePhoto));
    await tester.pumpAndSettle();

    // No route to registration/OTP/profile-completion/Discover was pushed:
    // the Face Verification page is still the one and only thing on screen.
    expect(find.byType(FaceVerificationPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
