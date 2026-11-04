import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/server_time.dart';

/// `POST /membership/checkout` request — the ONLY place its body is built.
///
/// The contract accepts `{ planCode, months, promoCode? }` and rejects extra
/// fields with a 400, and the client never sends an amount (the server
/// prices it). `promoCode` is sent only when the member typed one: an empty
/// or blank code is left out entirely, never sent as `""` or `null`.
class CheckoutRequest {
  const CheckoutRequest({
    required this.planCode,
    required this.months,
    this.promoCode,
  });

  final String planCode;
  final int months;
  final String? promoCode;

  Map<String, dynamic> toJson() {
    final code = promoCode?.trim();
    return {
      'planCode': planCode,
      'months': months,
      if (code != null && code.isNotEmpty) 'promoCode': code,
    };
  }
}

/// `422 PROMO_CODE_REJECTED` from `POST /membership/checkout`: the typed
/// referral code gives no discount. [reason] is the contract's machine code
/// (`INVALID`, `NOT_FIRST_PLAN`, `ALREADY_ATTRIBUTED`, `SELF_REFERRAL`,
/// `AGENT_PAUSED`, `PHONE_NOT_VERIFIED`, or one this version doesn't know).
class PromoCodeRejectedException extends ApiException {
  PromoCodeRejectedException(String message, {this.reason})
    : super(422, message, code: kPromoCodeRejected);

  final String? reason;
}

const String kPromoCodeRejected = 'PROMO_CODE_REJECTED';

/// The server's price breakdown for one checkout, all integer paise.
///
/// `totalPaise = listAmountPaise − discountPaise + taxPaise` on the server;
/// the app shows these values and never recomputes them.
class CheckoutPricing {
  const CheckoutPricing({
    required this.listAmountPaise,
    required this.discountPaise,
    required this.discountSource,
    required this.taxableAmountPaise,
    required this.taxRateBps,
    required this.taxPaise,
    required this.totalPaise,
  });

  /// Null when the body has no usable `pricing` object.
  static CheckoutPricing? tryFromJson(Object? json) {
    if (json is! Map) return null;
    int paise(String key) {
      final v = json[key];
      return v is num && v.isFinite && v >= 0 ? v.toInt() : 0;
    }

    return CheckoutPricing(
      listAmountPaise: paise('listAmountPaise'),
      discountPaise: paise('discountPaise'),
      discountSource: json['discountSource'] as String? ?? 'NONE',
      taxableAmountPaise: paise('taxableAmountPaise'),
      taxRateBps: paise('taxRateBps'),
      taxPaise: paise('taxPaise'),
      totalPaise: paise('totalPaise'),
    );
  }

  final int listAmountPaise;
  final int discountPaise;

  /// `NONE` or `REFERRAL_FIRST_PLAN`.
  final String discountSource;
  final int taxableAmountPaise;

  /// GST rate in basis points (`1800` = 18%). 0 until GST-registered.
  final int taxRateBps;
  final int taxPaise;
  final int totalPaise;

  bool get hasDiscount => discountPaise > 0;
  bool get hasTax => taxPaise > 0;
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
    this.pricing,
    this.referralAgentName,
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
      pricing: CheckoutPricing.tryFromJson(json['pricing']),
      referralAgentName: switch (json['referral']) {
        {'agentDisplayName': final String name} when name.isNotEmpty => name,
        _ => null,
      },
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

  /// The breakdown to show before paying. Null from a server that doesn't
  /// send one; [amountInPaise] is then the only figure shown.
  final CheckoutPricing? pricing;

  /// `referral.agentDisplayName`, when a referral discount applies.
  final String? referralAgentName;

  /// Whether this has what the payment sheet needs. Razorpay always charges
  /// [amountInPaise] (the server's `totalPaise`).
  bool get isPayable =>
      orderId.isNotEmpty && keyId.isNotEmpty && amountInPaise > 0;
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
