import 'package:dio/dio.dart';

import '../l10n/app_l10n.dart';

/// Turns a raw [DioException] into a sentence that can be shown to a user.
///
/// The single place in the app that decides what a network failure *reads*
/// like. Interceptors, repositories and error widgets all route through here
/// so "no internet" is phrased identically everywhere, and so a stack trace
/// or a Dio type name can never reach the screen.
///
/// Total by construction — every [DioExceptionType], and every non-Dio
/// object, maps to something. Callers never need a fallback of their own.
abstract final class NetworkErrorMapper {
  /// User-facing message for [error], which may be a [DioException] or any
  /// other thrown object (repositories often catch broadly and pass the raw
  /// object straight through).
  static String message(Object? error) {
    if (error is! DioException) return AppL10n.current.authGenericError;

    final l10n = AppL10n.current;
    return switch (error.type) {
      DioExceptionType.connectionTimeout => l10n.networkConnectionTimeout,
      DioExceptionType.sendTimeout => l10n.networkConnectionTimeout,
      DioExceptionType.receiveTimeout => l10n.networkReceiveTimeout,
      // Dio reports both "no route to host" and a refused connection as
      // connectionError; from the user's seat these are the same problem.
      DioExceptionType.connectionError => l10n.safetyErrorNetwork,
      DioExceptionType.badCertificate => l10n.networkNoInternetMessage,
      DioExceptionType.cancel => l10n.networkRequestCancelled,
      DioExceptionType.badResponse => statusMessage(error.response?.statusCode),
      DioExceptionType.unknown => _unknown(error),
    };
  }

  /// User-facing message for an HTTP status code. Public because the API
  /// client's `validateStatus` resolves everything below 500 as a normal
  /// response — repositories inspect `response.statusCode` themselves and
  /// need the same wording an exception would have produced.
  static String statusMessage(int? statusCode) {
    final l10n = AppL10n.current;
    return switch (statusCode) {
      400 => l10n.apiError400,
      401 => l10n.apiError401,
      403 => l10n.apiError403,
      404 => l10n.apiError404,
      422 => l10n.apiError422,
      429 => l10n.apiError429,
      500 => l10n.apiError500,
      503 => l10n.apiError503,
      _ => l10n.authGenericError,
    };
  }

  /// True when [error] means "the request never reached the server" —
  /// offline, DNS failure, backend down, timeout. Screens use it to offer a
  /// Retry affordance instead of a dead end.
  static bool isConnectivityFailure(Object? error) {
    if (error is! DioException) return false;
    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => true,
      _ => false,
    };
  }

  /// `unknown` is Dio's catch-all: a SocketException that escaped its own
  /// classification lands here just as often as a genuine bug, so sniff the
  /// wrapped error before falling back to the generic message.
  static String _unknown(DioException error) {
    final inner = error.error?.toString().toLowerCase() ?? '';
    final looksOffline =
        inner.contains('socketexception') ||
        inner.contains('failed host lookup') ||
        inner.contains('network is unreachable');
    return looksOffline
        ? AppL10n.current.safetyErrorNetwork
        : AppL10n.current.authGenericError;
  }
}
