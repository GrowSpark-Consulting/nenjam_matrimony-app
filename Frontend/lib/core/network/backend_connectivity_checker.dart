import 'dart:developer';

import 'package:dio/dio.dart';

/// Result of a [BackendConnectivityChecker.check] call.
sealed class BackendConnectivityResult {
  const BackendConnectivityResult();
}

/// `/health` responded 2xx — backend is fully reachable.
class BackendHealthy extends BackendConnectivityResult {
  const BackendHealthy();
}

/// The backend never responded at all.
///
/// On a USB-tunneled `127.0.0.1` connection this single failure mode covers
/// three distinct root causes that look identical from the phone's side —
/// the backend process isn't running, `adb reverse tcp:3000 tcp:3000`
/// hasn't been (re-)run since the last USB reconnect, or the phone has been
/// unplugged. All three fail the TCP handshake the same way, so this result
/// carries a checklist rather than false precision about which one it is.
class BackendUnreachable extends BackendConnectivityResult {
  const BackendUnreachable();
}

/// The backend responded, but `/health` didn't return 2xx. The process is
/// up — so this is not a USB/adb-reverse problem — something else is wrong
/// server-side.
class BackendUnhealthy extends BackendConnectivityResult {
  final int? statusCode;
  const BackendUnhealthy(this.statusCode);
}

/// Debug-only check that the configured backend (`EnvConfig.apiBaseUrl`) is
/// actually reachable, used to give developers an honest diagnostic instead
/// of Dio's generic "No internet connection" (which is misleading on a
/// USB-tunneled `127.0.0.1` connection — the phone's Wi-Fi may well be off).
///
/// See docs/development/android-usb-debugging.md.
class BackendConnectivityChecker {
  BackendConnectivityChecker(this._dio);

  final Dio _dio;

  static const checkTimeout = Duration(seconds: 3);

  Future<BackendConnectivityResult> check() async {
    try {
      final response = await _dio.get<dynamic>(
        '/health',
        options: Options(
          sendTimeout: checkTimeout,
          receiveTimeout: checkTimeout,
          validateStatus: (_) => true,
        ),
      );
      final status = response.statusCode;
      if (status != null && status >= 200 && status < 300) {
        return const BackendHealthy();
      }
      return BackendUnhealthy(status);
    } on DioException catch (e) {
      log(
        '[BackendConnectivityChecker] ${_dio.options.baseUrl}/health unreachable: ${e.message}',
        name: 'API',
      );
      return const BackendUnreachable();
    }
  }
}
