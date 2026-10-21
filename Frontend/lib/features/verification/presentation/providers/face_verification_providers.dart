import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/permissions/app_permission_service.dart';
import '../../../../core/permissions/nm_permission.dart';
import '../../../../core/services/face_liveness/face_liveness_launcher.dart';
import '../../data/repositories/api_face_verification_repository.dart';
import '../../domain/models/face_verification.dart';
import '../../domain/repositories/face_verification_repository.dart';

/// Real backend implementation — matches the repo's `Mock*`/`Api*`-behind-
/// one-`Provider` pattern (see `personalityRepositoryProvider` for another
/// example). Not mocked by default: `NOT_AVAILABLE` (503) is itself the
/// correct behavior while `FACE_VERIFICATION_ENABLED=false`, and the entry
/// gate already treats that as a pass-through — no fake success needed to
/// build against it.
final faceVerificationRepositoryProvider = Provider<FaceVerificationRepository>(
  (ref) => ApiFaceVerificationRepository(ref.watch(apiClientProvider)),
);

final faceLivenessLauncherProvider = Provider<FaceLivenessLauncher>(
  (ref) => MethodChannelFaceLivenessLauncher(),
);

final appPermissionServiceProvider = Provider<AppPermissionService>(
  (ref) => const AppPermissionServiceImpl(),
);

/// The signed-in member's current face-verification state. Used by the
/// router gate ([PostAuthDestination]... see app_router.dart), the
/// Verification Center card, and the profile "Face Match" tile.
///
/// Invalidated on sign-in/sign-out (`main.dart`) and after any photo
/// replace/delete/set-primary (the backend reports `REVOKED` once the
/// matched photo is no longer primary).
class FaceVerificationStatusNotifier
    extends AutoDisposeAsyncNotifier<FaceVerificationState> {
  @override
  Future<FaceVerificationState> build() {
    return ref.watch(faceVerificationRepositoryProvider).getState();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<FaceVerificationState>().copyWithPrevious(
      state,
    );
    state = await AsyncValue.guard(
      () => ref.read(faceVerificationRepositoryProvider).getState(),
    );
  }
}

final faceVerificationStatusProvider = AsyncNotifierProvider.autoDispose<
  FaceVerificationStatusNotifier,
  FaceVerificationState
>(FaceVerificationStatusNotifier.new);

/// The flow controller's state machine — see
/// docs/development/selfie-verification-frontend-handoff.md §6.3.
enum FaceVerificationFlowPhase {
  idle,
  checkingPermission,
  permissionDenied,
  creatingSession,
  capturing,
  completing,
  verified,
  failed,
  blocked,
  networkError,

  /// This platform has no face-liveness capture (the browser, iOS today —
  /// only the Android native bridge exists). Said outright, with no camera
  /// prompt and no paid session created.
  unsupported,
}

class FaceVerificationFlowState {
  const FaceVerificationFlowState({
    this.phase = FaceVerificationFlowPhase.idle,
    this.blockedReason,
    this.failureReason,
    this.canRetry = true,
    this.attemptsRemainingToday,
    this.permanentlyDenied = false,
  });

  final FaceVerificationFlowPhase phase;
  final FaceBlockedReason? blockedReason;
  final FaceVerificationFailureReason? failureReason;
  final bool canRetry;
  final int? attemptsRemainingToday;
  final bool permanentlyDenied;

  FaceVerificationFlowState copyWith({
    FaceVerificationFlowPhase? phase,
    FaceBlockedReason? blockedReason,
    FaceVerificationFailureReason? failureReason,
    bool? canRetry,
    int? attemptsRemainingToday,
    bool? permanentlyDenied,
  }) {
    return FaceVerificationFlowState(
      phase: phase ?? this.phase,
      blockedReason: blockedReason,
      failureReason: failureReason,
      canRetry: canRetry ?? this.canRetry,
      attemptsRemainingToday:
          attemptsRemainingToday ?? this.attemptsRemainingToday,
      permanentlyDenied: permanentlyDenied ?? this.permanentlyDenied,
    );
  }
}

/// Retry backoff for `/complete` on `RESULT_NOT_READY` / `ATTEMPT_IN_PROGRESS`
/// / network failure — handoff doc §6.3.
const List<Duration> _completeRetryBackoff = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
];

class FaceVerificationFlowController
    extends AutoDisposeNotifier<FaceVerificationFlowState> {
  @override
  FaceVerificationFlowState build() => const FaceVerificationFlowState();

  FaceVerificationRepository get _repository =>
      ref.read(faceVerificationRepositoryProvider);

  /// Requests camera permission, starts a session, launches the native
  /// capture, then closes the attempt with `/complete`. Never throws — every
  /// failure path lands in [state].
  Future<void> startVerification() async {
    if (state.phase == FaceVerificationFlowPhase.checkingPermission ||
        state.phase == FaceVerificationFlowPhase.creatingSession ||
        state.phase == FaceVerificationFlowPhase.capturing ||
        state.phase == FaceVerificationFlowPhase.completing) {
      // Double-tap protection (handoff doc §6.3): each start can create a
      // paid AWS session, so a second concurrent tap is dropped rather than
      // queued.
      return;
    }

    // Before anything else: no camera prompt and no session for a platform
    // that cannot run the capture at all.
    if (!ref.read(faceLivenessLauncherProvider).isSupported) {
      state = const FaceVerificationFlowState(
        phase: FaceVerificationFlowPhase.unsupported,
        canRetry: false,
      );
      return;
    }

    state = const FaceVerificationFlowState(
      phase: FaceVerificationFlowPhase.checkingPermission,
    );

    final permissions = ref.read(appPermissionServiceProvider);
    var status = await permissions.statusOf(NmPermission.camera);
    if (!status.isGranted) {
      status = await permissions.request(NmPermission.camera);
    }
    if (!status.isGranted) {
      // Requested before creating a session (handoff doc §6.2) so a denial
      // never burns a paid AWS session.
      state = FaceVerificationFlowState(
        phase: FaceVerificationFlowPhase.permissionDenied,
        permanentlyDenied: status == NmPermissionStatus.permanentlyDenied,
      );
      return;
    }

    final launcher = ref.read(faceLivenessLauncherProvider);
    if (!launcher.isSupported) {
      state = const FaceVerificationFlowState(
        phase: FaceVerificationFlowPhase.failed,
        canRetry: false,
      );
      return;
    }

    state = state.copyWith(phase: FaceVerificationFlowPhase.creatingSession);

    final LivenessSessionTicket ticket;
    try {
      ticket = await _repository.startSession(consent: true);
    } on ApiException catch (e) {
      _handleStartFailure(e);
      return;
    } catch (_) {
      state = const FaceVerificationFlowState(
        phase: FaceVerificationFlowPhase.networkError,
      );
      return;
    }

    state = state.copyWith(phase: FaceVerificationFlowPhase.capturing);
    // The ticket is held only in this local variable for the single call
    // below — never assigned into `state`, so it is dropped from memory as
    // soon as `start()` returns (handoff doc §6.3).
    final capture = await launcher.start(ticket);

    await _completeAttempt(
      attemptId: ticket.attemptId,
      expiresAt: ticket.expiresAt,
      outcome: capture.outcome,
      errorCode: capture.errorCode,
    );
  }

  /// Calls `/complete` on every native outcome — including cancel and error
  /// — so the backend can close the attempt (handoff doc §6.3). Retries with
  /// backoff on `RESULT_NOT_READY` / `ATTEMPT_IN_PROGRESS` / network failure
  /// until `expiresAt` + ~60s.
  Future<void> _completeAttempt({
    required String attemptId,
    required DateTime expiresAt,
    required ClientLivenessOutcome outcome,
    String? errorCode,
  }) async {
    state = state.copyWith(phase: FaceVerificationFlowPhase.completing);
    final deadline = expiresAt.add(const Duration(seconds: 60));

    var attempt = 0;
    while (true) {
      try {
        final result = await _repository.complete(
          attemptId: attemptId,
          clientOutcome: outcome,
          clientErrorCode: errorCode,
        );
        _applyResult(result);
        return;
      } on ApiException catch (e) {
        final retryable = e.code == 'RESULT_NOT_READY' ||
            e.code == 'ATTEMPT_IN_PROGRESS';
        if (!retryable || DateTime.now().isAfter(deadline) ||
            attempt >= _completeRetryBackoff.length) {
          if (retryable) {
            // The window ran out — a later GET /verification/face shows the
            // real state (handoff doc §6.3).
            state = state.copyWith(
              phase: FaceVerificationFlowPhase.networkError,
            );
          } else {
            _handleCompleteFailure(e);
          }
          return;
        }
        await Future<void>.delayed(_completeRetryBackoff[attempt]);
        attempt++;
      } catch (_) {
        if (DateTime.now().isAfter(deadline) ||
            attempt >= _completeRetryBackoff.length) {
          state = state.copyWith(
            phase: FaceVerificationFlowPhase.networkError,
          );
          return;
        }
        await Future<void>.delayed(_completeRetryBackoff[attempt]);
        attempt++;
      }
    }
  }

  void _applyResult(FaceVerificationResult result) {
    if (result.verified) {
      state = const FaceVerificationFlowState(
        phase: FaceVerificationFlowPhase.verified,
      );
      ref.invalidate(faceVerificationStatusProvider);
    } else {
      state = FaceVerificationFlowState(
        phase: FaceVerificationFlowPhase.failed,
        failureReason: result.reason,
        canRetry: result.canRetry,
        attemptsRemainingToday: result.attemptsRemainingToday,
      );
    }
  }

  void _handleStartFailure(ApiException e) {
    final blocked = FaceBlockedReason.fromJson(e.code);
    if (e.code != null && blocked != null) {
      state = FaceVerificationFlowState(
        phase: FaceVerificationFlowPhase.blocked,
        blockedReason: blocked,
      );
      return;
    }
    if (e.statusCode != null && e.statusCode! >= 500) {
      state = const FaceVerificationFlowState(
        phase: FaceVerificationFlowPhase.networkError,
      );
      return;
    }
    state = const FaceVerificationFlowState(
      phase: FaceVerificationFlowPhase.failed,
      canRetry: true,
    );
  }

  void _handleCompleteFailure(ApiException e) {
    if (e.code == 'ATTEMPT_NOT_FOUND') {
      state = const FaceVerificationFlowState(
        phase: FaceVerificationFlowPhase.failed,
        canRetry: true,
      );
      return;
    }
    state = const FaceVerificationFlowState(
      phase: FaceVerificationFlowPhase.networkError,
    );
  }

  void reset() => state = const FaceVerificationFlowState();
}

final faceVerificationFlowProvider = AutoDisposeNotifierProvider<
  FaceVerificationFlowController,
  FaceVerificationFlowState
>(FaceVerificationFlowController.new);
