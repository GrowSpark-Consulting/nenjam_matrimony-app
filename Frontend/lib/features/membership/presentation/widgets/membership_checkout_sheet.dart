import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../referral/domain/models/referral_models.dart';
import '../../domain/models/checkout_models.dart';
import '../../domain/models/membership_models.dart';
import '../purchase/membership_purchase.dart';
import '../utils/membership_format.dart';

/// Opens the order summary for [option]. Resolves to the message to show
/// once the sheet closes, or null when the member just closed it.
Future<String?> showMembershipCheckoutSheet(
  BuildContext context,
  PurchaseOption option,
) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  // Dragging away mid-payment would orphan the verify step; the sheet
  // closes through its own PopScope instead.
  enableDrag: false,
  builder: (context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: MembershipCheckoutSheet(option: option),
    ),
  ),
);

/// The order summary, following docs/membership/api-contract.md:
///
/// 1. The plan, with an optional, collapsed "Have a referral code?" box.
/// 2. Continue → `POST /membership/checkout` (`promoCode` only when typed).
///    The server's breakdown is then shown: plan price, referral discount,
///    GST, total.
/// 3. Pay → Razorpay for that order → `POST /membership/checkout/verify`.
///
/// One checkout is one Razorpay order. A closed or failed sheet pays the
/// same order again; only a different code makes a new checkout, and Pay is
/// never offered for an order priced with a code other than the one typed.
class MembershipCheckoutSheet extends ConsumerStatefulWidget {
  const MembershipCheckoutSheet({super.key, required this.option});

  final PurchaseOption option;

  @override
  ConsumerState<MembershipCheckoutSheet> createState() =>
      _MembershipCheckoutSheetState();
}

enum _Stage {
  /// Checkout and Pay available.
  ready,

  /// Razorpay open, or verify / activation polling running.
  paying,

  /// Verify couldn't be reached: only "Check again" (same values).
  uncertain,

  /// Paid, but not activated within the polling window.
  pending,
}

class _MembershipCheckoutSheetState
    extends ConsumerState<MembershipCheckoutSheet> {
  final _codeController = TextEditingController();

  _Stage _stage = _Stage.ready;
  bool _codeOpen = false;
  bool _checkingOut = false;

  CheckoutSession? _session;

  /// The normalised code [_session] was priced with, if any.
  String? _pricedCode;

  /// The last code the server refused; resubmitting it is pointless.
  String? _rejectedCode;

  String? _checkoutError;
  String? _codeError;

  /// After a cancelled or failed payment: the same order can be paid again.
  String? _payNote;

  /// Shown while paying: verifying, then activating.
  String? _progress;

  /// The sheet's success values, kept so verify can be retried.
  PaymentSucceeded? _paid;

  MembershipPurchaseService get _service =>
      ref.read(membershipPurchaseServiceProvider);

  bool get _working => _checkingOut || _stage == _Stage.paying;

  String get _typed => _codeOpen ? _codeController.text.trim() : '';

  /// The code a checkout would send now: null for none. Malformed text is
  /// reported by [_continue] rather than sent.
  String? get _typedCode =>
      _typed.isEmpty ? null : normalizeReferralCode(_typed);

  /// True until there is an order priced with exactly what is typed.
  bool get _needsCheckout =>
      _session == null ||
      (_typed.isEmpty ? _pricedCode != null : _typedCode != _pricedCode);

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_working) return;
    final l10n = AppLocalizations.of(context);
    final code = _typedCode;
    if (_typed.isNotEmpty && code == null) {
      setState(() => _codeError = l10n.referralCodeInvalid);
      return;
    }
    setState(() {
      _checkingOut = true;
      _checkoutError = null;
      _codeError = null;
      _payNote = null;
    });
    try {
      final session = await _service.startCheckout(
        widget.option,
        promoCode: code,
      );
      if (!mounted) return;
      setState(() {
        _session = session;
        _pricedCode = code;
        _rejectedCode = null;
      });
    } on PromoCodeRejectedException catch (e) {
      // The earlier pricing (if any) stays; it is never replaced by a
      // refused one, and Pay stays off until the code matches an order.
      if (!mounted) return;
      setState(() {
        _codeError = _rejectionMessage(e, l10n);
        _rejectedCode = code;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'PROMO_CODES_UNAVAILABLE') {
          _codeError = l10n.membershipPromoCodesUnavailable;
          _rejectedCode = code;
        } else {
          _checkoutError = _checkoutErrorMessage(e, l10n);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _checkoutError = _checkoutErrorMessage(e, l10n));
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  void _removeCode() {
    _codeController.clear();
    setState(() {
      _codeOpen = false;
      _codeError = null;
    });
  }

  static String _rejectionMessage(
    PromoCodeRejectedException e,
    AppLocalizations l10n,
  ) => switch (e.reason) {
    'INVALID' => l10n.membershipPromoInvalid,
    'NOT_FIRST_PLAN' => l10n.membershipPromoNotFirstPlan,
    'ALREADY_ATTRIBUTED' => l10n.membershipPromoAlreadyAttributed,
    'SELF_REFERRAL' => l10n.membershipPromoSelfReferral,
    'AGENT_PAUSED' => l10n.membershipPromoAgentPaused,
    'PHONE_NOT_VERIFIED' => l10n.membershipPromoPhoneNotVerified,
    // A reason this version doesn't know: the server's own sentence.
    _ => e.message,
  };

  static String _checkoutErrorMessage(Object error, AppLocalizations l10n) =>
      switch (error) {
        ApiException(code: 'CHECKOUT_UNAVAILABLE') =>
          l10n.membershipCheckoutUnavailable,
        // 400 "not on sale" and the like: the server's own sentence.
        ApiException(:final message) => message,
        // 502 from Razorpay, 503 not configured, or no connection.
        DioException() => l10n.membershipPurchaseStartFailed,
        _ => l10n.membershipPurchaseStartFailed,
      };

  Future<void> _pay() async {
    final session = _session;
    if (session == null || _working || _needsCheckout) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _stage = _Stage.paying;
      _payNote = null;
      _progress = null;
    });
    PurchaseResult result;
    try {
      result = await _service.pay(
        session,
        onPaid: (p) {
          if (!mounted) return;
          setState(() {
            _paid = p;
            _progress = l10n.membershipCheckoutVerifying;
          });
        },
        onActivating: _onActivating,
      );
    } on StateError {
      // Another payment sheet is already open; this tap opens nothing.
      if (mounted) setState(() => _stage = _Stage.ready);
      return;
    }
    _onResult(result);
  }

  void _onActivating() {
    if (!mounted) return;
    setState(
      () =>
          _progress = AppLocalizations.of(context).membershipCheckoutActivating,
    );
  }

  /// Verify again with the same values: never a new payment.
  Future<void> _checkAgain() async {
    final session = _session;
    final paid = _paid;
    if (session == null || paid == null || _working) return;
    setState(() {
      _stage = _Stage.paying;
      _progress = AppLocalizations.of(context).membershipCheckoutVerifying;
    });
    _onResult(
      await _service.confirm(session, paid, onActivating: _onActivating),
    );
  }

  void _onResult(PurchaseResult result) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    void close(String message) => Navigator.of(context).pop(message);
    switch (result) {
      case PurchaseResult.cancelled:
      case PurchaseResult.paymentFailed:
        // Nothing was granted and the same order is still payable.
        setState(() {
          _stage = _Stage.ready;
          _progress = null;
          _payNote = result == PurchaseResult.cancelled
              ? l10n.membershipPurchaseCancelled
              : l10n.membershipPurchaseFailed;
        });
      case PurchaseResult.verificationUncertain:
        setState(() => _stage = _Stage.uncertain);
      case PurchaseResult.activationPending:
        setState(() => _stage = _Stage.pending);
      case PurchaseResult.activated:
        close(l10n.membershipPurchaseActivated);
      case PurchaseResult.alreadyApplied:
        close(l10n.membershipPurchaseAlreadyApplied);
      case PurchaseResult.refunded:
        close(l10n.membershipPurchaseRefunded);
      case PurchaseResult.contactSupport:
        close(l10n.membershipPurchaseContactSupport);
      case PurchaseResult.unavailable:
        close(l10n.membershipPurchaseUnavailableHere);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final o = widget.option;
    final startsAt = o.startsAt;
    final session = _session;
    return PopScope(
      canPop: !_working,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${o.planName} · ${l10n.membershipMonths(o.months)}',
              style: AppTypography.titleMedium,
            ),
            // A renewal or downgrade is queued: say when it starts before
            // payment.
            if (o.isQueued && startsAt != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.membershipStartsOn(formatMembershipDate(startsAt, l10n)),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ],
            if (session != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _Breakdown(session: session),
            ],
            ..._codeBox(l10n),
            const SizedBox(height: AppSpacing.lg),
            ..._actions(l10n),
          ],
        ),
      ),
    );
  }

  /// "Have a referral code?", collapsed until tapped. Hidden once paying has
  /// started, and when a referral discount already applies without a typed
  /// code (a member referred at signup gets it on their first plan).
  List<Widget> _codeBox(AppLocalizations l10n) {
    if (_stage != _Stage.ready) return const [];
    final session = _session;
    if (session != null &&
        _pricedCode == null &&
        !_codeOpen &&
        (session.pricing?.hasDiscount ?? false)) {
      return const [];
    }
    final colors = Theme.of(context).colorScheme;
    if (!_codeOpen) {
      return [
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: _working ? null : () => setState(() => _codeOpen = true),
            child: Text(l10n.referralCodePrompt),
          ),
        ),
      ];
    }
    final applied = _pricedCode != null && !_needsCheckout;
    return [
      const SizedBox(height: AppSpacing.lg),
      Text(l10n.referralCodePrompt, style: AppTypography.titleSmall),
      const SizedBox(height: AppSpacing.sm),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: NmTextField(
              label: l10n.referralCodeLabel,
              controller: _codeController,
              enabled: !_working,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _continue(),
              onChanged: (_) => setState(() => _codeError = null),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: TextButton(
              onPressed: _working ? null : _removeCode,
              child: Text(l10n.referralCodeRemove),
            ),
          ),
        ],
      ),
      if (applied) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.membershipPromoCodeApplied(_pricedCode!),
          style: AppTypography.bodySmall.copyWith(color: AppColors.success),
        ),
      ],
      if (_codeError != null) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          _codeError!,
          style: AppTypography.bodySmall.copyWith(color: colors.error),
        ),
      ],
    ];
  }

  List<Widget> _actions(AppLocalizations l10n) {
    final session = _session;
    if (_stage == _Stage.uncertain || _stage == _Stage.pending) {
      return [
        Text(
          _stage == _Stage.uncertain
              ? l10n.membershipVerificationUncertain
              : l10n.membershipPurchaseActivationPending,
          style: AppTypography.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        NmGradientButton(
          label: l10n.membershipCheckAgain,
          onPressed: _checkAgain,
        ),
      ];
    }
    final secondary = AppTypography.bodySmall.copyWith(
      color: AppColors.textSecondaryLight,
    );
    if (_needsCheckout || session == null) {
      final refused = _rejectedCode != null && _typedCode == _rejectedCode;
      return [
        if (_checkoutError != null) ...[
          Text(_checkoutError!, style: AppTypography.bodyMedium),
          const SizedBox(height: AppSpacing.md),
        ],
        NmGradientButton(
          label: _checkoutError != null
              ? l10n.commonRetry
              : l10n.membershipCheckoutContinue,
          isLoading: _checkingOut,
          onPressed: _working || refused ? null : _continue,
        ),
      ];
    }
    return [
      NmGradientButton(
        label: l10n.membershipCheckoutPay(
          formatPaise(session.amountInPaise, session.currency),
        ),
        useAccentGradient: true,
        isLoading: _stage == _Stage.paying,
        onPressed: _working ? null : _pay,
      ),
      if (_stage == _Stage.paying && _progress != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          _progress!,
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall,
        ),
      ],
      if (_payNote != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(_payNote!, textAlign: TextAlign.center, style: secondary),
      ],
    ];
  }
}

/// Plan price, referral discount (when `discountPaise > 0`), GST (when
/// `taxPaise > 0`) and the total (`amountInPaise`) — the server's figures,
/// never recomputed here. The response carries no discount percentage, so
/// none is shown; the agent's name is shown when the server sends it.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.session});

  final CheckoutSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pricing = session.pricing;
    String money(int paise) => formatPaise(paise, session.currency);
    final agent = session.referralAgentName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pricing != null) ...[
          _Line(
            label: l10n.membershipCheckoutPlanPrice,
            value: money(pricing.listAmountPaise),
          ),
          if (pricing.hasDiscount) ...[
            const SizedBox(height: AppSpacing.sm),
            _Line(
              label: l10n.membershipCheckoutReferralDiscount,
              value: '−${money(pricing.discountPaise)}',
              valueColor: AppColors.success,
            ),
            if (agent != null)
              Text(
                l10n.referralCodeReferredBy(agent),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondaryLight,
                ),
              ),
          ],
          if (pricing.hasTax) ...[
            const SizedBox(height: AppSpacing.sm),
            _Line(
              label: l10n.membershipCheckoutGst(_percent(pricing.taxRateBps)),
              value: money(pricing.taxPaise),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
        ],
        _Line(
          label: l10n.membershipCheckoutTotal,
          value: money(session.amountInPaise),
          emphasised: true,
        ),
      ],
    );
  }

  /// Basis points as a percentage: `1800` → `18`, `1850` → `18.5`.
  static String _percent(int bps) {
    final whole = bps ~/ 100;
    final rest = bps % 100;
    if (rest == 0) return '$whole';
    final fraction = rest
        .toString()
        .padLeft(2, '0')
        .replaceAll(RegExp(r'0+$'), '');
    return '$whole.$fraction';
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasised = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final style = emphasised
        ? AppTypography.titleSmall
        : AppTypography.bodyMedium;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: AppSpacing.sm),
        Text(value, style: style.copyWith(color: valueColor)),
      ],
    );
  }
}
