import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/navigation/app_bottom_nav.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../membership/domain/models/membership_models.dart';
import '../../../membership/presentation/providers/membership_providers.dart';
import '../../../membership/presentation/purchase/membership_purchase.dart';
import '../../../membership/presentation/utils/membership_format.dart';

/// Premium tab, driven by `GET /membership/plans` and `GET /membership/me`.
///
/// While nothing can be bought — no paid plan has a priced length, or the
/// backend reports `checkoutAvailable: false` — it shows only the honest
/// "coming soon" state: no plans, prices or benefits. Otherwise every plan,
/// feature label, entitlement, price and duration comes from the API; none
/// is hard-coded here.
class PremiumPage extends ConsumerWidget {
  const PremiumPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(membershipPlansProvider);
    final purchasable = catalog.valueOrNull?.hasPurchasablePlans ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.premiumTitle)),
      // bottom: false — the shell draws the floating nav pill over this page,
      // and letting SafeArea eat that inset here would end the scroll viewport
      // above the pill and leave this Scaffold's own opaque background painting
      // a full-width strip behind it. The inset belongs on the scroll view's
      // padding instead, so the page scrolls THROUGH the transparent area
      // around the pill while the CTA below still comes to rest clear of it.
      //
      // SizedBox.expand: a Scaffold body gets loose height constraints, so on
      // its own the scroll viewport would shrink to this short content and
      // stop well above the pill — the same opaque strip, by another route.
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () {
            ref.invalidate(myMembershipProvider);
            return ref.refresh(membershipPlansProvider.future);
          },
          // Inside the RefreshIndicator: its Stack loosens constraints again.
          child: SizedBox.expand(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl3,
                AppSpacing.lg,
                navContentInset(context),
              ),
              child: NmContentWidth(
                maxWidth: purchasable ? ContentWidth.prose : ContentWidth.form,
                child: catalog.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => _LoadError(
                    onRetry: () => ref.invalidate(membershipPlansProvider),
                  ),
                  data: (catalog) => catalog.hasPurchasablePlans
                      ? _Plans(catalog: catalog)
                      : const _ComingSoon(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nothing on sale: no plans, prices or benefits — only the notice.
class _ComingSoon extends StatelessWidget {
  const _ComingSoon();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        const Icon(
          Icons.lock_outline_rounded,
          size: 48,
          color: AppColors.primary,
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          l10n.premiumTitle,
          textAlign: TextAlign.center,
          style: AppTypography.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.premiumUnavailableNotice,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        // No purchase is possible: the button stays visible but disabled,
        // labelled "Coming soon" with the reason above it, rather than
        // suggesting a payment could go ahead.
        NmGradientButton(
          label: l10n.premiumComingSoon,
          useAccentGradient: true,
          onPressed: null,
        ),
        const SizedBox(height: AppSpacing.sm),
        const _HistoryLink(),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Text(
          l10n.membershipLoadError,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
      ],
    );
  }
}

class _HistoryLink extends StatelessWidget {
  const _HistoryLink();

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => context.push(RouteNames.membershipHistory),
    child: Text(AppLocalizations.of(context).membershipHistoryTitle),
  );
}

/// Plans on sale, rendered entirely from the API.
class _Plans extends ConsumerWidget {
  const _Plans({required this.catalog});

  final MembershipCatalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myMembershipProvider).valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final plan in catalog.plans) ...[
          _PlanCard(
            plan: plan,
            features: catalog.features,
            isCurrent: me?.plan.code == plan.code,
            options: [
              for (final o in me?.purchaseOptions ?? const <PurchaseOption>[])
                if (o.planCode == plan.code) o,
            ],
            checkoutAvailable: me?.checkoutAvailable ?? false,
          ),
          const SizedBox(height: AppSpacing.base),
        ],
        const _HistoryLink(),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({
    required this.plan,
    required this.features,
    required this.isCurrent,
    required this.options,
    required this.checkoutAvailable,
  });

  final MembershipPlan plan;
  final List<MembershipFeature> features;
  final bool isCurrent;
  final List<PurchaseOption> options;
  final bool checkoutAvailable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entitlements = plan.entitlements ?? const <String, Object?>{};
    final rows = <(String, String)>[
      for (final f in features)
        if (entitlements.containsKey(f.key))
          if (describeEntitlement(f, entitlements[f.key], l10n)
              case final value?)
            (f.label, value),
    ];
    final canBuy =
        checkoutAvailable &&
        ref.watch(membershipPurchaseServiceProvider).isSupported;
    return Container(
      padding: AppSpacing.cardPaddingLarge,
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl2),
        border: isCurrent ? Border.all(color: AppColors.primary) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(plan.name, style: AppTypography.titleMedium),
              ),
              if (isCurrent)
                Text(
                  l10n.membershipCurrentPlan,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
          if (plan.description != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              plan.description!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondaryLight,
              ),
            ),
          ],
          for (final (label, value) in rows) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(label, style: AppTypography.bodySmall)),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: AppTypography.labelMedium,
                  ),
                ),
              ],
            ),
          ],
          for (final d in plan.priced) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${l10n.membershipMonths(d.months)} · '
              '${formatPaise(d.priceInPaise!, d.currency)}',
              style: AppTypography.titleSmall,
            ),
          ],
          // Web never buys (no payment SDK there): a note replaces the Buy
          // buttons rather than leaving dead ones.
          for (final option in options)
            if (option.priceInPaise != null && !kIsWeb) ...[
              const SizedBox(height: AppSpacing.md),
              _BuyButton(option: option, enabled: canBuy),
            ],
          if (options.isNotEmpty && !canBuy) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              kIsWeb
                  ? l10n.membershipPurchaseWebNote
                  : l10n.membershipPurchaseUnavailableHere,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondaryLight,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BuyButton extends ConsumerStatefulWidget {
  const _BuyButton({required this.option, required this.enabled});

  final PurchaseOption option;
  final bool enabled;

  @override
  ConsumerState<_BuyButton> createState() => _BuyButtonState();
}

class _BuyButtonState extends ConsumerState<_BuyButton> {
  bool _busy = false;

  Future<void> _buy() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    String message;
    try {
      final result = await ref
          .read(membershipPurchaseServiceProvider)
          .purchase(widget.option);
      message = switch (result) {
        PurchaseResult.activated => l10n.membershipPurchaseActivated,
        PurchaseResult.activationPending =>
          l10n.membershipPurchaseActivationPending,
        PurchaseResult.cancelled => l10n.membershipPurchaseCancelled,
        PurchaseResult.paymentFailed => l10n.membershipPurchaseFailed,
        PurchaseResult.contactSupport => l10n.membershipPurchaseContactSupport,
        PurchaseResult.unavailable => l10n.membershipPurchaseUnavailableHere,
      };
    } on ApiException catch (e) {
      // 400 "not on sale" and similar: the server's own sentence.
      message = e.message;
    } on DioException {
      // 502 from Razorpay, 503 not configured, or no connection.
      message = l10n.membershipPurchaseStartFailed;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final o = widget.option;
    final startsAt = o.startsAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NmGradientButton(
          label:
              '${l10n.membershipBuy} · ${l10n.membershipMonths(o.months)} · '
              '${formatPaise(o.priceInPaise!, o.currency)}',
          useAccentGradient: true,
          isLoading: _busy,
          onPressed: widget.enabled && !_busy ? _buy : null,
        ),
        // A renewal or downgrade is queued: say when it starts before payment.
        if (o.isQueued && startsAt != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.membershipStartsOn(formatMembershipDate(startsAt, l10n)),
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondaryLight,
            ),
          ),
        ],
      ],
    );
  }
}
