import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/membership/data/repositories/mock_membership_repository.dart';
import 'package:nenjam_matrimony/features/membership/domain/models/checkout_models.dart';
import 'package:nenjam_matrimony/features/membership/domain/models/membership_models.dart';

/// `fromJson` for every membership response, using the contract's examples
/// (docs/membership/api-contract.md) and the edge cases it calls out.
void main() {
  group('MembershipCatalog', () {
    test('today: empty durations and checkout off → nothing purchasable', () {
      final c = MembershipCatalog.fromJson(MockMembershipRepository.plansJson);
      expect(c.checkoutAvailable, isFalse);
      expect(c.plans.map((p) => p.code), ['FREE', 'GOLD', 'PLATINUM']);
      expect(c.plans.every((p) => p.durations.isEmpty), isTrue);
      expect(c.hasPurchasablePlans, isFalse);
      expect(c.features.map((f) => f.kind), [
        MembershipFeatureKind.quota,
        MembershipFeatureKind.level,
        MembershipFeatureKind.boolean,
      ]);
      expect(c.features.last.requiredOnEveryPlan, isTrue);
    });

    test('purchasable only with checkout on AND a priced paid length', () {
      MembershipCatalog with_({required bool checkout, Object? price}) =>
          MembershipCatalog.fromJson({
            'checkoutAvailable': checkout,
            'plans': [
              {
                'code': 'GOLD',
                'name': 'Gold',
                'tier': 1,
                'isFree': false,
                'durations': [
                  {'months': 3, 'durationDays': 90, 'priceInPaise': price},
                ],
              },
            ],
          });
      expect(with_(checkout: true, price: 399900).hasPurchasablePlans, isTrue);
      expect(
        with_(checkout: false, price: 399900).hasPurchasablePlans,
        isFalse,
      );
      expect(with_(checkout: true, price: null).hasPurchasablePlans, isFalse);
    });

    test('tolerates unknown kinds, missing fields and junk entries', () {
      final c = MembershipCatalog.fromJson({
        'plans': [
          'junk',
          {'code': 'X', 'tier': 'nope'},
        ],
        'features': [
          {'key': 'new.thing', 'kind': 'meter'},
        ],
      });
      expect(c.checkoutAvailable, isFalse);
      expect(c.plans.single.tier, 0);
      expect(c.features.single.kind, MembershipFeatureKind.unknown);
      expect(c.features.single.label, 'new.thing');
    });
  });

  group('EntitlementValue', () {
    test('parses the three contract shapes', () {
      expect(EntitlementValue.parse(true)!.included, isTrue);
      expect(EntitlementValue.parse('PRIORITY')!.level, 'PRIORITY');
      expect(EntitlementValue.parse({'limit': 5})!.limit, 5);
      expect(EntitlementValue.parse({'limit': null})!.unlimited, isTrue);
      expect(
        EntitlementValue.parse({'limit': 60, 'perMonths': 3})!.perMonths,
        3,
      );
    });

    test('an unknown shape is null, not a guess', () {
      expect(EntitlementValue.parse(null), isNull);
      expect(EntitlementValue.parse(42), isNull);
      expect(EntitlementValue.parse({'max': 5}), isNull);
      expect(EntitlementValue.parse({'limit': 'five'}), isNull);
    });
  });

  group('MyMembership', () {
    test('Free member today: photo cap 6, others uncapped, shadow mode', () {
      final me = MyMembership.fromJson(MockMembershipRepository.freeMeJson);
      expect(me.source, MembershipSource.free);
      expect(me.subscription, isNull);
      expect(me.effectiveCaps['profile.photos'], 6);
      expect(me.effectiveCaps.containsKey('shortlist.profiles'), isTrue);
      expect(me.effectiveCaps['shortlist.profiles'], isNull);
      expect(me.limitsEnforced, isFalse);
      expect(me.checkoutAvailable, isFalse);
      expect(me.mayShowUpgradePrompts, isTrue);
    });

    test('the contract example: subscription, queue, usage, options', () {
      final me = MyMembership.fromJson({
        'plan': {'code': 'GOLD', 'name': 'Gold', 'tier': 1},
        'source': 'SUBSCRIPTION',
        'planVersion': 1,
        'subscription': {
          'id': 's1',
          'planCode': 'GOLD',
          'status': 'ACTIVE',
          'startDate': '2026-10-27T06:00:00.000Z',
          'endDate': '2027-01-25T06:00:00.000Z',
          'months': 3,
        },
        'scheduled': [
          {'id': 's2', 'planCode': 'GOLD', 'planName': 'Gold'},
        ],
        'usage': [
          {
            'feature': 'interests.send',
            'period': 'MONTH',
            'used': 3,
            'limit': 100,
            'remaining': 97,
            'fairUse': false,
            'resetsAt': '2026-10-31T18:30:00.000Z',
          },
        ],
        'purchaseOptions': [
          {
            'planCode': 'PLATINUM',
            'planName': 'Platinum',
            'months': 3,
            'priceInPaise': 799900,
            'currency': 'INR',
            'kind': 'UPGRADE',
          },
          {'planCode': 'GOLD', 'months': 3, 'kind': 'RENEWAL'},
        ],
        'effectiveCaps': {'profile.photos': 15},
        'checkoutAvailable': true,
        'limitsEnforced': true,
      });
      expect(me.hasPaidPlan, isTrue);
      expect(me.subscription!.endDate, DateTime.utc(2027, 1, 25, 6).toLocal());
      expect(me.scheduled.single.id, 's2');
      expect(me.usage.single.remaining, 97);
      expect(me.purchaseOptions.first.kind, PurchaseKind.upgrade);
      expect(me.purchaseOptions.first.isQueued, isFalse);
      expect(me.purchaseOptions.last.isQueued, isTrue);
      expect(me.effectiveCaps['profile.photos'], 15);
    });

    test('LEGACY and UNAVAILABLE: no entitlements, no upgrade prompts', () {
      for (final source in ['LEGACY', 'UNAVAILABLE']) {
        final me = MyMembership.fromJson({
          'plan': {'code': 'GOLD', 'name': 'Gold'},
          'source': source,
          'entitlements': null,
        });
        expect(me.entitlements, isNull, reason: source);
        expect(me.mayShowUpgradePrompts, isFalse, reason: source);
      }
      expect(
        MyMembership.fromJson({'source': 'SOMETHING_NEW'}).source,
        MembershipSource.unknown,
      );
    });

    test('drops unusable cap values instead of guessing', () {
      final me = MyMembership.fromJson({
        'effectiveCaps': {'profile.photos': -1, 'a': 'x', 'b': 4.0},
      });
      expect(me.effectiveCaps.containsKey('profile.photos'), isFalse);
      expect(me.effectiveCaps.containsKey('a'), isFalse);
      expect(me.effectiveCaps['b'], 4);
    });
  });

  test('history item from the contract example', () {
    final item = MembershipHistoryItem.fromJson({
      'id': 'h1',
      'plan': {'code': 'GOLD', 'name': 'Gold'},
      'months': 3,
      'status': 'CANCELLED',
      'cancellationReason': 'REFUNDED',
      'source': 'PURCHASE',
      'priceInPaise': 399900,
      'currency': 'INR',
      'payments': [
        {
          'id': 'p1',
          'orderId': 'order_1',
          'paymentId': 'pay_1',
          'amountInPaise': 399900,
          'currency': 'INR',
          'status': 'SUCCESS',
          'refundedAmount': 0,
        },
      ],
    });
    expect(item.plan.name, 'Gold');
    expect(item.cancellationReason, 'REFUNDED');
    expect(item.payments.single.refundedAmount, 0);
  });

  group('checkout', () {
    test('the request carries only planCode and months', () {
      expect(const CheckoutRequest(planCode: 'GOLD', months: 3).toJson(), {
        'planCode': 'GOLD',
        'months': 3,
      });
    });

    test('verify outcomes map, unknown ones are "not granted"', () {
      VerifyOutcome o(String s) =>
          CheckoutVerifyResult.fromJson({'outcome': s}).outcome;
      expect(o('ACTIVATED'), VerifyOutcome.activated);
      expect(o('ALREADY_APPLIED'), VerifyOutcome.alreadyApplied);
      expect(o('AWAITING_CAPTURE'), VerifyOutcome.awaitingCapture);
      expect(o('PENDING_CONFIRMATION'), VerifyOutcome.pendingConfirmation);
      expect(o('NOT_PAID'), VerifyOutcome.notPaid);
      expect(o('REFUNDED'), VerifyOutcome.refunded);
      expect(o('AMOUNT_MISMATCH'), VerifyOutcome.amountMismatch);
      expect(o('PAID_NOT_ACTIVATED'), VerifyOutcome.paidNotActivated);
      expect(o('UNKNOWN_ORDER'), VerifyOutcome.unknownOrder);
      expect(o('SOMETHING_ELSE'), VerifyOutcome.unknown);
    });
  });
}
