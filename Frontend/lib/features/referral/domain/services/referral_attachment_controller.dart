import '../../../../core/network/api_exception.dart';
import '../../data/services/pending_referral_store.dart';
import '../models/referral_models.dart';
import '../repositories/referral_repository.dart';

/// What one attach attempt came to. Only the first four are final; a final
/// outcome removes the stored code, so it is never sent again.
enum ReferralAttachOutcome {
  /// `200` — the member is now credited to the code's agent.
  attached,

  /// `409 ALREADY_ATTRIBUTED` — the first agent always stays.
  alreadyAttributed,

  /// `404 CODE_NOT_FOUND`, or a `400` (the code cannot pass validation).
  codeNotFound,

  /// `422 SELF_REFERRAL`.
  notAllowed,

  /// Network, `401`, `429`, `5xx` or a code the contract does not list (the
  /// remaining attach error codes are still pending). The code is kept and
  /// retried at the next trigger point, up to [ReferralAttachmentController
  /// .maxAttempts] times.
  retryLater,

  /// [ReferralAttachmentController.maxAttempts] retryable failures in a row:
  /// the code is dropped rather than retried for ever.
  gaveUp,

  /// No code is waiting.
  nothingPending,

  /// A code is waiting but there is no Firebase session to attach it with.
  /// Kept untouched.
  notSignedIn,
}

/// Attaches the stored referral code once — and only once — the member is
/// signed in.
///
/// Not an interceptor and not tied to every request: it runs only at three
/// controlled points (the name step's save when already signed in, the end of
/// the verify-mobile step, and a cold start with a restored session), each
/// after an authenticated call has already succeeded.
///
/// Idempotent by construction:
/// - single-flight — a second call while one is running joins it;
/// - a final answer (success or a contract-defined refusal) clears the code;
/// - retryable failures are capped at [maxAttempts].
///
/// Never throws and never logs the code: a referral code must never block
/// signup or sign-in.
class ReferralAttachmentController {
  ReferralAttachmentController({
    required ReferralRepository repository,
    required PendingReferralStore store,
    required bool Function() isSignedIn,
    bool Function()? isEnabled,
  }) : _repository = repository,
       _store = store,
       _isSignedIn = isSignedIn,
       _isEnabled = isEnabled ?? _always;

  static bool _always() => true;

  /// Client-side cap on retryable failures — not a contract value.
  static const int maxAttempts = 3;

  final ReferralRepository _repository;
  final PendingReferralStore _store;
  final bool Function() _isSignedIn;

  /// False when the feature is off (a non-debug build whose endpoints are
  /// not live): then nothing is sent and any stored code is left alone.
  final bool Function() _isEnabled;

  Future<ReferralAttachOutcome>? _inFlight;

  Future<ReferralAttachOutcome> attachPending() {
    return _inFlight ??= _attempt().whenComplete(() => _inFlight = null);
  }

  Future<ReferralAttachOutcome> _attempt() async {
    try {
      if (!_isEnabled()) return ReferralAttachOutcome.nothingPending;
      final pending = _store.read();
      if (pending == null) return ReferralAttachOutcome.nothingPending;
      if (!_isSignedIn()) return ReferralAttachOutcome.notSignedIn;

      try {
        final result = await _repository.attachCode(pending.code);
        // The contract's 200 is `attached: true`; it does not define a 200
        // with `attached: false`. Such a body is not treated as success —
        // the code is kept and retried within the cap rather than cleared.
        if (!result.attached) return _retryOrGiveUp(pending);
      } on ApiException catch (e) {
        final mapped = outcomeForError(e);
        if (mapped != ReferralAttachOutcome.retryLater) {
          await _store.clear();
          return mapped;
        }
        return _retryOrGiveUp(pending);
      } catch (_) {
        return _retryOrGiveUp(pending);
      }
      await _store.clear();
      return ReferralAttachOutcome.attached;
    } catch (_) {
      return ReferralAttachOutcome.retryLater;
    }
  }

  Future<ReferralAttachOutcome> _retryOrGiveUp(
    PendingReferralCode pending,
  ) async {
    final next = pending.withAttempt();
    if (next.attempts >= maxAttempts) {
      await _store.clear();
      return ReferralAttachOutcome.gaveUp;
    }
    await _store.write(next);
    return ReferralAttachOutcome.retryLater;
  }

  /// Maps an attach refusal by its contract `code`, never by its message.
  static ReferralAttachOutcome outcomeForError(ApiException e) {
    switch (e.code) {
      case 'ALREADY_ATTRIBUTED':
        return ReferralAttachOutcome.alreadyAttributed;
      case 'CODE_NOT_FOUND':
        return ReferralAttachOutcome.codeNotFound;
      case 'SELF_REFERRAL':
        return ReferralAttachOutcome.notAllowed;
    }
    // A 400 is a body the server will refuse every time; retrying is futile.
    if (e.statusCode == 400) return ReferralAttachOutcome.codeNotFound;
    return ReferralAttachOutcome.retryLater;
  }
}
