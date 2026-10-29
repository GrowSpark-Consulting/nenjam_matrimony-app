import '../../../../core/utils/server_time.dart';

/// `POST /membership/checkout` request — the ONLY place its body is built.
///
/// The contract accepts exactly `{ planCode, months }` and rejects extra
/// fields with a 400, and the client never sends an amount (the server
/// prices it). When the referral promo-code box ships, add the field here
/// (and only once the backend accepts it), so every caller picks it up.
class CheckoutRequest {
  const CheckoutRequest({required this.planCode, required this.months});

  final String planCode;
  final int months;

  Map<String, dynamic> toJson() => {'planCode': planCode, 'months': months};
}

/// `POST /membership/checkout` 201 response. Nothing is granted yet — the
/// subscription is `PENDING` until verify (or the webhook) activates it.
class CheckoutSession {
  const CheckoutSession({
    required this.subscriptionId,
    required this.orderId,
    required this.amountInPaise,
    required this.currency,
    required this.keyId,
    required this.planCode,
    required this.planName,
    required this.months,
  });

  factory CheckoutSession.fromJson(Map<String, dynamic> json) {
    final plan = json['plan'] is Map
        ? json['plan'] as Map
        : const <String, dynamic>{};
    return CheckoutSession(
      subscriptionId: json['subscriptionId'] as String? ?? '',
      orderId: json['orderId'] as String? ?? '',
      amountInPaise: (json['amountInPaise'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'INR',
      keyId: json['keyId'] as String? ?? '',
      planCode: plan['code'] as String? ?? '',
      planName: plan['name'] as String? ?? '',
      months: (json['months'] as num?)?.toInt() ?? 0,
    );
  }

  final String subscriptionId;
  final String orderId;
  final int amountInPaise;
  final String currency;
  final String keyId;
  final String planCode;
  final String planName;
  final int months;
}

/// `POST /membership/checkout/verify` request: exactly the payment SDK's
/// success-handler values.
class CheckoutVerifyRequest {
  const CheckoutVerifyRequest({
    required this.orderId,
    required this.paymentId,
    required this.signature,
  });

  final String orderId;
  final String paymentId;
  final String signature;

  Map<String, dynamic> toJson() => {
    'orderId': orderId,
    'paymentId': paymentId,
    'signature': signature,
  };
}

enum VerifyOutcome {
  activated,
  alreadyApplied,
  awaitingCapture,
  pendingConfirmation,
  notPaid,
  refunded,
  amountMismatch,
  paidNotActivated,
  unknownOrder,

  /// A value this app version doesn't know. Treated as "not granted".
  unknown,
}

class CheckoutVerifyResult {
  const CheckoutVerifyResult({
    required this.outcome,
    required this.subscriptionId,
    this.status,
    this.startDate,
    this.endDate,
  });

  factory CheckoutVerifyResult.fromJson(Map<String, dynamic> json) =>
      CheckoutVerifyResult(
        outcome: switch (json['outcome']) {
          'ACTIVATED' => VerifyOutcome.activated,
          'ALREADY_APPLIED' => VerifyOutcome.alreadyApplied,
          'AWAITING_CAPTURE' => VerifyOutcome.awaitingCapture,
          'PENDING_CONFIRMATION' => VerifyOutcome.pendingConfirmation,
          'NOT_PAID' => VerifyOutcome.notPaid,
          'REFUNDED' => VerifyOutcome.refunded,
          'AMOUNT_MISMATCH' => VerifyOutcome.amountMismatch,
          'PAID_NOT_ACTIVATED' => VerifyOutcome.paidNotActivated,
          'UNKNOWN_ORDER' => VerifyOutcome.unknownOrder,
          _ => VerifyOutcome.unknown,
        },
        subscriptionId: json['subscriptionId'] as String? ?? '',
        status: json['status'] as String?,
        startDate: tryParseServerTime(json['startDate']),
        endDate: tryParseServerTime(json['endDate']),
      );

  final VerifyOutcome outcome;
  final String subscriptionId;
  final String? status;

  /// Set only once the plan is really active.
  final DateTime? startDate;
  final DateTime? endDate;
}
