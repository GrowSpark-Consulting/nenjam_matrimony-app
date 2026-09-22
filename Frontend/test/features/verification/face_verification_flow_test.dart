import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/core/permissions/app_permission_service.dart';
import 'package:nenjam_matrimony/core/permissions/nm_permission.dart';
import 'package:nenjam_matrimony/core/services/face_liveness/face_liveness_launcher.dart';
import 'package:nenjam_matrimony/features/verification/domain/models/face_verification.dart';
import 'package:nenjam_matrimony/features/verification/domain/repositories/face_verification_repository.dart';
import 'package:nenjam_matrimony/features/verification/presentation/providers/face_verification_providers.dart';

class _FakeRepository implements FaceVerificationRepository {
  _FakeRepository({
    this.startError,
    this.completeErrors = const [],
    this.completeResult,
  });

  final ApiException? startError;
  final List<Object> completeErrors;
  final FaceVerificationResult? completeResult;
  int startCalls = 0;
  int completeCalls = 0;

  @override
  Future<FaceVerificationState> getState() async {
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
  Future<LivenessSessionTicket> startSession({required bool consent}) async {
    startCalls++;
    if (startError != null) throw startError!;
    return LivenessSessionTicket.fromJson({
      'attemptId': 'attempt-1',
      'sessionId': 'session-1',
      'region': 'ap-south-1',
      'expiresAt': DateTime.now().add(const Duration(minutes: 3)).toIso8601String(),
      'credentials': {
        'accessKeyId': 'a',
        'secretAccessKey': 'b',
        'sessionToken': 'c',
        'expiration': DateTime.now().add(const Duration(minutes: 15)).toIso8601String(),
      },
    });
  }

  @override
  Future<FaceVerificationResult> complete({
    required String attemptId,
    ClientLivenessOutcome? clientOutcome,
    String? clientErrorCode,
  }) async {
    final index = completeCalls;
    completeCalls++;
    if (index < completeErrors.length) {
      final err = completeErrors[index];
      if (err is ApiException) throw err;
      throw err;
    }
    return completeResult ??
        const FaceVerificationResult(
          attemptId: 'attempt-1',
          verified: true,
          reason: null,
          canRetry: false,
          attemptsRemainingToday: 2,
        );
  }
}

class _FakeLauncher implements FaceLivenessLauncher {
  _FakeLauncher(this.result);
  final LivenessCaptureResult result;

  @override
  bool get isSupported => true;

  @override
  Future<LivenessCaptureResult> start(LivenessSessionTicket ticket) async =>
      result;
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

class _DeniedPermissions implements AppPermissionService {
  _DeniedPermissions({this.permanentlyDenied = false});
  final bool permanentlyDenied;

  @override
  Future<NmPermissionStatus> statusOf(NmPermission permission) async =>
      NmPermissionStatus.denied;

  @override
  Future<NmPermissionStatus> request(NmPermission permission) async =>
      permanentlyDenied
          ? NmPermissionStatus.permanentlyDenied
          : NmPermissionStatus.denied;

  @override
  Future<bool> openSettings() async => true;
}

void main() {
  group('FaceVerificationFlowController', () {
    test('happy path: verified', () async {
      final repo = _FakeRepository();
      final container = ProviderContainer(
        overrides: [
          faceVerificationRepositoryProvider.overrideWithValue(repo),
          faceLivenessLauncherProvider.overrideWithValue(
            _FakeLauncher(
              const LivenessCaptureResult(
                outcome: ClientLivenessOutcome.completed,
              ),
            ),
          ),
          appPermissionServiceProvider.overrideWithValue(
            _GrantedPermissions(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(faceVerificationFlowProvider.notifier)
          .startVerification();

      expect(
        container.read(faceVerificationFlowProvider).phase,
        FaceVerificationFlowPhase.verified,
      );
      expect(repo.startCalls, 1);
      expect(repo.completeCalls, 1);
    });

    test('cancel still calls /complete', () async {
      final repo = _FakeRepository(
        completeResult: const FaceVerificationResult(
          attemptId: 'attempt-1',
          verified: false,
          reason: FaceVerificationFailureReason.cancelled,
          canRetry: true,
          attemptsRemainingToday: 2,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          faceVerificationRepositoryProvider.overrideWithValue(repo),
          faceLivenessLauncherProvider.overrideWithValue(
            _FakeLauncher(
              const LivenessCaptureResult(
                outcome: ClientLivenessOutcome.cancelled,
              ),
            ),
          ),
          appPermissionServiceProvider.overrideWithValue(
            _GrantedPermissions(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(faceVerificationFlowProvider.notifier)
          .startVerification();

      expect(repo.completeCalls, 1);
      final state = container.read(faceVerificationFlowProvider);
      expect(state.phase, FaceVerificationFlowPhase.failed);
      expect(state.canRetry, isTrue);
    });

    test('native ERROR still calls /complete and surfaces failed', () async {
      final repo = _FakeRepository(
        completeResult: const FaceVerificationResult(
          attemptId: 'attempt-1',
          verified: false,
          reason: FaceVerificationFailureReason.error,
          canRetry: true,
          attemptsRemainingToday: 2,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          faceVerificationRepositoryProvider.overrideWithValue(repo),
          faceLivenessLauncherProvider.overrideWithValue(
            _FakeLauncher(
              const LivenessCaptureResult(
                outcome: ClientLivenessOutcome.error,
                errorCode: 'CAMERA_ERROR',
              ),
            ),
          ),
          appPermissionServiceProvider.overrideWithValue(
            _GrantedPermissions(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(faceVerificationFlowProvider.notifier)
          .startVerification();

      expect(repo.completeCalls, 1);
      expect(
        container.read(faceVerificationFlowProvider).phase,
        FaceVerificationFlowPhase.failed,
      );
    });

    test('RESULT_NOT_READY retries then succeeds', () async {
      final repo = _FakeRepository(
        completeErrors: [
          ApiException(409, 'not ready', code: 'RESULT_NOT_READY'),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          faceVerificationRepositoryProvider.overrideWithValue(repo),
          faceLivenessLauncherProvider.overrideWithValue(
            _FakeLauncher(
              const LivenessCaptureResult(
                outcome: ClientLivenessOutcome.completed,
              ),
            ),
          ),
          appPermissionServiceProvider.overrideWithValue(
            _GrantedPermissions(),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Keeps the autoDispose notifier alive across the retry's awaited
      // gaps — without an active listener, Riverpod tears it down and
      // resets `state` to a fresh `build()` the moment nothing is watching.
      final sub = container.listen(
        faceVerificationFlowProvider,
        (previous, next) {},
      );
      addTearDown(sub.close);

      await container
          .read(faceVerificationFlowProvider.notifier)
          .startVerification();

      expect(repo.completeCalls, 2);
      expect(
        container.read(faceVerificationFlowProvider).phase,
        FaceVerificationFlowPhase.verified,
      );
    });

    test('blocked codes surface as blocked with the reason', () async {
      final repo = _FakeRepository(
        startError: ApiException(422, 'no photo', code: 'NO_PRIMARY_PHOTO'),
      );
      final container = ProviderContainer(
        overrides: [
          faceVerificationRepositoryProvider.overrideWithValue(repo),
          faceLivenessLauncherProvider.overrideWithValue(
            _FakeLauncher(
              const LivenessCaptureResult(
                outcome: ClientLivenessOutcome.completed,
              ),
            ),
          ),
          appPermissionServiceProvider.overrideWithValue(
            _GrantedPermissions(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(faceVerificationFlowProvider.notifier)
          .startVerification();

      final state = container.read(faceVerificationFlowProvider);
      expect(state.phase, FaceVerificationFlowPhase.blocked);
      expect(state.blockedReason, FaceBlockedReason.noPrimaryPhoto);
      expect(repo.completeCalls, 0);
    });

    test('permission denied creates no session', () async {
      final repo = _FakeRepository();
      final container = ProviderContainer(
        overrides: [
          faceVerificationRepositoryProvider.overrideWithValue(repo),
          faceLivenessLauncherProvider.overrideWithValue(
            _FakeLauncher(
              const LivenessCaptureResult(
                outcome: ClientLivenessOutcome.completed,
              ),
            ),
          ),
          appPermissionServiceProvider.overrideWithValue(
            _DeniedPermissions(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(faceVerificationFlowProvider.notifier)
          .startVerification();

      expect(repo.startCalls, 0);
      expect(
        container.read(faceVerificationFlowProvider).phase,
        FaceVerificationFlowPhase.permissionDenied,
      );
    });

    test('permanently denied permission surfaces the open-settings path',
        () async {
      final repo = _FakeRepository();
      final container = ProviderContainer(
        overrides: [
          faceVerificationRepositoryProvider.overrideWithValue(repo),
          faceLivenessLauncherProvider.overrideWithValue(
            _FakeLauncher(
              const LivenessCaptureResult(
                outcome: ClientLivenessOutcome.completed,
              ),
            ),
          ),
          appPermissionServiceProvider.overrideWithValue(
            _DeniedPermissions(permanentlyDenied: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(faceVerificationFlowProvider.notifier)
          .startVerification();

      expect(repo.startCalls, 0);
      final state = container.read(faceVerificationFlowProvider);
      expect(state.phase, FaceVerificationFlowPhase.permissionDenied);
      expect(state.permanentlyDenied, isTrue);
    });

    test('double-tap creates only one session', () async {
      final repo = _FakeRepository();
      final container = ProviderContainer(
        overrides: [
          faceVerificationRepositoryProvider.overrideWithValue(repo),
          faceLivenessLauncherProvider.overrideWithValue(
            _FakeLauncher(
              const LivenessCaptureResult(
                outcome: ClientLivenessOutcome.completed,
              ),
            ),
          ),
          appPermissionServiceProvider.overrideWithValue(
            _GrantedPermissions(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(faceVerificationFlowProvider.notifier);
      final first = controller.startVerification();
      final second = controller.startVerification();
      await Future.wait([first, second]);

      expect(repo.startCalls, 1);
    });
  });
}
