import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/membership/data/repositories/mock_membership_repository.dart';
import 'package:nenjam_matrimony/features/membership/domain/models/checkout_models.dart';
import 'package:nenjam_matrimony/features/membership/domain/models/membership_models.dart';
import 'package:nenjam_matrimony/features/membership/presentation/purchase/membership_purchase.dart';

/// The purchase flow follows the contract: checkout → payment sheet → verify
/// → act on `outcome` → re-read `/membership/me`. A payment callback alone
/// never grants anything.
void main() {
  const option = PurchaseOption(
    planCode: 'GOLD',
    planName: 'Gold',
    months: 3,
    priceInPaise: 399900,
    currency: 'INR',
    kind: PurchaseKind.newPlan,
  );

  late _FakeRepo repo;
  late _FakeGateway gateway;
  late int meReads;
  late MyMembership Function() currentMe;

  MembershipPurchaseService service() => MembershipPurchaseService(
    repository: repo,
    gateway: gateway,
    refreshMe: () async {
      meReads++;
      return currentMe();
    },
    wait: (_) async {},
  );

  Future<PurchaseResult> buy([MembershipPurchaseService? s]) async {
    final svc = s ?? service();
    return svc.pay(await svc.startCheckout(option));
  }

  MyMembership meWith({String? subscriptionId, String? scheduledId}) =>
      MyMembership.fromJson({
        'source': subscriptionId == null ? 'FREE' : 'SUBSCRIPTION',
        if (subscriptionId != null)
          'subscription': {'id': subscriptionId, 'planCode': 'GOLD'},
        'scheduled': [
          if (scheduledId != null) {'id': scheduledId, 'planCode': 'GOLD'},
        ],
      });

  setUp(() {
    repo = _FakeRepo();
    gateway = _FakeGateway();
    meReads = 0;
    currentMe = () => meWith();
  });

  group('platform', () {
    test('Android and iOS buy through Razorpay', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(
          supportsNativePayments(isWeb: false, platform: platform),
          isTrue,
          reason: '$platform',
        );
      }
    });

    test('web never buys, whatever the browser platform', () {
      for (final platform in TargetPlatform.values) {
        expect(
          supportsNativePayments(isWeb: true, platform: platform),
          isFalse,
          reason: '$platform',
        );
      }
    });

    test('desktop builds have no payment SDK', () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          supportsNativePayments(isWeb: false, platform: platform),
          isFalse,
        );
      }
    });

    test('the unsupported gateway hides purchasing', () {
      expect(const UnsupportedPaymentGateway().isSupported, isFalse);
    });
  });

  test('no payment provider → no checkout is started', () async {
    gateway.supported = false;
    final s = service();
    expect(s.isSupported, isFalse);
    await expectLater(s.startCheckout(option), throwsStateError);
    expect(repo.checkoutRequests, isEmpty);
  });

  group('checkout request', () {
    test('no code entered → exactly planCode + months', () async {
      await service().startCheckout(option);
      expect(repo.checkoutRequests.single.toJson(), {
        'planCode': 'GOLD',
        'months': 3,
      });
    });

    test('a blank code is left out, not sent empty', () async {
      await service().startCheckout(option, promoCode: '   ');
      expect(
        repo.checkoutRequests.single.toJson().containsKey('promoCode'),
        isFalse,
      );
    });

    test('a typed code is sent as promoCode', () async {
      await service().startCheckout(option, promoCode: 'NM7K2P9X');
      expect(repo.checkoutRequests.single.toJson(), {
        'planCode': 'GOLD',
        'months': 3,
        'promoCode': 'NM7K2P9X',
      });
    });

    test('a promo refusal reaches the caller untouched', () async {
      repo.checkoutError = ApiException(
        422,
        'That code can’t be used for this purchase.',
        code: 'PROMO_CODE_REJECTED',
      );
      await expectLater(
        service().startCheckout(option, promoCode: 'NM7K2P9X'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'PROMO_CODE_REJECTED',
          ),
        ),
      );
    });
  });

  test('the gateway gets the server session as returned', () async {
    repo.outcome = 'ACTIVATED';
    await buy();
    final session = gateway.sessions.single;
    expect(session.keyId, 'rzp_test_x');
    expect(session.orderId, 'order_1');
    expect(session.amountInPaise, 379905);
    expect(session.currency, 'INR');
  });

  test('cancelled or failed sheet → no verify call, nothing granted', () async {
    gateway.result = const PaymentCancelled();
    expect(await buy(), PurchaseResult.cancelled);
    gateway.result = const PaymentFailed();
    expect(await buy(), PurchaseResult.paymentFailed);
    expect(repo.verifyRequests, isEmpty);
    expect(meReads, 0);
  });

  test('success without verify values → support, never verified', () async {
    gateway.result = const PaymentUnconfirmed();
    expect(await buy(), PurchaseResult.contactSupport);
    expect(repo.verifyRequests, isEmpty);
  });

  test('a session with no order is never sent to the sheet', () async {
    final s = service();
    final session = CheckoutSession.fromJson(const {'amountInPaise': 100});
    expect(await s.pay(session), PurchaseResult.paymentFailed);
    expect(gateway.sessions, isEmpty);
  });

  test('verify gets exactly the SDK success values', () async {
    repo.outcome = 'ACTIVATED';
    PaymentSucceeded? reported;
    final s = service();
    await s.pay(await s.startCheckout(option), onPaid: (p) => reported = p);
    expect(repo.verifyRequests.single.toJson(), {
      'orderId': 'order_1',
      'paymentId': 'pay_1',
      'signature': 'sig',
    });
    expect(reported?.paymentId, 'pay_1');
  });

  test('nothing is re-read before verify says it is granted', () async {
    repo.outcome = 'NOT_PAID';
    expect(await buy(), PurchaseResult.paymentFailed);
    expect(repo.verifyRequests, hasLength(1));
    expect(meReads, 0);
  });

  test('ACTIVATED → activated, /me re-read', () async {
    repo.outcome = 'ACTIVATED';
    expect(await buy(), PurchaseResult.activated);
    expect(meReads, 1);
  });

  test('ALREADY_APPLIED → alreadyApplied, /me re-read', () async {
    repo.outcome = 'ALREADY_APPLIED';
    expect(await buy(), PurchaseResult.alreadyApplied);
    expect(meReads, 1);
  });

  test(
    'AWAITING_CAPTURE says activating, polls /me until it appears',
    () async {
      repo.outcome = 'AWAITING_CAPTURE';
      var reads = 0;
      var activating = 0;
      currentMe = () =>
          ++reads < 3 ? meWith() : meWith(subscriptionId: 'sub_1');
      final s = service();
      final result = await s.pay(
        await s.startCheckout(option),
        onActivating: () => activating++,
      );
      expect(result, PurchaseResult.activated);
      expect(activating, 1);
      expect(reads, 3);
      // Never sent back to the payment sheet.
      expect(gateway.sessions, hasLength(1));
    },
  );

  test(
    'polling is bounded: a fixed number of /me reads, then pending',
    () async {
      repo.outcome = 'AWAITING_CAPTURE';
      final waits = <Duration>[];
      final s = MembershipPurchaseService(
        repository: repo,
        gateway: gateway,
        refreshMe: () async {
          meReads++;
          return meWith();
        },
        wait: (d) async => waits.add(d),
      );
      expect(
        await s.pay(await s.startCheckout(option)),
        PurchaseResult.activationPending,
      );
      // 2 + 4 + 8 + 16 + 32 s: inside the 60 s window, then it stops.
      expect(waits, const [
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 16),
        Duration(seconds: 32),
      ]);
      expect(meReads, 5);
    },
  );

  test('a queued plan counts as active once it shows in `scheduled`', () async {
    repo.outcome = 'PENDING_CONFIRMATION';
    currentMe = () => meWith(scheduledId: 'sub_1');
    expect(await buy(), PurchaseResult.activated);
  });

  test('still not active after the window → activationPending', () async {
    repo.outcome = 'PENDING_CONFIRMATION';
    expect(await buy(), PurchaseResult.activationPending);
    expect(meReads, greaterThan(0));
  });

  test('NOT_PAID → payment failed; the same order can be paid again', () async {
    repo.outcome = 'NOT_PAID';
    final s = service();
    final session = await s.startCheckout(option);
    expect(await s.pay(session), PurchaseResult.paymentFailed);
    repo.outcome = 'ACTIVATED';
    expect(await s.pay(session), PurchaseResult.activated);
    expect(repo.checkoutRequests, hasLength(1), reason: 'one order');
    expect(gateway.sessions.map((x) => x.orderId), ['order_1', 'order_1']);
  });

  test('REFUNDED → refunded, nothing re-read', () async {
    repo.outcome = 'REFUNDED';
    expect(await buy(), PurchaseResult.refunded);
    expect(meReads, 0);
  });

  test('mismatch, not activated, unknown order, unknown → support', () async {
    for (final outcome in [
      'AMOUNT_MISMATCH',
      'PAID_NOT_ACTIVATED',
      'UNKNOWN_ORDER',
      'WHO_KNOWS',
    ]) {
      repo.outcome = outcome;
      expect(await buy(), PurchaseResult.contactSupport, reason: outcome);
    }
  });

  group('verify that cannot be reached', () {
    test('timeout → uncertain (not failed), and nothing granted', () async {
      repo.verifyError = DioException(
        requestOptions: RequestOptions(path: '/membership/checkout/verify'),
        type: DioExceptionType.receiveTimeout,
      );
      expect(await buy(), PurchaseResult.verificationUncertain);
      expect(meReads, 0);
    });

    test('429 and coded 503 → uncertain', () async {
      for (final error in [
        ApiException(429, 'Too many requests'),
        ApiException(503, 'Unavailable', code: 'CHECKOUT_UNAVAILABLE'),
      ]) {
        repo.verifyError = error;
        expect(await buy(), PurchaseResult.verificationUncertain);
      }
    });

    test('400 bad signature → support', () async {
      repo.verifyError = ApiException(400, 'Payment verification failed.');
      expect(await buy(), PurchaseResult.contactSupport);
    });

    test(
      'a retry re-verifies the same values, never re-opening the sheet',
      () async {
        repo.verifyError = DioException(
          requestOptions: RequestOptions(path: '/membership/checkout/verify'),
          type: DioExceptionType.connectionError,
        );
        final s = service();
        final session = await s.startCheckout(option);
        PaymentSucceeded? paid;
        expect(
          await s.pay(session, onPaid: (p) => paid = p),
          PurchaseResult.verificationUncertain,
        );

        repo
          ..verifyError = null
          ..outcome = 'ALREADY_APPLIED';
        expect(await s.confirm(session, paid!), PurchaseResult.alreadyApplied);
        expect(gateway.sessions, hasLength(1));
        expect(repo.verifyRequests, hasLength(2));
        expect(
          repo.verifyRequests.last.toJson(),
          repo.verifyRequests.first.toJson(),
        );
      },
    );
  });

  test('a second pay while one is open opens no second sheet', () async {
    final pending = Completer<PaymentResult>();
    gateway.pending = pending;
    final s = service();
    final session = await s.startCheckout(option);
    final first = s.pay(session);
    await expectLater(s.pay(session), throwsStateError);
    expect(gateway.sessions, hasLength(1));

    pending.complete(const PaymentCancelled());
    expect(await first, PurchaseResult.cancelled);
    // Once closed, the same order can be paid again.
    gateway.pending = null;
    repo.outcome = 'ACTIVATED';
    expect(await s.pay(session), PurchaseResult.activated);
  });
}

class _FakeRepo extends MockMembershipRepository {
  String outcome = 'ACTIVATED';
  Object? checkoutError;
  Object? verifyError;
  final checkoutRequests = <CheckoutRequest>[];
  final verifyRequests = <CheckoutVerifyRequest>[];

  @override
  Future<CheckoutSession> startCheckout(CheckoutRequest request) async {
    checkoutRequests.add(request);
    if (checkoutError case final e?) throw e;
    return CheckoutSession.fromJson({
      'subscriptionId': 'sub_1',
      'orderId': 'order_1',
      'amountInPaise': 379905,
      'currency': 'INR',
      'keyId': 'rzp_test_x',
      'plan': {'code': 'GOLD', 'name': 'Gold'},
      'months': 3,
    });
  }

  @override
  Future<CheckoutVerifyResult> verifyCheckout(
    CheckoutVerifyRequest request,
  ) async {
    verifyRequests.add(request);
    if (verifyError case final e?) throw e;
    return CheckoutVerifyResult.fromJson({
      'outcome': outcome,
      'subscriptionId': 'sub_1',
    });
  }
}

class _FakeGateway implements PaymentGateway {
  bool supported = true;
  Completer<PaymentResult>? pending;
  final sessions = <CheckoutSession>[];
  PaymentResult result = const PaymentSucceeded(
    orderId: 'order_1',
    paymentId: 'pay_1',
    signature: 'sig',
  );

  @override
  bool get isSupported => supported;

  @override
  Future<PaymentResult> pay(CheckoutSession session) async {
    sessions.add(session);
    return pending?.future ?? result;
  }
}
