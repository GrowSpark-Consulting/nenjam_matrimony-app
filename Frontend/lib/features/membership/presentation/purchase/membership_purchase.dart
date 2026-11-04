import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../domain/models/checkout_models.dart';
import '../../domain/models/membership_models.dart';
import '../../domain/repositories/membership_repository.dart';
import '../providers/membership_providers.dart';
import 'razorpay_payment_gateway.dart';

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

/// The sheet reported success but without the values verify needs. Nothing
/// can be checked, so the member is sent to support rather than told the
/// payment failed (they may have been charged).
class PaymentUnconfirmed extends PaymentResult {
  const PaymentUnconfirmed();
}

/// Opens the payment provider's checkout (Razorpay: `key: keyId`,
/// `order_id: orderId`, `amount: amountInPaise`, `currency`).
///
/// Android and iOS use [RazorpayPaymentGateway]; web and every other
/// platform get [UnsupportedPaymentGateway], which keeps every Buy button
/// hidden (see [paymentGatewayProvider]).
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

/// Whether this platform buys through Razorpay: the Android and iOS apps
/// only. Web shows plans and "buy in the app" (the Razorpay plugin has no web
/// implementation), and desktop builds have no payment SDK.
bool supportsNativePayments({
  required bool isWeb,
  required TargetPlatform platform,
}) =>
    !isWeb &&
    (platform == TargetPlatform.android || platform == TargetPlatform.iOS);

final paymentGatewayProvider = Provider<PaymentGateway>((ref) {
  if (!supportsNativePayments(isWeb: kIsWeb, platform: defaultTargetPlatform)) {
    return const UnsupportedPaymentGateway();
  }
  final gateway = RazorpayPaymentGateway();
  ref.onDispose(gateway.dispose);
  return gateway;
});

enum PurchaseResult {
  /// `ACTIVATED` (or a pending payment that `/membership/me` now shows): the
  /// plan is active, or queued.
  activated,

  /// `ALREADY_APPLIED`: this payment had already been applied (for example
  /// by the webhook, or an earlier verify).
  alreadyApplied,

  /// Paid, but `/membership/me` hasn't shown the plan within the polling
  /// window. The webhook activates it later; nothing is granted locally.
  activationPending,

  /// The member closed the payment sheet. Not verified.
  cancelled,

  /// `NOT_PAID`, or the sheet reported a failure. The same order can be paid
  /// again.
  paymentFailed,

  /// `REFUNDED`: the payment was refunded, so nothing is granted.
  refunded,

  /// `AMOUNT_MISMATCH`, `PAID_NOT_ACTIVATED`, `UNKNOWN_ORDER`, an outcome
  /// this version doesn't know, or a verify the server refused. Operators
  /// are alerted server-side.
  contactSupport,

  /// The sheet reported success but verify couldn't be reached (timeout, no
  /// connection, 5xx, rate limit). The outcome is unknown: neither success
  /// nor failure is claimed, and the member must not pay again. Verify is
  /// safe to retry with the same values ([MembershipPurchaseService.confirm]).
  verificationUncertain,

  /// No payment provider on this platform.
  unavailable,
}

/// Runs one purchase, following the contract:
/// [startCheckout] (`POST /checkout`, which returns the price breakdown to
/// show) → [pay] (payment sheet → `POST /checkout/verify` → act on `outcome`
/// → re-read `/membership/me`). Nothing is granted on the sheet's word; only
/// verify's `outcome` and `/membership/me` decide.
///
/// Errors from checkout (400 not on sale, 422 promo refusals, 502, 503,
/// network) are rethrown for the caller to show.
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

  bool _paying = false;

  static Future<void> _delay(Duration d) => Future<void>.delayed(d);

  bool get isSupported => _gateway.isSupported;

  /// `POST /membership/checkout` for [option]. [promoCode] is sent only when
  /// non-blank. Creates a `PENDING` order; nothing is granted.
  Future<CheckoutSession> startCheckout(
    PurchaseOption option, {
    String? promoCode,
  }) async {
    if (!_gateway.isSupported) {
      throw StateError('No payment provider on this platform.');
    }
    return _repository.startCheckout(
      CheckoutRequest(
        planCode: option.planCode,
        months: option.months,
        promoCode: promoCode,
      ),
    );
  }

  /// Opens the payment sheet for [session], then verifies with the server.
  ///
  /// [onPaid] fires once the sheet reports success, before verify, with the
  /// values a retry of [confirm] needs; [onActivating] as in [confirm]. A
  /// second call while one is still running throws [StateError] rather than
  /// opening a second sheet.
  Future<PurchaseResult> pay(
    CheckoutSession session, {
    void Function(PaymentSucceeded payment)? onPaid,
    void Function()? onActivating,
  }) async {
    if (!_gateway.isSupported) return PurchaseResult.unavailable;
    if (_paying) throw StateError('A payment is already in progress.');
    _paying = true;
    try {
      if (!session.isPayable) return PurchaseResult.paymentFailed;
      final PaymentSucceeded payment;
      switch (await _gateway.pay(session)) {
        case PaymentCancelled():
          return PurchaseResult.cancelled;
        case PaymentFailed():
          return PurchaseResult.paymentFailed;
        case PaymentUnconfirmed():
          return PurchaseResult.contactSupport;
        case final PaymentSucceeded succeeded:
          payment = succeeded;
      }
      onPaid?.call(payment);
      return await confirm(session, payment, onActivating: onActivating);
    } finally {
      _paying = false;
    }
  }

  /// `POST /membership/checkout/verify` with the sheet's success values, then
  /// acts on `outcome`. Safe to call again with the same values: a retry
  /// after activation returns `ALREADY_APPLIED`.
  ///
  /// [onActivating] fires when the server has the payment but hasn't
  /// activated the plan yet (`AWAITING_CAPTURE`, `PENDING_CONFIRMATION`),
  /// while `/membership/me` is polled.
  Future<PurchaseResult> confirm(
    CheckoutSession session,
    PaymentSucceeded payment, {
    void Function()? onActivating,
  }) async {
    // The SDK's success callback is NOT proof of payment. Only the server's
    // verify — which fetches the payment from Razorpay — decides.
    final CheckoutVerifyResult verified;
    try {
      verified = await _repository.verifyCheckout(
        CheckoutVerifyRequest(
          orderId: payment.orderId,
          paymentId: payment.paymentId,
          signature: payment.signature,
        ),
      );
    } on ApiException catch (e) {
      // 429 and coded 5xx: verify didn't run, so nothing is known yet.
      // 400 bad signature / 404 not your order: the server said no.
      final retryable = e.statusCode == 429 || (e.statusCode ?? 0) >= 500;
      return retryable
          ? PurchaseResult.verificationUncertain
          : PurchaseResult.contactSupport;
    } on DioException {
      // Timeout, no connection, 502/503: the payment may well have gone
      // through, so this is never reported as a failure.
      return PurchaseResult.verificationUncertain;
    }

    switch (verified.outcome) {
      case VerifyOutcome.activated:
        await _refreshMeQuietly();
        return PurchaseResult.activated;
      case VerifyOutcome.alreadyApplied:
        await _refreshMeQuietly();
        return PurchaseResult.alreadyApplied;
      case VerifyOutcome.awaitingCapture:
      case VerifyOutcome.pendingConfirmation:
        onActivating?.call();
        return _pollUntilActive(session.subscriptionId);
      case VerifyOutcome.notPaid:
        return PurchaseResult.paymentFailed;
      case VerifyOutcome.refunded:
        return PurchaseResult.refunded;
      case VerifyOutcome.amountMismatch:
      case VerifyOutcome.paidNotActivated:
      case VerifyOutcome.unknownOrder:
      case VerifyOutcome.unknown:
        return PurchaseResult.contactSupport;
    }
  }

  /// Verify already decided; a failed re-read changes nothing.
  Future<void> _refreshMeQuietly() async {
    try {
      await _refreshMe();
    } catch (_) {}
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
