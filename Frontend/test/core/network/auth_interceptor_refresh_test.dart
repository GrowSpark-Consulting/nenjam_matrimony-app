import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_interceptor.dart';

/// Single-flight coverage for [AuthInterceptor]'s 401 recovery: several
/// requests that 401 around the same time must share one force-refresh
/// rather than each starting its own.
void main() {
  Dio buildDio({required Response<dynamic> Function(RequestOptions) onFetch}) {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.httpClientAdapter = _FakeAdapter(onFetch);
    return dio;
  }

  group('AuthInterceptor 401 recovery — single-flight refresh', () {
    test('one 401 triggers exactly one refresh', () async {
      var refreshCalls = 0;
      final dio = buildDio(
        onFetch: (_) => Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 200,
          data: 'ok',
        ),
      );
      final interceptor = AuthInterceptor(
        dio: dio,
        getAccessToken: () async => 'stale-token',
        refreshAccessToken: () async {
          refreshCalls++;
          return 'fresh-token';
        },
        onSessionExpired: () async {},
      );

      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: '/profiles/me'),
        statusCode: 401,
      );
      final handler = ResponseInterceptorHandler();
      await interceptor.onResponse(response, handler);

      expect(refreshCalls, 1);
    });

    test('multiple simultaneous 401s share exactly one refresh', () async {
      var refreshCalls = 0;
      final dio = buildDio(
        onFetch: (_) => Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 200,
          data: 'ok',
        ),
      );
      final interceptor = AuthInterceptor(
        dio: dio,
        getAccessToken: () async => 'stale-token',
        refreshAccessToken: () async {
          refreshCalls++;
          // Simulate a real network round trip so the concurrent 401s below
          // are genuinely in flight at the same time, not sequential.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return 'fresh-token';
        },
        onSessionExpired: () async {},
      );

      Future<void> fire401(String path) {
        final response = Response<dynamic>(
          requestOptions: RequestOptions(path: path),
          statusCode: 401,
        );
        return interceptor.onResponse(response, ResponseInterceptorHandler());
      }

      await Future.wait([
        fire401('/profiles/me'),
        fire401('/matches'),
        fire401('/interests'),
      ]);

      expect(refreshCalls, 1);
    });

    test('waiting requests retry using the refreshed token', () async {
      final seenAuthHeaders = <String>[];
      final dio = buildDio(
        onFetch: (options) {
          seenAuthHeaders.add(options.headers['Authorization'] as String);
          return Response(
            requestOptions: options,
            statusCode: 200,
            data: 'ok',
          );
        },
      );
      final interceptor = AuthInterceptor(
        dio: dio,
        getAccessToken: () async => 'stale-token',
        refreshAccessToken: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return 'fresh-token';
        },
        onSessionExpired: () async {},
      );

      Future<void> fire401(String path) {
        final options = RequestOptions(path: path)
          ..headers['Authorization'] = 'Bearer stale-token';
        final response = Response<dynamic>(
          requestOptions: options,
          statusCode: 401,
        );
        return interceptor.onResponse(response, ResponseInterceptorHandler());
      }

      await Future.wait([fire401('/profiles/me'), fire401('/matches')]);

      expect(seenAuthHeaders, everyElement('Bearer fresh-token'));
    });

    test('refresh failure preserves existing session-expiry behavior', () async {
      var sessionExpiredCalls = 0;
      final dio = buildDio(
        onFetch: (_) => Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 200,
          data: 'ok',
        ),
      );
      final interceptor = AuthInterceptor(
        dio: dio,
        getAccessToken: () async => 'stale-token',
        refreshAccessToken: () async => null,
        onSessionExpired: () async {
          sessionExpiredCalls++;
        },
      );

      final options = RequestOptions(path: '/profiles/me')
        ..headers['Authorization'] = 'Bearer stale-token';
      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 401,
      );
      final handler = ResponseInterceptorHandler();
      await interceptor.onResponse(response, handler);

      expect(sessionExpiredCalls, 1);
    });

    test('a later 401, after refresh settled, triggers a new refresh', () async {
      var refreshCalls = 0;
      final dio = buildDio(
        onFetch: (_) => Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 200,
          data: 'ok',
        ),
      );
      final interceptor = AuthInterceptor(
        dio: dio,
        getAccessToken: () async => 'stale-token',
        refreshAccessToken: () async {
          refreshCalls++;
          return 'fresh-token';
        },
        onSessionExpired: () async {},
      );

      Future<void> fire401(String path) {
        final response = Response<dynamic>(
          requestOptions: RequestOptions(path: path),
          statusCode: 401,
        );
        return interceptor.onResponse(response, ResponseInterceptorHandler());
      }

      await fire401('/profiles/me');
      await fire401('/matches');

      expect(refreshCalls, 2);
    });
  });
}

/// Minimal fake transport: satisfies `dio.fetch` (used by the retry inside
/// `_recover`) without touching the network. [onFetch] answers every replayed
/// request.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.onFetch);

  final Response<dynamic> Function(RequestOptions options) onFetch;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = onFetch(options);
    return ResponseBody.fromString(
      response.data as String? ?? '',
      response.statusCode ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.textPlainContentType],
      },
    );
  }
}
