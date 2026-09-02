import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_providers.dart';

/// Whether an email or mobile number already belongs to an account.
///
/// Three outcomes, not two: "free", "taken", and **"could not tell"**. The
/// third exists because treating a failed lookup as "free" is exactly how
/// duplicate accounts get created, so callers must handle it explicitly
/// rather than falling through to the happy path.
class AccountAvailability {
  final bool emailExists;
  final bool phoneExists;

  const AccountAvailability({
    required this.emailExists,
    required this.phoneExists,
  });

  bool get anyExists => emailExists || phoneExists;
}

/// Thrown when the check could not be completed — no network, the endpoint
/// unreachable, the server erroring. Never means "available".
class AccountAvailabilityUnavailable implements Exception {
  const AccountAvailabilityUnavailable();
}

/// Looks up whether identifiers are already registered.
///
/// A seam, so the signup screen depends on the question rather than on
/// where the answer comes from, and so a test can supply an answer without
/// a network.
abstract interface class AccountAvailabilityChecker {
  /// Both identifiers in one call. Throws [AccountAvailabilityUnavailable]
  /// when the answer cannot be established.
  Future<AccountAvailability> check({
    required String email,
    required String phoneE164,
  });
}

/// Asks the backend, which asks Firebase Auth — the app's actual account
/// store. Unauthenticated by design: this runs before an account exists.
class ApiAccountAvailabilityChecker implements AccountAvailabilityChecker {
  ApiAccountAvailabilityChecker(this._client);

  final ApiClient _client;

  @override
  Future<AccountAvailability> check({
    required String email,
    required String phoneE164,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiEndpoints.accountExists,
        data: {
          // Normalized here so the value the backend matches on is the same
          // one Firebase stores — it lowercases addresses, and a stray space
          // from an autofill would otherwise read as a different account.
          'email': normalizeEmail(email),
          'phone': phoneE164.trim(),
        },
      );
      final data = response.data;
      if (data == null) throw const AccountAvailabilityUnavailable();
      return AccountAvailability(
        emailExists: data['emailExists'] == true,
        phoneExists: data['phoneExists'] == true,
      );
    } on DioException {
      throw const AccountAvailabilityUnavailable();
    } on AccountAvailabilityUnavailable {
      rethrow;
    } catch (_) {
      throw const AccountAvailabilityUnavailable();
    }
  }

  /// The one normalization rule, matching the backend's: trimmed and
  /// lowercased. Kept here so caller and server can never disagree.
  static String normalizeEmail(String email) => email.trim().toLowerCase();
}

final accountAvailabilityProvider = Provider<AccountAvailabilityChecker>(
  (ref) => ApiAccountAvailabilityChecker(ref.watch(apiClientProvider)),
);
