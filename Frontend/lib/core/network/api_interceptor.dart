import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../utils/story_perf.dart';
import '../l10n/app_l10n.dart';

/// Marks a request as already having gone through one 401-recovery retry,
/// so [AuthInterceptor] never retries the same request twice.
const _authRetriedKey = 'nm_auth_retried';

/// Centralized auth interceptor — the single place that attaches the
/// current session token to outgoing requests and reacts to a 401.
///
/// Recovery flow on 401: force-refresh the session token, retry the
/// request exactly once with the new token; if the refresh yields nothing
/// or the retry also 401s, hand off to [onSessionExpired] (session teardown
/// + redirect are handled centrally — see NenjamMatrimonyApp's
/// authStateChanges listener and app_router.dart's redirect). Callers
/// (repositories, pages) never see or handle 401s directly.
class AuthInterceptor extends Interceptor {
  final Dio dio;
  final Future<String?> Function() getAccessToken;
  final Future<String?> Function() refreshAccessToken;
  final Future<void> Function() onSessionExpired;

  AuthInterceptor({
    required this.dio,
    required this.getAccessToken,
    required this.refreshAccessToken,
    required this.onSessionExpired,
  });

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await getAccessToken();
    StoryPerf.mark('Firebase token obtained (${options.path})');
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final isUnauthorized = err.response?.statusCode == 401;
    final alreadyRetried = err.requestOptions.extra[_authRetriedKey] == true;
    if (!isUnauthorized || alreadyRetried) {
      return handler.next(err);
    }

    final refreshedToken = await refreshAccessToken();
    if (refreshedToken == null || refreshedToken.isEmpty) {
      await onSessionExpired();
      return handler.next(err);
    }

    try {
      final retryOptions = err.requestOptions
        ..headers['Authorization'] = 'Bearer $refreshedToken'
        ..extra[_authRetriedKey] = true;
      final response = await dio.fetch<dynamic>(retryOptions);
      return handler.resolve(response);
    } on DioException catch (retryError) {
      if (retryError.response?.statusCode == 401) {
        await onSessionExpired();
      }
      return handler.next(retryError);
    }
  }
}

/// Logging Interceptor — Logs method + URL only (never headers or body, so
/// the `Authorization` bearer token can never end up in a log line) and
/// only in debug builds.
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      log('→ ${options.method} ${options.uri}', name: 'API');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      log('← ${response.statusCode} ${response.requestOptions.uri}', name: 'API');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      log(
        '✕ ${err.response?.statusCode ?? 'NETWORK'} ${err.requestOptions.uri}',
        name: 'API',
        level: 1000,
      );
    }
    handler.next(err);
  }
}

/// Error Handling Interceptor — Maps Dio errors to app-level errors.
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final String message;

    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        message = 'Connection timed out. Please try again.';
      case DioExceptionType.connectionError:
        message = 'No internet connection. Please check your network.';
      case DioExceptionType.cancel:
        message = 'Request was cancelled.';
      case DioExceptionType.badResponse:
        message = _mapStatusCode(err.response?.statusCode);
      default:
        message = 'Something went wrong. Please try again.';
    }

    handler.next(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: err.error,
        message: message,
      ),
    );
  }

  String _mapStatusCode(int? statusCode) {
    final l10n = AppL10n.current;
    switch (statusCode) {
      case 400:
        return l10n.apiError400;
      case 401:
        return l10n.apiError401;
      case 403:
        return l10n.apiError403;
      case 404:
        return l10n.apiError404;
      case 422:
        return l10n.apiError422;
      case 429:
        return l10n.apiError429;
      case 500:
        return l10n.apiError500;
      case 503:
        return l10n.apiError503;
      default:
        return l10n.authGenericError;
    }
  }
}
