import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

/// Interests Sent placeholder — route wired from the navigation drawer.
class InterestsSentPage extends StatelessWidget {
  const InterestsSentPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.drawerInterestSent),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.outbox_outlined,
                size: 64, color: AppColors.accentGold),
            const SizedBox(height: 16),
            Text('Coming Soon', style: AppTypography.titleLarge),
          ],
        ),
      ),
    );
  }
}
