import 'dart:developer';

import 'package:dio/dio.dart';

/// JWT Auth Interceptor — Attaches access token to requests
/// and handles 401 token refresh.
class AuthInterceptor extends Interceptor {
  // Token provider callbacks — will be connected to storage later
  final Future<String?> Function() getAccessToken;
  final Future<String?> Function() getRefreshToken;
  final Future<void> Function(String accessToken, String refreshToken)
      saveTokens;
  final Future<void> Function() onTokenExpired;

  AuthInterceptor({
    required this.getAccessToken,
    required this.getRefreshToken,
    required this.saveTokens,
    required this.onTokenExpired,
  });

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await getAccessToken();
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
    if (err.response?.statusCode == 401) {
      // Token expired — notify app to handle logout/refresh
      await onTokenExpired();
    }
    handler.next(err);
  }
}

/// Logging Interceptor — Logs request/response in debug mode.
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    log(
      '→ ${options.method} ${options.uri}',
      name: 'API',
    );
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    log(
      '← ${response.statusCode} ${response.requestOptions.uri}',
      name: 'API',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    log(
      '✕ ${err.response?.statusCode ?? 'NETWORK'} ${err.requestOptions.uri}: ${err.message}',
      name: 'API',
      level: 1000,
    );
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
    switch (statusCode) {
      case 400:
        return 'Invalid request. Please check your input.';
      case 401:
        return 'Session expired. Please login again.';
      case 403:
        return 'You do not have permission for this action.';
      case 404:
        return 'Resource not found.';
      case 422:
        return 'Validation failed. Please check your input.';
      case 429:
        return 'Too many requests. Please wait and try again.';
      case 500:
        return 'Server error. Please try again later.';
      case 503:
        return 'Service temporarily unavailable.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
