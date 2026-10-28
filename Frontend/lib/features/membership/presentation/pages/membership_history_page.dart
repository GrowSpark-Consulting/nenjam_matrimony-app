import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/membership_models.dart';
import '../providers/membership_providers.dart';
import '../utils/membership_format.dart';

/// `GET /membership/history` — the member's purchases and plan grants,
/// newest first (at most 50), exactly as the server reports them.
class MembershipHistoryPage extends ConsumerWidget {
  const MembershipHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(membershipHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.membershipHistoryTitle)),
      body: SafeArea(
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _Message(
            text: l10n.membershipLoadError,
            actionLabel: l10n.commonRetry,
            onAction: () => ref.invalidate(membershipHistoryProvider),
          ),
          data: (items) => items.isEmpty
              ? _Message(text: l10n.membershipHistoryEmpty)
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.refresh(membershipHistoryProvider.future),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (context, i) => NmContentWidth(
                      maxWidth: ContentWidth.prose,
                      fill: true,
                      child: _HistoryTile(item: items[i]),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final MembershipHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final start = item.startDate;
    final end = item.endDate;
    final price = item.priceInPaise;
    final details = <String>[
      if (item.months != null) l10n.membershipMonths(item.months!),
      if (price != null) formatPaise(price, item.currency),
      if (item.source == 'ADMIN_GRANT') l10n.membershipSourceGrant,
    ];
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.plan.name, style: AppTypography.titleSmall),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  describeHistoryStatus(item, l10n),
                  textAlign: TextAlign.end,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(details.join(' · '), style: AppTypography.bodySmall),
          ],
          if (start != null && end != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${formatMembershipDate(start, l10n)} – '
              '${formatMembershipDate(end, l10n)}',
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

class _Message extends StatelessWidget {
  const _Message({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.pagePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondaryLight,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: AppSpacing.base),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
