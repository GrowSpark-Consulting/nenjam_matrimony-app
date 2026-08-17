import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';

/// Syncs the signed-in Firebase user to the NestJS + PostgreSQL backend.
///
/// Firebase alone never creates a Postgres row — `FirebaseAuthGuard` on the
/// backend does that as a side effect of verifying the ID token on any
/// guarded request. `GET /profiles/me` is the lightest such request, so
/// calling it right after auth success (and once per app resume) is enough
/// to keep the two systems in sync.
///
/// Fire-and-forget by design: a 404 just means the profile hasn't been
/// finalized yet (registration wizard not completed) — expected, not an
/// error. Any other failure is logged only, never surfaced to the user or
/// allowed to block navigation, since Firebase remains the source of truth
/// for "is this user logged in."
///
/// Note the status is inspected on the *response*, not caught: [ApiClient]
/// sets `validateStatus: status < 500`, so no 4xx ever raises a
/// [DioException] here. The catch below is for 5xx and transport failures.
Future<void> syncUserWithBackend(ApiClient apiClient) async {
  try {
    final response = await apiClient.get<dynamic>(ApiEndpoints.profileMe);
    final status = response.statusCode;
    // 404 = profile not finalized yet. Anything else in the 4xx range is a
    // genuine problem (403 from a disabled account, 422, …) that would
    // otherwise vanish silently, since it neither throws nor blocks startup.
    if (status != null && status >= 400 && status != 404 && kDebugMode) {
      debugPrint('[Auth] Backend profile sync rejected: status $status');
    }
  } on DioException catch (e) {
    if (kDebugMode) {
      debugPrint(
        '[Auth] Backend profile sync failed: ${e.type}, status ${e.response?.statusCode}',
      );
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[Auth] Backend profile sync failed: ${e.runtimeType}');
    }
  }
}
