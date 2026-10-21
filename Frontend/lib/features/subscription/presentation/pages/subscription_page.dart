import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

/// Checkout — not available, and says so.
///
/// This used to show a fixed price and a "Proceed to payment" button that
/// simply navigated to Discover, as if a payment had succeeded. No checkout or
/// payment-confirmation endpoint is mounted on the backend, so nothing can be
/// bought and no premium access can be granted. A client-side flag must never
/// grant premium; when real checkout exists, access has to come from the
/// backend's confirmed subscription state, not from this screen.
class SubscriptionPage extends StatelessWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.premiumTitle)),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: AppSpacing.pagePadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
