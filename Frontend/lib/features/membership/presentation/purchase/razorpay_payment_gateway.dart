import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../domain/models/checkout_models.dart';
import 'membership_purchase.dart';

/// [PaymentGateway] over the native Razorpay Checkout (`razorpay_flutter`),
/// for the Android and iOS apps only — [paymentGatewayProvider] never builds
/// this on web.
///
/// One SDK instance lives as long as the gateway (Razorpay's intended use),
/// created on the first payment so that nothing touches the platform channel
/// until the member actually pays. Its callbacks complete the one payment in
/// progress, at most once; anything arriving with no payment in progress
/// (such as a result the SDK re-delivers after the app was recreated) is
/// ignored. A success for a different order is ignored too: verify is keyed
/// on the order, and the webhook still activates that older payment.
///
/// Nothing here grants anything: a success only hands the three values to
/// `POST /membership/checkout/verify`.
class RazorpayPaymentGateway implements PaymentGateway {
  RazorpayPaymentGateway({Razorpay Function()? createSdk})
    : _createSdk = createSdk ?? Razorpay.new;

  final Razorpay Function() _createSdk;
  Razorpay? _sdk;
  _PendingPayment? _pending;

  @override
  bool get isSupported => true;

  /// The Checkout options. The amount and currency are the server's
  /// (`amountInPaise` = `pricing.totalPaise`), never computed here.
  @visibleForTesting
  static Map<String, dynamic> optionsFor(CheckoutSession session) => {
    'key': session.keyId,
    'order_id': session.orderId,
    'amount': session.amountInPaise,
    'currency': session.currency,
    'name': 'Nenjam Matrimony',
    if (session.planName.isNotEmpty) 'description': session.planName,
  };

  @override
  Future<PaymentResult> pay(CheckoutSession session) {
    if (_pending != null) {
      return Future.error(StateError('A payment is already in progress.'));
    }
    final pending = _PendingPayment(session.orderId);
    _pending = pending;
    // `on` and `open` call the platform channel without awaiting it, so a
    // missing or broken plugin surfaces as an uncaught async error. The zone
    // turns that into a failed payment instead of a crash or a hang.
    runZonedGuarded(
      () {
        final sdk = _sdk ??= _attach(_createSdk());
        sdk.open(optionsFor(session));
      },
      (error, _) {
        debugPrint('[Razorpay] checkout could not open: $error');
        _finish(pending, const PaymentFailed());
      },
    );
    return pending.completer.future;
  }

  /// Releases the SDK's listeners. The gateway can't be used afterwards.
  void dispose() {
    _sdk?.clear();
    _sdk = null;
    final pending = _pending;
    if (pending != null) _finish(pending, const PaymentCancelled());
  }

  Razorpay _attach(Razorpay sdk) {
    sdk
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _onError)
      // External wallets aren't offered (no `external` option), so this
      // only fires if Razorpay hands off anyway: the payment didn't happen
      // here, and the order stays PENDING.
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    return sdk;
  }

  void _onSuccess(Object? response) {
    final pending = _pending;
    if (pending == null || response is! PaymentSuccessResponse) return;
    final orderId = response.orderId;
    if (orderId != null && orderId != pending.orderId) return;
    final paymentId = response.paymentId;
    final signature = response.signature;
    _finish(
      pending,
      paymentId == null ||
              paymentId.isEmpty ||
              signature == null ||
              signature.isEmpty
          ? const PaymentUnconfirmed()
          : PaymentSucceeded(
              orderId: pending.orderId,
              paymentId: paymentId,
              signature: signature,
            ),
    );
  }

  void _onError(Object? response) {
    final pending = _pending;
    if (pending == null) return;
    final cancelled =
        response is PaymentFailureResponse &&
        response.code == Razorpay.PAYMENT_CANCELLED;
    _finish(
      pending,
      cancelled ? const PaymentCancelled() : const PaymentFailed(),
    );
  }

  void _onExternalWallet(Object? _) {
    final pending = _pending;
    if (pending != null) _finish(pending, const PaymentCancelled());
  }

  void _finish(_PendingPayment pending, PaymentResult result) {
    if (pending.completer.isCompleted) return;
    if (identical(_pending, pending)) _pending = null;
    pending.completer.complete(result);
  }
}

class _PendingPayment {
  _PendingPayment(this.orderId);

  final String orderId;
  final Completer<PaymentResult> completer = Completer<PaymentResult>();
}
