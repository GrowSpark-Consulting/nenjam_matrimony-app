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
