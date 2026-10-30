import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/core/widgets/buttons/gradient_button.dart';
import 'package:nenjam_matrimony/features/membership/data/repositories/mock_membership_repository.dart';
import 'package:nenjam_matrimony/features/membership/domain/models/checkout_models.dart';
import 'package:nenjam_matrimony/features/membership/domain/models/membership_models.dart';
import 'package:nenjam_matrimony/features/membership/presentation/providers/membership_providers.dart';
import 'package:nenjam_matrimony/features/membership/presentation/purchase/membership_purchase.dart';
import 'package:nenjam_matrimony/features/membership/presentation/widgets/membership_checkout_sheet.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import '../../support/responsive_harness.dart';

/// The order summary: an optional collapsed code box, Continue →
/// `POST /checkout`, the server's breakdown, then Razorpay, then verify.
/// One checkout is one order; nothing here grants a plan.
void main() {
  const option = PurchaseOption(
    planCode: 'GOLD',
    planName: 'Gold',
    months: 3,
    priceInPaise: 399900,
    currency: 'INR',
    kind: PurchaseKind.newPlan,
  );
  final l10n = lookupAppLocalizations(const Locale('en'));

  Map<String, dynamic> sessionJson({
    String orderId = 'order_1',
    int list = 399900,
    int discount = 0,
    int taxRateBps = 0,
    int tax = 0,
    int? amount,
    String? agent,
  }) {
    final total = list - discount + tax;
    return {
      'subscriptionId': 'sub_1',
      'orderId': orderId,
      'amountInPaise': amount ?? total,
      'currency': 'INR',
      'keyId': 'rzp_test_x',
      'plan': {'code': 'GOLD', 'name': 'Gold'},
      'months': 3,
      'pricing': {
        'listAmountPaise': list,
        'discountPaise': discount,
        'discountSource': discount > 0 ? 'REFERRAL_FIRST_PLAN' : 'NONE',
        'taxableAmountPaise': list - discount,
        'taxRateBps': taxRateBps,
        'taxPaise': tax,
        'totalPaise': total,
      },
      'referral': agent == null ? null : {'agentDisplayName': agent},
    };
  }

  group('CheckoutSession pricing', () {
    test('parses the breakdown and the referral agent', () {
      final s = CheckoutSession.fromJson(
        sessionJson(
          discount: 19995,
          taxRateBps: 1800,
          tax: 68383,
          agent: 'Ravi K.',
        ),
      );
      final p = s.pricing!;
      expect(p.listAmountPaise, 399900);
      expect(p.discountPaise, 19995);
      expect(p.hasDiscount, isTrue);
      expect(p.taxRateBps, 1800);
      expect(p.taxPaise, 68383);
      expect(p.hasTax, isTrue);
      expect(p.totalPaise, 448288);
      expect(s.amountInPaise, 448288);
      expect(s.referralAgentName, 'Ravi K.');
      expect(s.isPayable, isTrue);
    });

    test('no pricing object → null, never a guessed one', () {
      final s = CheckoutSession.fromJson(
        Map.of(sessionJson())
          ..remove('pricing')
          ..remove('referral'),
      );
      expect(s.pricing, isNull);
      expect(s.referralAgentName, isNull);
    });
  });

  late _Repo repo;
  late _Gateway gateway;
  String? closedWith;

  Future<void> open(WidgetTester tester, {Locale? locale, Size? size}) async {
    closedWith = null;
    await pumpAtSize(
      tester,
      size ?? const Size(390, 800),
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              closedWith = await showMembershipCheckoutSheet(context, option);
            },
            child: const Text('open'),
          ),
        ),
      ),
      locale: locale ?? const Locale('en'),
      overrides: [
        membershipRepositoryProvider.overrideWithValue(repo),
        paymentGatewayProvider.overrideWithValue(gateway),
      ],
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Finder continueButton() =>
      find.widgetWithText(NmGradientButton, l10n.membershipCheckoutContinue);

  Finder payButton(String amount) =>
      find.widgetWithText(NmGradientButton, l10n.membershipCheckoutPay(amount));

  Future<void> tapContinue(WidgetTester tester) async {
    await tester.tap(continueButton());
    await settle(tester);
  }

  Future<void> typeCode(WidgetTester tester, String code) async {
    if (find.byType(TextField).evaluate().isEmpty) {
      await tester.tap(find.text(l10n.referralCodePrompt));
      await settle(tester);
    }
    await tester.enterText(find.byType(TextField), code);
    await tester.pump();
  }

  setUp(() {
    repo = _Repo();
    gateway = _Gateway();
  });

  group('before checkout', () {
    testWidgets('the code box starts collapsed and nothing is requested', (
      tester,
    ) async {
      await open(tester);
      expect(find.text(l10n.referralCodePrompt), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(continueButton(), findsOneWidget);
      expect(repo.checkoutRequests, isEmpty);
      expect(gateway.sessions, isEmpty);
    });

    testWidgets('Continue with no code → planCode + months only', (
      tester,
    ) async {
      repo.sessions.add(sessionJson());
      await open(tester);
      await tapContinue(tester);
      expect(repo.checkoutRequests.single.toJson(), {
        'planCode': 'GOLD',
        'months': 3,
      });
    });

    testWidgets('an opened but empty box sends no promoCode', (tester) async {
      repo.sessions.add(sessionJson());
      await open(tester);
      await typeCode(tester, '   ');
      await tapContinue(tester);
      expect(
        repo.checkoutRequests.single.toJson().containsKey('promoCode'),
        isFalse,
      );
    });

    testWidgets('a typed code is normalised and sent as promoCode', (
      tester,
    ) async {
      repo.sessions.add(sessionJson(discount: 19995, agent: 'Ravi K.'));
      await open(tester);
      await typeCode(tester, 'nm7k-2p9x');
      await tapContinue(tester);
      expect(repo.checkoutRequests.single.toJson(), {
        'planCode': 'GOLD',
        'months': 3,
        'promoCode': 'NM7K2P9X',
      });
      expect(find.text(l10n.membershipPromoCodeApplied('NM7K2P9X')), findsOne);
      expect(payButton('₹3,799.05'), findsOneWidget);
    });

    testWidgets('a malformed code is refused locally, never sent', (
      tester,
    ) async {
      await open(tester);
      await typeCode(tester, 'HELLO');
      await tapContinue(tester);
      expect(find.text(l10n.referralCodeInvalid), findsOneWidget);
      expect(repo.checkoutRequests, isEmpty);
    });
  });

  group('pricing', () {
    testWidgets('plain price: plan price and total, no discount, no GST', (
      tester,
    ) async {
      repo.sessions.add(sessionJson());
      await open(tester);
      await tapContinue(tester);

      expect(find.text(l10n.membershipCheckoutPlanPrice), findsOneWidget);
      expect(find.text(l10n.membershipCheckoutTotal), findsOneWidget);
      expect(find.text('₹3,999'), findsNWidgets(2));
      expect(find.text(l10n.membershipCheckoutReferralDiscount), findsNothing);
      expect(find.textContaining('GST'), findsNothing);
      expect(payButton('₹3,999'), findsOneWidget);
      // Shown before Razorpay is ever opened.
      expect(gateway.sessions, isEmpty);
    });

    testWidgets('signup referral: discount, agent and GST without a code', (
      tester,
    ) async {
      repo.sessions.add(
        sessionJson(
          discount: 19995,
          taxRateBps: 1800,
          tax: 68383,
          agent: 'Ravi K.',
        ),
      );
      await open(tester);
      await tapContinue(tester);

      expect(
        find.text(l10n.membershipCheckoutReferralDiscount),
        findsOneWidget,
      );
      expect(find.text('−₹199.95'), findsOneWidget);
      expect(find.text(l10n.referralCodeReferredBy('Ravi K.')), findsOneWidget);
      // No discount percentage is in the response, so none is shown.
      expect(find.textContaining('% off'), findsNothing);
      expect(find.text(l10n.membershipCheckoutGst('18')), findsOneWidget);
      expect(find.text('₹683.83'), findsOneWidget);
      expect(payButton('₹4,482.88'), findsOneWidget);
      // The discount already applies: no code box.
      expect(find.text(l10n.referralCodePrompt), findsNothing);
    });

    testWidgets('the payable figure is amountInPaise, not a client sum', (
      tester,
    ) async {
      repo.sessions.add(sessionJson(amount: 100000));
      await open(tester);
      await tapContinue(tester);
      expect(payButton('₹1,000'), findsOneWidget);
    });

    testWidgets('a changed code needs a new checkout before Pay', (
      tester,
    ) async {
      repo.sessions
        ..add(sessionJson())
        ..add(sessionJson(orderId: 'order_2', discount: 19995));
      await open(tester);
      await tapContinue(tester);
      expect(payButton('₹3,999'), findsOneWidget);

      await typeCode(tester, 'NM7K2P9X');
      // The old order is no longer offered.
      expect(payButton('₹3,999'), findsNothing);
      expect(continueButton(), findsOneWidget);

      await tapContinue(tester);
      await tester.tap(payButton('₹3,799.05'));
      await settle(tester);
      expect(gateway.sessions.single.orderId, 'order_2');
    });

    testWidgets('a second Continue while one is in flight sends nothing', (
      tester,
    ) async {
      final pending = Completer<CheckoutSession>();
      repo.pendingCheckout = pending;
      await open(tester);
      await tester.tap(continueButton());
      await tester.pump();
      await tester.tap(find.byType(NmGradientButton), warnIfMissed: false);
      await tester.pump();
      expect(repo.checkoutRequests, hasLength(1));
      pending.complete(CheckoutSession.fromJson(sessionJson()));
      await settle(tester);
      expect(payButton('₹3,999'), findsOneWidget);
    });
  });

  group('referral code refused', () {
    final reasons = <String, String>{
      'INVALID': l10n.membershipPromoInvalid,
      'NOT_FIRST_PLAN': l10n.membershipPromoNotFirstPlan,
      'ALREADY_ATTRIBUTED': l10n.membershipPromoAlreadyAttributed,
      'SELF_REFERRAL': l10n.membershipPromoSelfReferral,
      'AGENT_PAUSED': l10n.membershipPromoAgentPaused,
      'PHONE_NOT_VERIFIED': l10n.membershipPromoPhoneNotVerified,
    };
    for (final MapEntry(key: reason, value: message) in reasons.entries) {
      testWidgets('PROMO_CODE_REJECTED $reason → its own message', (
        tester,
      ) async {
        repo.promoError = PromoCodeRejectedException(
          'server text',
          reason: reason,
        );
        await open(tester);
        await typeCode(tester, 'NM7K2P9X');
        await tapContinue(tester);
        expect(find.text(message), findsOneWidget);
        expect(find.text('server text'), findsNothing);
      });
    }

    testWidgets('an unknown reason shows the server sentence', (tester) async {
      repo.promoError = PromoCodeRejectedException(
        'That code can’t be used for this purchase.',
        reason: 'SOMETHING_NEW',
      );
      await open(tester);
      await typeCode(tester, 'NM7K2P9X');
      await tapContinue(tester);
      expect(
        find.text('That code can’t be used for this purchase.'),
        findsOneWidget,
      );
    });

    testWidgets('code kept, box open, earlier price kept, no Pay with it', (
      tester,
    ) async {
      repo.sessions.add(sessionJson());
      repo.promoError = PromoCodeRejectedException('x', reason: 'INVALID');
      await open(tester);
      await tapContinue(tester);
      await typeCode(tester, 'NM7K2P9X');
      await tapContinue(tester);

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'NM7K2P9X',
      );
      // The earlier (code-free) breakdown is still on screen …
      expect(find.text(l10n.membershipCheckoutTotal), findsOneWidget);
      // … but it is not offered for this code, and resubmitting the same
      // refused code is off.
      expect(payButton('₹3,999'), findsNothing);
      final cont = tester.widget<NmGradientButton>(continueButton());
      expect(cont.onPressed, isNull);
      expect(gateway.sessions, isEmpty);
    });

    testWidgets('Remove → pay without the code, on the code-free order', (
      tester,
    ) async {
      repo.sessions.add(sessionJson());
      repo.promoError = PromoCodeRejectedException('x', reason: 'INVALID');
      await open(tester);
      await tapContinue(tester);
      await typeCode(tester, 'NM7K2P9X');
      await tapContinue(tester);

      await tester.tap(find.text(l10n.referralCodeRemove));
      await settle(tester);
      expect(payButton('₹3,999'), findsOneWidget);
      await tester.tap(payButton('₹3,999'));
      await settle(tester);
      expect(gateway.sessions.single.orderId, 'order_1');
      expect(repo.checkoutRequests, hasLength(2));
    });

    testWidgets('rejected before any price: Remove allows a plain checkout', (
      tester,
    ) async {
      repo.promoError = PromoCodeRejectedException('x', reason: 'INVALID');
      repo.sessions.add(sessionJson());
      await open(tester);
      await typeCode(tester, 'NM7K2P9X');
      await tapContinue(tester);
      expect(find.text(l10n.membershipPromoInvalid), findsOneWidget);

      await tester.tap(find.text(l10n.referralCodeRemove));
      await settle(tester);
      await tapContinue(tester);
      expect(repo.checkoutRequests.last.toJson(), {
        'planCode': 'GOLD',
        'months': 3,
      });
      expect(payButton('₹3,999'), findsOneWidget);
    });

    testWidgets('PROMO_CODES_UNAVAILABLE: "can\'t be used yet", no retry', (
      tester,
    ) async {
      repo.promoError = ApiException(
        422,
        'server text',
        code: 'PROMO_CODES_UNAVAILABLE',
      );
      await open(tester);
      await typeCode(tester, 'NM7K2P9X');
      await tapContinue(tester);

      expect(find.text(l10n.membershipPromoCodesUnavailable), findsOneWidget);
      expect(
        l10n.membershipPromoCodesUnavailable,
        "Referral codes can't be used yet.",
      );
      // No silent retry without the code.
      expect(repo.checkoutRequests, hasLength(1));
    });
  });

  group('payment', () {
    testWidgets('Pay → Razorpay → verify → closes once activated', (
      tester,
    ) async {
      repo.sessions.add(sessionJson());
      final sheet = Completer<PaymentResult>();
      gateway.pending = sheet;
      await open(tester);
      await tapContinue(tester);

      await tester.tap(payButton('₹3,999'));
      await tester.pump();
      // A second tap while Razorpay is open starts nothing.
      await tester.tap(find.byType(NmGradientButton), warnIfMissed: false);
      await tester.pump();
      expect(gateway.sessions, hasLength(1));
      // Nothing is verified, or granted, before Razorpay reports success.
      expect(repo.verifyRequests, isEmpty);
      expect(repo.meReads, 0);

      sheet.complete(
        const PaymentSucceeded(
          orderId: 'order_1',
          paymentId: 'pay_1',
          signature: 'sig',
        ),
      );
      await settle(tester);

      expect(repo.verifyRequests.single.toJson(), {
        'orderId': 'order_1',
        'paymentId': 'pay_1',
        'signature': 'sig',
      });
      expect(closedWith, l10n.membershipPurchaseActivated);
      expect(find.byType(MembershipCheckoutSheet), findsNothing);
    });

    testWidgets('closed or failed: same order reopened, no new checkout', (
      tester,
    ) async {
      repo.sessions.add(sessionJson());
      gateway.results.addAll(const [PaymentCancelled(), PaymentFailed()]);
      await open(tester);
      await tapContinue(tester);

      await tester.tap(payButton('₹3,999'));
      await settle(tester);
      expect(find.text(l10n.membershipPurchaseCancelled), findsOneWidget);
      await tester.tap(payButton('₹3,999'));
      await settle(tester);
      expect(find.text(l10n.membershipPurchaseFailed), findsOneWidget);

      expect(gateway.sessions.map((s) => s.orderId), ['order_1', 'order_1']);
      expect(repo.checkoutRequests, hasLength(1));
      expect(repo.verifyRequests, isEmpty);
      final pay = tester.widget<NmGradientButton>(payButton('₹3,999'));
      expect(pay.onPressed, isNotNull);
    });

    testWidgets('NOT_PAID: stays open to pay the same order again', (
      tester,
    ) async {
      repo.sessions.add(sessionJson());
      repo.outcomes.add('NOT_PAID');
      await open(tester);
      await tapContinue(tester);
      await tester.tap(payButton('₹3,999'));
      await settle(tester);
      expect(find.text(l10n.membershipPurchaseFailed), findsOneWidget);
      expect(find.byType(MembershipCheckoutSheet), findsOneWidget);
      expect(repo.checkoutRequests, hasLength(1));
    });

    final closing = <String, String Function()>{
      'ALREADY_APPLIED': () => l10n.membershipPurchaseAlreadyApplied,
      'REFUNDED': () => l10n.membershipPurchaseRefunded,
      'AMOUNT_MISMATCH': () => l10n.membershipPurchaseContactSupport,
      'PAID_NOT_ACTIVATED': () => l10n.membershipPurchaseContactSupport,
    };
    for (final MapEntry(key: outcome, value: message) in closing.entries) {
      testWidgets('$outcome closes with its own message', (tester) async {
        repo.sessions.add(sessionJson());
        repo.outcomes.add(outcome);
        await open(tester);
        await tapContinue(tester);
        await tester.tap(payButton('₹3,999'));
        await settle(tester);
        expect(closedWith, message());
      });
    }

    testWidgets('AWAITING_CAPTURE: "activating" while /me is polled', (
      tester,
    ) async {
      repo.sessions.add(sessionJson());
      repo.outcomes.add('AWAITING_CAPTURE');
      final me = Completer<MyMembership>();
      repo.pendingMe = me;
      await open(tester);
      await tapContinue(tester);
      await tester.tap(payButton('₹3,999'));
      // The service waits 2 s before the first /me read.
      await tester.pump(const Duration(seconds: 3));

      expect(find.text(l10n.membershipCheckoutActivating), findsOneWidget);
      expect(
        l10n.membershipCheckoutActivating,
        startsWith('Payment received, activating your plan'),
      );
      expect(
        gateway.sessions,
        hasLength(1),
        reason: 'never asked to pay again',
      );

      me.complete(
        MyMembership.fromJson(const {
          'source': 'SUBSCRIPTION',
          'subscription': {'id': 'sub_1', 'planCode': 'GOLD'},
        }),
      );
      await settle(tester);
      expect(closedWith, l10n.membershipPurchaseActivated);
    });

    testWidgets('verify unreachable: no Pay, Check again re-verifies', (
      tester,
    ) async {
      repo.sessions.add(sessionJson());
      repo.verifyErrors.add(
        ApiException(503, 'x', code: 'CHECKOUT_UNAVAILABLE'),
      );
      await open(tester);
      await tapContinue(tester);

      await tester.tap(payButton('₹3,999'));
      await settle(tester);
      expect(find.text(l10n.membershipVerificationUncertain), findsOneWidget);
      expect(payButton('₹3,999'), findsNothing);
      expect(find.text(l10n.membershipPurchaseFailed), findsNothing);

      await tester.tap(find.text(l10n.membershipCheckAgain));
      await settle(tester);
      expect(gateway.sessions, hasLength(1), reason: 'never charged twice');
      expect(repo.verifyRequests, hasLength(2));
      expect(
        repo.verifyRequests.last.toJson(),
        repo.verifyRequests.first.toJson(),
      );
      expect(closedWith, l10n.membershipPurchaseActivated);
    });
  });

  group('checkout unavailable', () {
    testWidgets('CHECKOUT_UNAVAILABLE: try again shortly, deliberate retry', (
      tester,
    ) async {
      repo.checkoutErrors.add(
        ApiException(503, 'x', code: 'CHECKOUT_UNAVAILABLE'),
      );
      repo.sessions.add(sessionJson());
      await open(tester);
      await tapContinue(tester);

      expect(find.text(l10n.membershipCheckoutUnavailable), findsOneWidget);
      expect(
        l10n.membershipCheckoutUnavailable,
        contains('Try again shortly.'),
      );
      expect(repo.checkoutRequests, hasLength(1), reason: 'no auto-retry');
      expect(find.textContaining('Pay '), findsNothing);

      await tester.tap(find.text(l10n.commonRetry));
      await settle(tester);
      expect(repo.checkoutRequests, hasLength(2));
      expect(payButton('₹3,999'), findsOneWidget);
    });

    testWidgets('400 not on sale: the server sentence', (tester) async {
      repo.checkoutErrors.add(
        ApiException(400, 'Gold is not available for 3 months.'),
      );
      await open(tester);
      await tapContinue(tester);
      expect(find.text('Gold is not available for 3 months.'), findsOneWidget);
    });
  });

  for (final locale in const [Locale('en'), Locale('ta')]) {
    testWidgets('fits at 320dp with every row ($locale)', (tester) async {
      repo.sessions.add(
        sessionJson(
          discount: 19995,
          taxRateBps: 1800,
          tax: 68383,
          agent: 'Ravi K.',
        ),
      );
      await open(tester, locale: locale, size: const Size(320, 640));
      await tester.tap(find.byType(NmGradientButton));
      await settle(tester);
      expectNoOverflowIn(drainExceptions(tester));
      expect(find.byType(MembershipCheckoutSheet), findsOneWidget);
    });
  }
}

/// Pumps past the sheet's open animation and the async steps, without
/// pumpAndSettle (a spinner would keep it from ever settling).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

class _Repo extends MockMembershipRepository {
  final sessions = <Map<String, dynamic>>[];
  final checkoutErrors = <Object>[];
  final verifyErrors = <Object>[];
  final outcomes = <String>[];
  final checkoutRequests = <CheckoutRequest>[];
  final verifyRequests = <CheckoutVerifyRequest>[];
  Completer<CheckoutSession>? pendingCheckout;
  Completer<MyMembership>? pendingMe;
  int meReads = 0;

  /// Thrown for a checkout that carries a promoCode.
  Object? promoError;

  @override
  Future<CheckoutSession> startCheckout(CheckoutRequest request) async {
    checkoutRequests.add(request);
    if (pendingCheckout case final c?) return c.future;
    if (request.promoCode != null && promoError != null) throw promoError!;
    if (checkoutErrors.isNotEmpty) throw checkoutErrors.removeAt(0);
    return CheckoutSession.fromJson(sessions.removeAt(0));
  }

  @override
  Future<CheckoutVerifyResult> verifyCheckout(
    CheckoutVerifyRequest request,
  ) async {
    verifyRequests.add(request);
    if (verifyErrors.isNotEmpty) throw verifyErrors.removeAt(0);
    return CheckoutVerifyResult.fromJson({
      'outcome': outcomes.isNotEmpty ? outcomes.removeAt(0) : 'ACTIVATED',
      'subscriptionId': 'sub_1',
    });
  }

  @override
  Future<MyMembership> getMe() {
    meReads++;
    return pendingMe?.future ?? super.getMe();
  }
}

class _Gateway implements PaymentGateway {
  Completer<PaymentResult>? pending;
  final results = <PaymentResult>[];
  final sessions = <CheckoutSession>[];

  @override
  bool get isSupported => true;

  @override
  Future<PaymentResult> pay(CheckoutSession session) async {
    sessions.add(session);
    if (pending case final p?) return p.future;
    if (results.isNotEmpty) return results.removeAt(0);
    return const PaymentSucceeded(
      orderId: 'order_1',
      paymentId: 'pay_1',
      signature: 'sig',
    );
  }
}
