/// Nenjam Matrimony — Shared API Exception
///
/// Thrown when the backend rejects a request (validation error,
/// unauthenticated, not found, etc.) — carries the backend's own message
/// when available so callers can show something more useful than "something
/// went wrong". Every repository that talks to [ApiClient] should throw
/// this (via [unwrapOrThrow]) rather than defining its own copy.
class ApiException implements Exception {
  ApiException(
    this.statusCode,
    this.message, {
    this.code,
    this.retryAfterSeconds,
    this.feature,
    this.limit,
    this.resetsAt,
    this.upgradeTo,
  });
  final int? statusCode;
  final String message;

  /// Stable, machine-readable error code from the response body's `code`
  /// field, when the endpoint sends one (e.g. face verification's
  /// `ATTEMPT_LIMIT`, `NO_PRIMARY_PHOTO`, `RESULT_NOT_READY`). Branch on this,
  /// never on [message] — messages are human-readable and may change. Null
  /// for endpoints that only use Nest's default `{ statusCode, message }`.
  final String? code;

  /// Positive whole seconds from the response body's `retryAfterSeconds`
  /// field, when the endpoint sends one — e.g. the psychology quiz's retake
  /// cooldown (`429 { ..., retryAfterSeconds }`). Null otherwise, including
  /// for the global per-IP rate limit, whose 429 carries no such field — so
  /// a 429 alone never implies a cooldown.
  final int? retryAfterSeconds;

  // ── Membership refusal details ──────────────────────────────────────────
  // Parsed only when [code] starts with `MEMBERSHIP_` (a membership 403, see
  // docs/membership/api-contract.md). Each is null when the body omits it or
  // sends something unusable — never a guessed default. The backend only
  // returns these once enforcement is switched on; in shadow mode it doesn't.

  /// Feature id the refusal is about, e.g. `interests.send`.
  final String? feature;

  /// The plan's allowance for [feature] (a whole number, 0 or more).
  final int? limit;

  /// When the allowance resets. Null for a cap (it doesn't reset) and for a
  /// feature the plan doesn't include.
  final DateTime? resetsAt;

  /// The cheapest plan on sale that would allow this, e.g. `GOLD`. Null means
  /// no upgrade can help — never offer one then.
  final String? upgradeTo;

  /// Whether this is a membership refusal rather than any other 403.
  bool get isMembershipDenial => code?.startsWith('MEMBERSHIP_') ?? false;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Unwraps a Dio [Response]'s `statusCode`/`data`, throwing an
/// [ApiException] for 4xx responses.
///
/// [ApiClient] is configured with `validateStatus: status < 500`, so 4xx
/// responses land as normal [Response] objects rather than [DioException]s
/// — this is what turns those into a thrown exception, matching Nest's
/// default HTTP-exception filter shape: `{ statusCode, message, error }`,
/// where `message` may be a single string or a list of validation errors.
T? unwrapOrThrow<T>(int? statusCode, T? data) {
  if (statusCode != null && statusCode >= 400) {
    final dynamic message = data is Map ? data['message'] : null;
    final dynamic code = data is Map ? data['code'] : null;
    final dynamic retryAfter = data is Map ? data['retryAfterSeconds'] : null;
    // Membership details only ride on a membership refusal; on any other error
    // a `limit` or `feature` key means something else and is left alone.
    final Map<dynamic, dynamic>? membership =
        data is Map && code is String && code.startsWith('MEMBERSHIP_')
        ? data
        : null;
    final dynamic feature = membership?['feature'];
    final dynamic limit = membership?['limit'];
    final dynamic resetsAt = membership?['resetsAt'];
    final dynamic upgradeTo = membership?['upgradeTo'];
    throw ApiException(
      statusCode,
      message is String
          ? message
          : message is List && message.isNotEmpty
          ? message.join(', ')
          : 'Request failed ($statusCode).',
      code: code is String && code.isNotEmpty ? code : null,
      retryAfterSeconds:
          retryAfter is num && retryAfter.isFinite && retryAfter > 0
          ? retryAfter.ceil()
          : null,
      feature: feature is String && feature.isNotEmpty ? feature : null,
      limit:
          limit is num && limit.isFinite && limit >= 0 && limit == limit.floor()
          ? limit.toInt()
          : null,
      resetsAt: resetsAt is String ? DateTime.tryParse(resetsAt) : null,
      upgradeTo: upgradeTo is String && upgradeTo.isNotEmpty ? upgradeTo : null,
    );
  }
  return data;
}
