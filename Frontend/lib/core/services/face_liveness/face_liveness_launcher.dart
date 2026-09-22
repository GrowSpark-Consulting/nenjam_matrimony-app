import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../features/verification/domain/models/face_verification.dart';

/// What the native side reported. Never a pass/fail — see the handoff doc
/// §1 rule 1: only the backend's `/complete` response may say "verified".
class LivenessCaptureResult {
  const LivenessCaptureResult({
    required this.outcome,
    this.errorCode,
    this.errorMessage,
  });

  final ClientLivenessOutcome outcome;
  final String? errorCode;
  final String? errorMessage;
}

/// Launches the native AWS Rekognition Face Liveness capture screen.
///
/// AWS has no Flutter SDK for this (see the handoff doc §2) — the real
/// implementation is a `MethodChannel` into a Kotlin `LivenessActivity`
/// hosting Amplify's `FaceLivenessDetector` Compose component. That native
/// side (`android/app/src/main/kotlin/.../liveness/`) is a separate,
/// device-tested platform change tracked by the handoff doc's "Order of
/// work" §10 step 1 — not added here.
abstract class FaceLivenessLauncher {
  /// True only on Android; the handoff doc scopes this feature to Android,
  /// and there is no native bridge on any other platform.
  bool get isSupported;

  Future<LivenessCaptureResult> start(LivenessSessionTicket ticket);
}

/// Channel name and method fixed by the handoff doc §5 — must match the
/// Kotlin `FaceLivenessChannel` registration exactly.
const String _channelName = 'com.growspark.nenjam/face_liveness';
const String _startMethod = 'startLiveness';

class MethodChannelFaceLivenessLauncher implements FaceLivenessLauncher {
  MethodChannelFaceLivenessLauncher()
    : _channel = const MethodChannel(_channelName);

  final MethodChannel _channel;

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<LivenessCaptureResult> start(LivenessSessionTicket ticket) async {
    if (!isSupported) {
      return const LivenessCaptureResult(
        outcome: ClientLivenessOutcome.error,
        errorCode: 'UNSUPPORTED_PLATFORM',
      );
    }
    try {
      // Credentials cross the channel once, for this call only — never
      // logged, never persisted. The native side is responsible for holding
      // them in memory only and clearing them after use (handoff doc §5/§7).
      final result = await _channel.invokeMapMethod<String, dynamic>(
        _startMethod,
        <String, dynamic>{
          'sessionId': ticket.sessionId,
          'region': ticket.region,
          'accessKeyId': ticket.accessKeyId,
          'secretAccessKey': ticket.secretAccessKey,
          'sessionToken': ticket.sessionToken,
          'expirationEpochSeconds':
              ticket.credentialsExpiration.millisecondsSinceEpoch ~/ 1000,
        },
      );
      final outcome = switch (result?['outcome'] as String?) {
        'COMPLETED' => ClientLivenessOutcome.completed,
        'CANCELLED' => ClientLivenessOutcome.cancelled,
        _ => ClientLivenessOutcome.error,
      };
      return LivenessCaptureResult(
        outcome: outcome,
        errorCode: result?['errorCode'] as String?,
        errorMessage: result?['errorMessage'] as String?,
      );
    } on PlatformException catch (e) {
      // The handoff doc says the native side should never throw for
      // expected outcomes — a PlatformException here is itself unexpected,
      // so it is treated the same as a native ERROR result.
      return LivenessCaptureResult(outcome: ClientLivenessOutcome.error, errorCode: e.code);
    }
  }
}
