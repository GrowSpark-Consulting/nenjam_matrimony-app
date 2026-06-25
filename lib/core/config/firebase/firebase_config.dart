import '../app_environment.dart';
import 'firebase_options_dev.dart';
import 'firebase_options_production.dart';
import 'firebase_options_qa.dart';
import 'firebase_options_staging.dart';

/// Firebase configuration selector based on active flavor environment.
class FirebaseConfig {
  static Map<String, String> options(AppEnvironment env) {
    return switch (env) {
      AppEnvironment.dev => DefaultFirebaseOptionsDev.currentPlatform,
      AppEnvironment.qa => DefaultFirebaseOptionsQa.currentPlatform,
      AppEnvironment.staging => DefaultFirebaseOptionsStaging.currentPlatform,
      AppEnvironment.production => DefaultFirebaseOptionsProduction.currentPlatform,
    };
  }
}
