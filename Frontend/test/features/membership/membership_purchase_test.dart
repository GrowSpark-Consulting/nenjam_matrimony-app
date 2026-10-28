import 'package:flutter_test/flutter_test.dart';
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

  test(
    'no payment provider → unavailable, and no checkout is started',
    () async {
      gateway.supported = false;
      expect(await service().purchase(option), PurchaseResult.unavailable);
      expect(repo.checkoutRequests, isEmpty);
    },
  );

  test('sends exactly planCode + months to checkout', () async {
    repo.outcome = 'ACTIVATED';
    await service().purchase(option);
    expect(repo.checkoutRequests.single.toJson(), {
      'planCode': 'GOLD',
      'months': 3,
    });
  });

  test('cancelled or failed sheet → no verify call', () async {
    gateway.result = const PaymentCancelled();
    expect(await service().purchase(option), PurchaseResult.cancelled);
    gateway.result = const PaymentFailed();
    expect(await service().purchase(option), PurchaseResult.paymentFailed);
    expect(repo.verifyRequests, isEmpty);
    expect(meReads, 0);
  });

  test('verify gets exactly the SDK success values', () async {
    repo.outcome = 'ACTIVATED';
    await service().purchase(option);
    expect(repo.verifyRequests.single.toJson(), {
      'orderId': 'order_1',
      'paymentId': 'pay_1',
      'signature': 'sig',
    });
  });

  test('ACTIVATED / ALREADY_APPLIED → activated, /me re-read', () async {
    for (final outcome in ['ACTIVATED', 'ALREADY_APPLIED']) {
      repo.outcome = outcome;
      meReads = 0;
      expect(await service().purchase(option), PurchaseResult.activated);
      expect(meReads, 1, reason: outcome);
    }
  });

  test('AWAITING_CAPTURE polls /me until the subscription appears', () async {
    repo.outcome = 'AWAITING_CAPTURE';
    var reads = 0;
    currentMe = () => ++reads < 3 ? meWith() : meWith(subscriptionId: 'sub_1');
    expect(await service().purchase(option), PurchaseResult.activated);
    expect(reads, 3);
  });

  test('a queued plan counts as active once it shows in `scheduled`', () async {
    repo.outcome = 'PENDING_CONFIRMATION';
    currentMe = () => meWith(scheduledId: 'sub_1');
    expect(await service().purchase(option), PurchaseResult.activated);
  });

  test('still not active after the window → activationPending', () async {
    repo.outcome = 'PENDING_CONFIRMATION';
    expect(await service().purchase(option), PurchaseResult.activationPending);
    expect(meReads, greaterThan(0));
  });

  test('NOT_PAID / REFUNDED → payment failed', () async {
    for (final outcome in ['NOT_PAID', 'REFUNDED']) {
      repo.outcome = outcome;
      expect(await service().purchase(option), PurchaseResult.paymentFailed);
    }
  });

  test('mismatch, not activated, unknown order, unknown → support', () async {
    for (final outcome in [
      'AMOUNT_MISMATCH',
      'PAID_NOT_ACTIVATED',
      'UNKNOWN_ORDER',
      'WHO_KNOWS',
    ]) {
      repo.outcome = outcome;
      expect(
        await service().purchase(option),
        PurchaseResult.contactSupport,
        reason: outcome,
      );
    }
  });

  test('the default gateway hides purchasing', () {
    expect(const UnsupportedPaymentGateway().isSupported, isFalse);
  });
}

class _FakeRepo extends MockMembershipRepository {
  String outcome = 'ACTIVATED';
  final checkoutRequests = <CheckoutRequest>[];
  final verifyRequests = <CheckoutVerifyRequest>[];

  @override
  Future<CheckoutSession> startCheckout(CheckoutRequest request) async {
    checkoutRequests.add(request);
    return CheckoutSession.fromJson({
      'subscriptionId': 'sub_1',
      'orderId': 'order_1',
      'amountInPaise': 399900,
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
    return CheckoutVerifyResult.fromJson({
      'outcome': outcome,
      'subscriptionId': 'sub_1',
    });
  }
}

class _FakeGateway implements PaymentGateway {
  bool supported = true;
  PaymentResult result = const PaymentSucceeded(
    orderId: 'order_1',
    paymentId: 'pay_1',
    signature: 'sig',
  );

  @override
  bool get isSupported => supported;

  @override
  Future<PaymentResult> pay(CheckoutSession session) async => result;
}
