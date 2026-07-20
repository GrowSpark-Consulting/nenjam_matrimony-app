/// Nenjam Matrimony — Shared API Exception
///
/// Thrown when the backend rejects a request (validation error,
/// unauthenticated, not found, etc.) — carries the backend's own message
/// when available so callers can show something more useful than "something
/// went wrong". Every repository that talks to [ApiClient] should throw
/// this (via [unwrapOrThrow]) rather than defining its own copy.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int? statusCode;
  final String message;

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
    throw ApiException(
      statusCode,
      message is String
          ? message
          : message is List && message.isNotEmpty
              ? message.join(', ')
              : 'Request failed ($statusCode).',
    );
  }
  return data;
}
