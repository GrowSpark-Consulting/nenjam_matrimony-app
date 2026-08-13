import 'package:dio/dio.dart';

import '../constants/app_constants.dart';
import 'api_interceptor.dart';

/// Nenjam Matrimony — Dio API Client
///
/// Configured with timeouts, interceptors, and base URL.
/// Use this singleton for all network requests.
///
/// The base URL is [AppConstants.apiBaseUrl] — an origin with no path
/// segment, so endpoint constants (`/discover`, `/profiles/me`, …) resolve
/// exactly as written. The backend has no global `/v1` prefix.
class ApiClient {
  late final Dio _dio;

  Dio get dio => _dio;

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: AppConstants.apiConnectTimeout,
        receiveTimeout: AppConstants.apiReceiveTimeout,
        sendTimeout: AppConstants.apiSendTimeout,
        responseType: ResponseType.json,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-App-Version': AppConstants.appVersion,
        },
        // 4xx resolves normally so repositories can read the error body;
        // only 5xx becomes a DioException.
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    // Add interceptors in order. AuthInterceptor is inserted separately
    // (see addAuthInterceptor) once the token provider is ready, ahead of
    // these so it can attach the Authorization header before anything else
    // runs.
    _dio.interceptors.addAll([LoggingInterceptor(), ErrorInterceptor()]);
  }

  /// Adds the auth interceptor after storage is initialized.
  void addAuthInterceptor(AuthInterceptor interceptor) {
    _dio.interceptors.insert(0, interceptor);
  }

  // ─── Convenience Methods ─────────────────────────────────────────

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _dio.get<T>(
    path,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
  );

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _dio.post<T>(
    path,
    data: data,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
  );

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _dio.patch<T>(
    path,
    data: data,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
  );

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _dio.put<T>(
    path,
    data: data,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
  );

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) => _dio.delete<T>(
    path,
    data: data,
    queryParameters: queryParameters,
    options: options,
    cancelToken: cancelToken,
  );

  /// Upload file with multipart form data.
  Future<Response<T>> upload<T>(
    String path, {
    required FormData data,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
  }) => _dio.post<T>(
    path,
    data: data,
    options: options,
    cancelToken: cancelToken,
    onSendProgress: onSendProgress,
  );
}
