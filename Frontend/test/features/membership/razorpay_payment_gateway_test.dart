import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/membership/domain/models/checkout_models.dart';
import 'package:nenjam_matrimony/features/membership/presentation/purchase/membership_purchase.dart';
import 'package:nenjam_matrimony/features/membership/presentation/purchase/razorpay_payment_gateway.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

/// The gateway over the native SDK, driven through a fake `Razorpay`. The
/// real Checkout UI can't run in a unit test; this covers what the app hands
/// it and how its callbacks are turned into a [PaymentResult].
void main() {
  final session = CheckoutSession.fromJson(const {
    'subscriptionId': 'sub_1',
    'orderId': 'order_1',
    'amountInPaise': 379905,
    'currency': 'INR',
    'keyId': 'rzp_test_abc',
    'plan': {'code': 'GOLD', 'name': 'Gold'},
    'months': 3,
  });

  late _FakeRazorpay sdk;
  late int created;
  late RazorpayPaymentGateway gateway;

  setUp(() {
    sdk = _FakeRazorpay();
    created = 0;
    gateway = RazorpayPaymentGateway(
      createSdk: () {
        created++;
        return sdk;
      },
    );
  });

  test('maps the checkout response onto the SDK options', () {
    expect(RazorpayPaymentGateway.optionsFor(session), {
      'key': 'rzp_test_abc',
      'order_id': 'order_1',
      'amount': 379905,
      'currency': 'INR',
      'name': 'Nenjam Matrimony',
      'description': 'Gold',
    });
  });

  test('is supported, and touches no SDK until a payment starts', () {
    expect(gateway.isSupported, isTrue);
    expect(created, 0);
  });

  test('success → the three values verify needs', () async {
    final result = gateway.pay(session);
    expect(sdk.opened.single['order_id'], 'order_1');
    sdk.emit(
      Razorpay.EVENT_PAYMENT_SUCCESS,
      PaymentSuccessResponse('pay_1', 'order_1', 'sig_1', null),
    );
    final paid = await result;
    expect(paid, isA<PaymentSucceeded>());
    paid as PaymentSucceeded;
    expect(
      [paid.orderId, paid.paymentId, paid.signature],
      ['order_1', 'pay_1', 'sig_1'],
    );
  });

  test('a success missing the signature is unconfirmed', () async {
    final result = gateway.pay(session);
    sdk.emit(
      Razorpay.EVENT_PAYMENT_SUCCESS,
      PaymentSuccessResponse('pay_1', 'order_1', null, null),
    );
    expect(await result, isA<PaymentUnconfirmed>());
  });

  test('closing the sheet is a cancellation', () async {
    final result = gateway.pay(session);
    sdk.emit(
      Razorpay.EVENT_PAYMENT_ERROR,
      PaymentFailureResponse(Razorpay.PAYMENT_CANCELLED, 'cancelled', null),
    );
    expect(await result, isA<PaymentCancelled>());
  });

  test('any other error is a failure', () async {
    for (final code in [
      Razorpay.NETWORK_ERROR,
      Razorpay.INVALID_OPTIONS,
      Razorpay.UNKNOWN_ERROR,
    ]) {
      final result = gateway.pay(session);
      sdk.emit(
        Razorpay.EVENT_PAYMENT_ERROR,
        PaymentFailureResponse(code, 'x', null),
      );
      expect(await result, isA<PaymentFailed>(), reason: '$code');
    }
  });

  test('a duplicate callback is ignored; one result per payment', () async {
    final result = gateway.pay(session);
    sdk
      ..emit(
        Razorpay.EVENT_PAYMENT_SUCCESS,
        PaymentSuccessResponse('pay_1', 'order_1', 'sig_1', null),
      )
      ..emit(
        Razorpay.EVENT_PAYMENT_ERROR,
        PaymentFailureResponse(Razorpay.NETWORK_ERROR, 'late', null),
      );
    expect(await result, isA<PaymentSucceeded>());
  });

  test('a success for another order does not settle this one', () async {
    final result = gateway.pay(session);
    sdk.emit(
      Razorpay.EVENT_PAYMENT_SUCCESS,
      PaymentSuccessResponse('pay_old', 'order_old', 'sig_old', null),
    );
    sdk.emit(
      Razorpay.EVENT_PAYMENT_SUCCESS,
      PaymentSuccessResponse('pay_1', 'order_1', 'sig_1', null),
    );
    expect(((await result) as PaymentSucceeded).paymentId, 'pay_1');
  });

  test('a callback with no payment in progress is dropped', () async {
    // Like a result the SDK re-delivers late: it arrives between payments.
    final first = gateway.pay(session);
    sdk.emit(
      Razorpay.EVENT_PAYMENT_ERROR,
      PaymentFailureResponse(Razorpay.PAYMENT_CANCELLED, 'x', null),
    );
    await first;
    sdk.emit(
      Razorpay.EVENT_PAYMENT_SUCCESS,
      PaymentSuccessResponse('pay_1', 'order_1', 'sig_1', null),
    );
    // Nothing is pending, so nothing completes or throws.
    final second = gateway.pay(session);
    sdk.emit(
      Razorpay.EVENT_PAYMENT_ERROR,
      PaymentFailureResponse(Razorpay.PAYMENT_CANCELLED, 'x', null),
    );
    expect(await second, isA<PaymentCancelled>());
  });

  test('one SDK instance, listeners registered once', () async {
    for (var i = 0; i < 2; i++) {
      final result = gateway.pay(session);
      sdk.emit(
        Razorpay.EVENT_PAYMENT_ERROR,
        PaymentFailureResponse(Razorpay.PAYMENT_CANCELLED, 'x', null),
      );
      await result;
    }
    expect(created, 1);
    expect(sdk.registrations[Razorpay.EVENT_PAYMENT_SUCCESS], 1);
  });

  test('a second payment while one is open is refused', () async {
    final first = gateway.pay(session);
    await expectLater(gateway.pay(session), throwsStateError);
    expect(sdk.opened, hasLength(1));
    sdk.emit(
      Razorpay.EVENT_PAYMENT_ERROR,
      PaymentFailureResponse(Razorpay.PAYMENT_CANCELLED, 'x', null),
    );
    await first;
  });

  test('an SDK that fails to open is a failed payment, not a hang', () async {
    sdk.openError = StateError('MissingPluginException');
    expect(await gateway.pay(session), isA<PaymentFailed>());
  });

  test('dispose releases the SDK and settles an open payment', () async {
    final result = gateway.pay(session);
    gateway.dispose();
    expect(sdk.cleared, isTrue);
    expect(await result, isA<PaymentCancelled>());
  });
}

class _FakeRazorpay implements Razorpay {
  final opened = <Map<String, dynamic>>[];
  final registrations = <String, int>{};
  final _handlers = <String, List<Function>>{};
  Object? openError;
  bool cleared = false;

  void emit(String event, Object payload) {
    for (final h in [...?_handlers[event]]) {
      // ignore: avoid_dynamic_calls
      h(payload);
    }
  }

  @override
  void on(String event, Function handler, {bool rawMap = false}) {
    registrations[event] = (registrations[event] ?? 0) + 1;
    (_handlers[event] ??= []).add(handler);
  }

  @override
  void open(Map<String, dynamic> options) {
    opened.add(options);
    // The real `open` is `async void`: its errors escape as uncaught async
    // errors, which is what the gateway's zone has to catch.
    if (openError case final e?) Future<void>.error(e);
  }

  @override
  void clear() {
    cleared = true;
    _handlers.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
