import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app_environment.dart';
import 'env_config.dart';

/// Singleton service holding current environment and flavor configuration.
class AppConfig {
  static final AppConfig _instance = AppConfig._internal();
  factory AppConfig() => _instance;
  AppConfig._internal();

  /// DEVELOPMENT ONLY. Firebase Auth is temporarily unavailable (suspended
  /// API key) — when true, [SplashController] and [OnboardingPage] skip the
  /// login/signup/email-OTP/phone-OTP flow entirely and route straight to
  /// Home (after language + onboarding) using [DevUser] as the session.
  ///
  /// This is a static const so it works even from the plain `main.dart`
  /// entry point, which never calls `AppConfig().init(...)`. Flip it back
  /// to `false` to restore the normal Firebase-gated flow — every call site
  /// only ever branches on this flag, nothing else was touched or deleted.
  static const bool devBypassAuth = true;

  late final AppEnvironment environment;
  late final EnvConfig envConfig;

  /// Initialize AppConfig by loading the appropriate flavor .env file.
  Future<void> init(AppEnvironment env) async {
    environment = env;
    final envFileName = switch (env) {
      AppEnvironment.dev => '.env.dev',
      AppEnvironment.qa => '.env.qa',
      AppEnvironment.staging => '.env.staging',
      AppEnvironment.production => '.env.production',
    };

    await dotenv.load(fileName: envFileName);

    envConfig = EnvConfig(
      apiBaseUrl: dotenv.env['API_BASE_URL'] ?? 'https://api.nenjammatrimony.com/v1',
      enableLogging: (dotenv.env['ENABLE_LOGGING'] ?? 'false').toLowerCase() == 'true',
      s3BucketName: dotenv.env['S3_BUCKET_NAME'] ?? '',
      stripePublishableKey: dotenv.env['STRIPE_PUBLISHABLE_KEY'] ?? '',
    );
  }
}
