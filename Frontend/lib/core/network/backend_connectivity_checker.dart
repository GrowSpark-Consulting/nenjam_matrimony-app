import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';

/// Result of a [BackendConnectivityChecker.check] call.
sealed class BackendConnectivityResult {
  const BackendConnectivityResult();

  /// Whether the app may proceed past startup. Only a healthy backend
  /// qualifies — see [BackendConnectivityChecker.check].
  bool get isHealthy => this is BackendHealthy;
}

/// `GET /health` responded 2xx — backend is reachable and serving.
class BackendHealthy extends BackendConnectivityResult {
  const BackendHealthy();
}

/// The request never got an answer: the device is offline, DNS failed, or
/// the server is down. Indistinguishable from the client's side, and the
/// user's next step is the same for all three — check the connection and
/// retry — so they share one result.
class BackendUnreachable extends BackendConnectivityResult {
  const BackendUnreachable();
}

/// The server answered, but `/health` was not 2xx — the process is up and
/// something is wrong server-side (bad deploy, dependency down).
class BackendUnhealthy extends BackendConnectivityResult {
  final int? statusCode;
  const BackendUnhealthy(this.statusCode);
}

/// Lightweight `GET /health` probe against [AppConstants.apiBaseUrl], used by
/// the startup flow to decide between entering the app and showing a
/// retryable error state (see `SplashController.checkServerHealth`).
///
/// Deliberately cheap and total: it sends no auth, accepts any status without
/// throwing, and is bounded by [AppConstants.healthCheckTimeout] so a dead
/// backend costs seconds rather than the full request timeout. It never
/// throws — every failure is one of the results above.
class BackendConnectivityChecker {
  BackendConnectivityChecker(this._dio);

  final Dio _dio;

  static const String healthPath = '/health';

  Future<BackendConnectivityResult> check() async {
    try {
      final response = await _dio.get<dynamic>(
        healthPath,
        options: Options(
          sendTimeout: AppConstants.healthCheckTimeout,
          receiveTimeout: AppConstants.healthCheckTimeout,
          // The probe reports the status itself; Dio must not turn a 503
          // into an exception here.
          validateStatus: (_) => true,
        ),
      );
      final status = response.statusCode;
      if (status != null && status >= 200 && status < 300) {
        return const BackendHealthy();
      }
      return BackendUnhealthy(status);
    } catch (error) {
      if (kDebugMode) {
        log(
          '${_dio.options.baseUrl}$healthPath unreachable: $error',
          name: 'API',
          level: 900,
        );
      }
      return const BackendUnreachable();
    }
  }
}
