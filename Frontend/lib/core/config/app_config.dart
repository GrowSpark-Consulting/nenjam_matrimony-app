import 'dart:developer';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app_environment.dart';
import 'env_config.dart';

/// Singleton service holding current environment and flavor configuration.
class AppConfig {
  static final AppConfig _instance = AppConfig._internal();
  factory AppConfig() => _instance;
  AppConfig._internal();

  late final AppEnvironment environment;
  late final EnvConfig envConfig;

  /// Initialize AppConfig by loading the appropriate flavor .env file.
  ///
  /// A missing/malformed `.env` asset must never take the app down on
  /// launch: nothing here is required for networking (the API origin is a
  /// compile-time constant), so a failed load simply leaves every value at
  /// its default.
  Future<void> init(AppEnvironment env) async {
    environment = env;
    // The per-flavour .env.* files are git-ignored and no longer bundled (see
    // pubspec.yaml), so the one asset every build has is the placeholder file.
    const envFileName = '.env.example';

    try {
      await dotenv.load(fileName: envFileName);
    } catch (error) {
      log(
        'Could not load $envFileName — using defaults: $error',
        name: 'AppConfig',
      );
    }

    envConfig = EnvConfig(
      // Never on in a production build, whatever the placeholder file says.
      enableLogging:
          !env.isProduction &&
          (dotenv.env['ENABLE_LOGGING'] ?? 'false').toLowerCase() == 'true',
      s3BucketName: dotenv.env['S3_BUCKET_NAME'] ?? '',
      stripePublishableKey: dotenv.env['STRIPE_PUBLISHABLE_KEY'] ?? '',
    );
  }
}
