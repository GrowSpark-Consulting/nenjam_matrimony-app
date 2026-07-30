import '../entities/blocked_user_entity.dart';
import '../entities/report_reason.dart';

/// Block / report a member by their user id. Block/unblock are idempotent on
/// the backend (re-blocking/re-unblocking never errors), so this interface
/// has no local "is blocked" state to track — Discover/Search/Matches simply
/// stop returning a blocked member once the request completes.
abstract interface class SafetyRepository {
  /// `POST /users/:id/block`.
  Future<void> blockUser(String userId);

  /// `DELETE /users/:id/block`.
  Future<void> unblockUser(String userId);

  /// `POST /users/:id/report`.
  Future<void> reportUser(
    String userId, {
    required ReportReason reason,
    String? description,
  });

  /// `GET /users/blocked` — the caller's blocked members, newest-blocked
  /// first, each as a Discover card plus when the block happened.
  Future<BlockedUsersPage> getBlockedUsers({int page = 1, int limit = 20});
}
