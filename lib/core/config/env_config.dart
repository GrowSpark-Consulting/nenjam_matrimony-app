/// Immutable configuration model holding environment variables loaded from .env.
class EnvConfig {
  final String apiBaseUrl;
  final bool enableLogging;
  final String s3BucketName;
  final String stripePublishableKey;

  const EnvConfig({
    required this.apiBaseUrl,
    required this.enableLogging,
    required this.s3BucketName,
    required this.stripePublishableKey,
  });
}
