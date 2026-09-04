import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../utils/photo_trace.dart';
import '../utils/story_perf.dart';
import 'network_error_mapper.dart';

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
///
/// Both delivery paths are covered. The client's `validateStatus` accepts
/// anything below 500, so a 401 normally arrives as a *successful* response
/// and never reaches [onError] — [onResponse] is therefore the primary hook.
/// [onError] stays as the safety net for callers that pass their own
/// `validateStatus` (or a plain Dio built elsewhere).
///
/// Nothing in here may throw: an exception escaping an interceptor surfaces
/// to the caller as an opaque `DioException` at best, and on the token path
/// it would turn a recoverable signed-out state into a crash. Every await is
/// individually guarded and degrades to "send the request unauthenticated"
/// or "give the caller the original 401".
class AuthInterceptor extends Interceptor {
  final Dio dio;
  final Future<String?> Function() getAccessToken;
  final Future<String?> Function() refreshAccessToken;
  final Future<void> Function() onSessionExpired;

  /// Supplies the dummy-OTP identifier when there is no Firebase session, for
  /// builds that use the dummy OTP. Optional, and returns null on a build that
  /// does not, so the header is never sent by an ordinary release. See
  /// `local_auth_session.dart` and the backend's `dev-auth.ts`.
  final String? Function()? devAuthPhone;

  AuthInterceptor({
    required this.dio,
    required this.getAccessToken,
    required this.refreshAccessToken,
    required this.onSessionExpired,
    this.devAuthPhone,
  });

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _safeToken(getAccessToken);
    // Marks that the token LOOKUP finished, which is not the same as having
    // one — this fires with `token == null` too. Reading it as "a token was
    // obtained" is what made a session-less 401 look like a server fault.
    StoryPerf.mark('Firebase token lookup done (${options.path})');
    // TEMPORARY (PhotoTrace) — the photo routes are the ones under
    // investigation; this says whether the request actually left with
    // credentials, never what they were.
    if (options.path.contains('photos')) {
      PhotoTrace.step('auth header for ${options.method} ${options.path}', {
        'hasToken': token != null && token.isNotEmpty,
      });
    }
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    } else {
      // The dummy-OTP bridge, supplied from LocalAuthSession — null unless
      // this build uses the dummy OTP, so a normal release sends nothing.
      // Deliberately in the `else`: a real Firebase token always wins, and
      // the two headers are never sent together, which is also the condition
      // the backend guard requires before it will look at this header.
      final devPhone = devAuthPhone?.call();
      if (devPhone != null && devPhone.isNotEmpty) {
        options.headers['X-Dev-Auth-Phone'] = devPhone;
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    if (!_shouldAttemptRecovery(response.statusCode, response.requestOptions)) {
      return handler.next(response);
    }

    final recovered = await _recover(response.requestOptions);
    // Recovery failed — hand the caller the original 401 response rather
    // than an exception; repositories already treat a 401 body as "no data".
    return handler.next(recovered ?? response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_shouldAttemptRecovery(err.response?.statusCode, err.requestOptions)) {
      return handler.next(err);
    }

    final recovered = await _recover(err.requestOptions);
    if (recovered != null) return handler.resolve(recovered);
    return handler.next(err);
  }

  bool _shouldAttemptRecovery(int? statusCode, RequestOptions options) {
    if (statusCode != 401 || options.extra[_authRetriedKey] == true) {
      return false;
    }
    // A FormData body is single-use: Dio consumes it by calling finalize(),
    // which returns a stream that can only be read once. Replaying the same
    // RequestOptions therefore does not re-send the file — it throws inside
    // dio.fetch, _recover() swallows that as "recovery failed", and a photo
    // upload/replace that only needed a fresh token instead ended as an
    // opaque failure the member could not retry into. Hand the caller the
    // honest 401 (PhotoRepository turns it into a PhotoApiException the UI
    // already shows) rather than corrupting the retry. Deliberately not a
    // rebuild-the-FormData path: the bytes are the caller's, not ours.
    if (options.data is FormData) return false;
    // On a dummy-OTP session there is no Firebase token to refresh, so
    // recovery would refresh nothing, get null, and call onSessionExpired ->
    // logout -> the widgets refetch -> 401 again: a sign-out storm rather than
    // one honest error. A 401 here means the backend is not running with dummy
    // auth enabled, or the number is not whitelisted — a configuration answer,
    // not an expired session.
    if (devAuthPhone?.call() != null) return false;
    return true;
  }

  /// Force-refreshes the token and replays [options] exactly once.
  ///
  /// Returns the replayed response, or null when the session could not be
  /// recovered — in which case [onSessionExpired] has already run.
  Future<Response<dynamic>?> _recover(RequestOptions options) async {
    // Whether this request actually carried a token. onRequest sets the
    // header only when it got one, so its absence means the request was
    // never authenticated to begin with.
    final wasAuthenticated = options.headers.containsKey('Authorization');

    final refreshedToken = await _safeToken(refreshAccessToken);
    if (refreshedToken == null || refreshedToken.isEmpty) {
      // No session to refresh.
      //
      // Only a request that WAS authenticated and can no longer be is a
      // genuine expiry. Signing out unconditionally here is what turned a
      // startup race into a logout: a request issued before Firebase had
      // restored `currentUser` went out bare, took the backend's expected
      // 401, found no token to refresh, and tore down a session that was
      // about to become valid — killing any upload in flight and leaving the
      // member signed out with no explanation. AuthTokenService now waits for
      // the restore, and this is the second half of that fix: an
      // unauthenticated 401 is a "not signed in yet", not a "signed out".
      if (wasAuthenticated) await _safeSessionExpired();
      return null;
    }

    try {
      final retryOptions = options
        ..headers['Authorization'] = 'Bearer $refreshedToken'
        ..extra[_authRetriedKey] = true;
      final response = await dio.fetch<dynamic>(retryOptions);
      // `validateStatus` lets a second 401 through as a response, so the
      // status has to be re-checked here rather than caught below.
      if (response.statusCode == 401) {
        await _safeSessionExpired();
        return null;
      }
      return response;
    } catch (error) {
      if (error is DioException && error.response?.statusCode == 401) {
        await _safeSessionExpired();
      }
      return null;
    }
  }

  /// Token lookup can fail for reasons that are not the caller's problem —
  /// no signed-in user, a platform-channel error, an offline refresh. Treat
  /// every one as "no token" and let the request go out unauthenticated; the
  /// backend answers 401 and the normal expiry path takes over.
  Future<String?> _safeToken(Future<String?> Function() read) async {
    try {
      return await read();
    } catch (error) {
      if (kDebugMode) {
        log('token unavailable: $error', name: 'API', level: 900);
      }
      return null;
    }
  }

  /// Silent logout. Swallows failures deliberately: the user is already
  /// being signed out, and a throw here would escape the interceptor.
  Future<void> _safeSessionExpired() async {
    try {
      await onSessionExpired();
    } catch (error) {
      if (kDebugMode) {
        log('session teardown failed: $error', name: 'API', level: 1000);
      }
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
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (kDebugMode) {
      log(
        '← ${response.statusCode} ${response.requestOptions.uri}',
        name: 'API',
      );
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

/// Error Handling Interceptor — replaces Dio's own diagnostic text with the
/// localized, user-facing sentence from [NetworkErrorMapper], so anything
/// that renders `DioException.message` is already safe to show.
///
/// The exception is otherwise passed through untouched (same type, response
/// and cause), so callers that branch on `err.type` still work.
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: err.error,
        stackTrace: err.stackTrace,
        message: NetworkErrorMapper.message(err),
      ),
    );
  }
}
