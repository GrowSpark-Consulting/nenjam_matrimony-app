/// Immutable configuration model holding environment variables loaded from .env.
///
/// Deliberately carries NO API base URL: the backend origin is a single
/// compile-time constant ([AppConstants.apiBaseUrl]) so it can never differ
/// between the REST client, the socket and the health probe depending on
/// which `.env` asset happened to load.
class EnvConfig {
  final bool enableLogging;
  final String s3BucketName;
  final String stripePublishableKey;

  const EnvConfig({
    required this.enableLogging,
    required this.s3BucketName,
    required this.stripePublishableKey,
  });
}
