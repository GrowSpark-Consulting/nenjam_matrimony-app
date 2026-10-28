import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/checkout_models.dart';
import '../../domain/models/membership_models.dart';
import '../../domain/repositories/membership_repository.dart';
import '../providers/membership_providers.dart';

/// What the payment sheet reported. Only [PaymentSucceeded] leads to a verify
/// call; the contract says a closed or failed sheet must not be verified (the
/// `PENDING` checkout simply never activates).
sealed class PaymentResult {
  const PaymentResult();
}

class PaymentSucceeded extends PaymentResult {
  const PaymentSucceeded({
    required this.orderId,
    required this.paymentId,
    required this.signature,
  });

  final String orderId;
  final String paymentId;
  final String signature;
}

class PaymentCancelled extends PaymentResult {
  const PaymentCancelled();
}

class PaymentFailed extends PaymentResult {
  const PaymentFailed();
}

/// Opens the payment provider's checkout (Razorpay: `key: keyId`,
/// `order_id: orderId`, `amount`, `currency`).
///
/// No implementation ships yet: the app has no payment SDK dependency, web
/// purchases are undecided, and checkout is unavailable on the backend. The
/// default [UnsupportedPaymentGateway] keeps every Buy button hidden. Adding
/// Razorpay is one class implementing this, plus overriding
/// [paymentGatewayProvider].
abstract class PaymentGateway {
  /// False hides purchasing entirely on this platform/build.
  bool get isSupported;

  Future<PaymentResult> pay(CheckoutSession session);
}

class UnsupportedPaymentGateway implements PaymentGateway {
  const UnsupportedPaymentGateway();

  @override
  bool get isSupported => false;

  @override
  Future<PaymentResult> pay(CheckoutSession session) =>
      throw UnsupportedError('No payment provider in this build.');
}

final paymentGatewayProvider = Provider<PaymentGateway>(
  (ref) => const UnsupportedPaymentGateway(),
);

enum PurchaseResult {
  /// The plan is active (or queued) — `/membership/me` confirms it.
  activated,

  /// Paid, but `/membership/me` hasn't shown the plan within the polling
  /// window. The webhook activates it later; nothing is granted locally.
  activationPending,

  /// The member closed the payment sheet. Not verified.
  cancelled,

  /// The payment failed (`NOT_PAID`, `REFUNDED`, or the sheet reported a
  /// failure).
  paymentFailed,

  /// `AMOUNT_MISMATCH`, `PAID_NOT_ACTIVATED`, `UNKNOWN_ORDER`, or an outcome
  /// this version doesn't know. Operators are alerted server-side.
  contactSupport,

  /// No payment provider on this platform.
  unavailable,
}

/// Runs one purchase end to end, following the contract:
/// `POST /checkout` → payment sheet → `POST /checkout/verify` → act on
/// `outcome` → re-read `/membership/me`.
///
/// Errors from checkout/verify (400 not on sale, 502, 503, network) are
/// rethrown for the caller to show.
class MembershipPurchaseService {
  MembershipPurchaseService({
    required MembershipRepository repository,
    required PaymentGateway gateway,
    required Future<MyMembership> Function() refreshMe,
    Duration pollWindow = const Duration(seconds: 60),
    Future<void> Function(Duration) wait = _delay,
  }) : _repository = repository,
       _gateway = gateway,
       _refreshMe = refreshMe,
       _pollWindow = pollWindow,
       _wait = wait;

  final MembershipRepository _repository;
  final PaymentGateway _gateway;
  final Future<MyMembership> Function() _refreshMe;
  final Duration _pollWindow;
  final Future<void> Function(Duration) _wait;

  static Future<void> _delay(Duration d) => Future<void>.delayed(d);

  bool get isSupported => _gateway.isSupported;

  Future<PurchaseResult> purchase(PurchaseOption option) async {
    if (!_gateway.isSupported) return PurchaseResult.unavailable;

    final session = await _repository.startCheckout(
      CheckoutRequest(planCode: option.planCode, months: option.months),
    );

    final PaymentSucceeded payment;
    switch (await _gateway.pay(session)) {
      case PaymentCancelled():
        return PurchaseResult.cancelled;
      case PaymentFailed():
        return PurchaseResult.paymentFailed;
      case final PaymentSucceeded succeeded:
        payment = succeeded;
    }

    // The SDK's success callback is NOT proof of payment. Only the server's
    // verify — which fetches the payment from Razorpay — decides.
    final verified = await _repository.verifyCheckout(
      CheckoutVerifyRequest(
        orderId: payment.orderId,
        paymentId: payment.paymentId,
        signature: payment.signature,
      ),
    );

    switch (verified.outcome) {
      case VerifyOutcome.activated:
      case VerifyOutcome.alreadyApplied:
        await _refreshMe();
        return PurchaseResult.activated;
      case VerifyOutcome.awaitingCapture:
      case VerifyOutcome.pendingConfirmation:
        return _pollUntilActive(session.subscriptionId);
      case VerifyOutcome.notPaid:
      case VerifyOutcome.refunded:
        return PurchaseResult.paymentFailed;
      case VerifyOutcome.amountMismatch:
      case VerifyOutcome.paidNotActivated:
      case VerifyOutcome.unknownOrder:
      case VerifyOutcome.unknown:
        return PurchaseResult.contactSupport;
    }
  }

  /// Re-reads `/membership/me` with backoff (2s, 4s, 8s, …) for about
  /// [_pollWindow], until the new subscription shows up as current or queued.
  Future<PurchaseResult> _pollUntilActive(String subscriptionId) async {
    var elapsed = Duration.zero;
    var step = const Duration(seconds: 2);
    while (elapsed < _pollWindow) {
      await _wait(step);
      elapsed += step;
      try {
        final me = await _refreshMe();
        final active =
            me.subscription?.id == subscriptionId ||
            me.scheduled.any((s) => s.id == subscriptionId);
        if (active) return PurchaseResult.activated;
      } catch (_) {
        // A failed re-read is not a verdict; keep polling until the window
        // closes.
      }
      step *= 2;
    }
    return PurchaseResult.activationPending;
  }
}

final membershipPurchaseServiceProvider = Provider<MembershipPurchaseService>(
  (ref) => MembershipPurchaseService(
    repository: ref.watch(membershipRepositoryProvider),
    gateway: ref.watch(paymentGatewayProvider),
    refreshMe: () {
      ref.invalidate(myMembershipProvider);
      return ref.read(myMembershipProvider.future);
    },
  ),
);
