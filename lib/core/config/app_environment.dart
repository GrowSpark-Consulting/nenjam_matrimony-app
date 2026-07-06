/// Supported application runtime environments.
enum AppEnvironment {
  dev,
  qa,
  staging,
  production;

  bool get isDev => this == AppEnvironment.dev;
  bool get isQa => this == AppEnvironment.qa;
  bool get isStaging => this == AppEnvironment.staging;
  bool get isProduction => this == AppEnvironment.production;
}
