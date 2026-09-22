/// Nenjam Matrimony — Face Verification domain models
///
/// Mirrors `backend/apps/api/src/modules/verification/dto/face-verification.dto.ts`
/// exactly. Unknown enum strings map to a safe default rather than throwing,
/// since the backend can add a new blocked/failure reason before this app
/// updates.
library;

/// `GET /verification/face`'s `status`.
enum FaceVerificationStatus {
  unverified,
  verified,
  revoked;

  static FaceVerificationStatus fromJson(String? value) => switch (value) {
    'VERIFIED' => FaceVerificationStatus.verified,
    'REVOKED' => FaceVerificationStatus.revoked,
    _ => FaceVerificationStatus.unverified,
  };
}

/// `GET /verification/face`'s `blockedReason` — see `FACE_BLOCKED_REASONS`.
enum FaceBlockedReason {
  notAvailable,
  alreadyVerified,
  noPrimaryPhoto,
  unsupportedPhoto,
  attemptLimit,
  // A reason string the backend added after this app shipped. Deliberately
  // distinct from [notAvailable] — only a real NOT_AVAILABLE may pass the
  // entry gate; an unknown reason must still block, since it is by
  // definition not something this app knows is safe to bypass.
  unknown;

  static FaceBlockedReason? fromJson(String? value) => switch (value) {
    'NOT_AVAILABLE' => FaceBlockedReason.notAvailable,
    'ALREADY_VERIFIED' => FaceBlockedReason.alreadyVerified,
    'NO_PRIMARY_PHOTO' => FaceBlockedReason.noPrimaryPhoto,
    'UNSUPPORTED_PHOTO' => FaceBlockedReason.unsupportedPhoto,
    'ATTEMPT_LIMIT' => FaceBlockedReason.attemptLimit,
    null => null,
    _ => FaceBlockedReason.unknown,
  };
}

/// `GET /verification/face` response.
class FaceVerificationState {
  const FaceVerificationState({
    required this.status,
    required this.verifiedAt,
    required this.canStart,
    required this.blockedReason,
    required this.attemptsRemainingToday,
    required this.retryAfter,
  });

  factory FaceVerificationState.fromJson(Map<String, dynamic> json) {
    return FaceVerificationState(
      status: FaceVerificationStatus.fromJson(json['status'] as String?),
      verifiedAt: _parseDate(json['verifiedAt']),
      canStart: json['canStart'] as bool? ?? false,
      blockedReason: FaceBlockedReason.fromJson(
        json['blockedReason'] as String?,
      ),
      attemptsRemainingToday: json['attemptsRemainingToday'] as int? ?? 0,
      retryAfter: _parseDate(json['retryAfter']),
    );
  }

  final FaceVerificationStatus status;
  final DateTime? verifiedAt;
  final bool canStart;
  final FaceBlockedReason? blockedReason;
  final int attemptsRemainingToday;
  final DateTime? retryAfter;

  /// The router gate's "may this member reach Discover" check. `NOT_AVAILABLE`
  /// is a temporary pass-through: while the backend feature is switched off
  /// (`FACE_VERIFICATION_ENABLED=false`) it can never be satisfied, so it must
  /// not block anyone. It is deliberately NOT treated as equivalent to
  /// verified — the moment the backend turns the feature on, `canStart`
  /// becomes true (or status becomes `VERIFIED`) and the gate takes effect
  /// automatically, with no frontend flag to flip.
  bool get satisfiesEntryGate =>
      status == FaceVerificationStatus.verified ||
      blockedReason == FaceBlockedReason.notAvailable;
}

/// Short-lived AWS credentials from `POST /verification/face/sessions`.
///
/// Deliberately has no `toJson` — this must never be persisted, cached, or
/// sent anywhere except into the native liveness bridge for a single
/// attempt. `toString` hides every secret field so an accidental `print`,
/// log line, or crash report never leaks a credential.
class LivenessSessionTicket {
  const LivenessSessionTicket({
    required this.attemptId,
    required this.sessionId,
    required this.region,
    required this.expiresAt,
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.sessionToken,
    required this.credentialsExpiration,
  });

  factory LivenessSessionTicket.fromJson(Map<String, dynamic> json) {
    final credentials = json['credentials'] as Map<String, dynamic>? ?? {};
    return LivenessSessionTicket(
      attemptId: json['attemptId'] as String? ?? '',
      sessionId: json['sessionId'] as String? ?? '',
      region: json['region'] as String? ?? '',
      expiresAt: _parseDate(json['expiresAt']) ?? DateTime.now(),
      accessKeyId: credentials['accessKeyId'] as String? ?? '',
      secretAccessKey: credentials['secretAccessKey'] as String? ?? '',
      sessionToken: credentials['sessionToken'] as String? ?? '',
      credentialsExpiration:
          _parseDate(credentials['expiration']) ?? DateTime.now(),
    );
  }

  final String attemptId;
  final String sessionId;
  final String region;
  final DateTime expiresAt;
  final String accessKeyId;
  final String secretAccessKey;
  final String sessionToken;
  final DateTime credentialsExpiration;

  @override
  String toString() =>
      'LivenessSessionTicket(attemptId: $attemptId, sessionId: $sessionId, '
      'region: $region, expiresAt: $expiresAt, credentials: <redacted>)';
}

/// What the native liveness bridge observed — never a pass/fail result, only
/// what happened on-device. See the handoff doc §1 rule 1: only the backend's
/// `/complete` response may say "verified".
enum ClientLivenessOutcome {
  completed,
  cancelled,
  error;

  String toJson() => switch (this) {
    ClientLivenessOutcome.completed => 'COMPLETED',
    ClientLivenessOutcome.cancelled => 'CANCELLED',
    ClientLivenessOutcome.error => 'ERROR',
  };
}

/// `POST /verification/face/complete`'s `reason`.
enum FaceVerificationFailureReason {
  failedLiveness,
  failedMatch,
  noFaceInPhoto,
  multipleFacesInPhoto,
  unsupportedPhoto,
  noReferenceImage,
  photoChanged,
  expired,
  cancelled,
  error;

  static FaceVerificationFailureReason? fromJson(String? value) =>
      switch (value) {
        'FAILED_LIVENESS' => FaceVerificationFailureReason.failedLiveness,
        'FAILED_MATCH' => FaceVerificationFailureReason.failedMatch,
        'NO_FACE_IN_PHOTO' => FaceVerificationFailureReason.noFaceInPhoto,
        'MULTIPLE_FACES_IN_PHOTO' =>
          FaceVerificationFailureReason.multipleFacesInPhoto,
        'UNSUPPORTED_PHOTO' => FaceVerificationFailureReason.unsupportedPhoto,
        'NO_REFERENCE_IMAGE' =>
          FaceVerificationFailureReason.noReferenceImage,
        'PHOTO_CHANGED' => FaceVerificationFailureReason.photoChanged,
        'EXPIRED' => FaceVerificationFailureReason.expired,
        'CANCELLED' => FaceVerificationFailureReason.cancelled,
        null => null,
        _ => FaceVerificationFailureReason.error,
      };

  /// Whether this failure is one a member can fix by updating their main
  /// photo, per the handoff doc §6.2 "offer Update main photo" list.
  bool get suggestsPhotoUpdate => switch (this) {
    FaceVerificationFailureReason.failedMatch ||
    FaceVerificationFailureReason.noFaceInPhoto ||
    FaceVerificationFailureReason.multipleFacesInPhoto ||
    FaceVerificationFailureReason.unsupportedPhoto ||
    FaceVerificationFailureReason.photoChanged => true,
    _ => false,
  };
}

/// `POST /verification/face/complete` response. The backend's decision —
/// never derived or guessed on-device.
class FaceVerificationResult {
  const FaceVerificationResult({
    required this.attemptId,
    required this.verified,
    required this.reason,
    required this.canRetry,
    required this.attemptsRemainingToday,
  });

  factory FaceVerificationResult.fromJson(Map<String, dynamic> json) {
    return FaceVerificationResult(
      attemptId: json['attemptId'] as String? ?? '',
      verified: json['status'] == 'VERIFIED',
      reason: FaceVerificationFailureReason.fromJson(
        json['reason'] as String?,
      ),
      canRetry: json['canRetry'] as bool? ?? false,
      attemptsRemainingToday: json['attemptsRemainingToday'] as int? ?? 0,
    );
  }

  final String attemptId;
  final bool verified;
  final FaceVerificationFailureReason? reason;
  final bool canRetry;
  final int attemptsRemainingToday;
}

DateTime? _parseDate(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
