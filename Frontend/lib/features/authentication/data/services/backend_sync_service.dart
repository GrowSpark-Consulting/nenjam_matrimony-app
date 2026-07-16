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
Future<void> syncUserWithBackend(ApiClient apiClient) async {
  try {
    await apiClient.get<dynamic>(ApiEndpoints.profileMe);
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) return;
    if (kDebugMode) {
      debugPrint('[Auth] Backend profile sync failed: ${e.type}, status ${e.response?.statusCode}');
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[Auth] Backend profile sync failed: ${e.runtimeType}');
    }
  }
}
