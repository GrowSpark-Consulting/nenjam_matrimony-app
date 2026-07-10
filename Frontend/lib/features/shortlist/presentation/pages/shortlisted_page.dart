import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

/// Shortlisted Profiles placeholder — route wired from the navigation drawer.
class ShortlistedPage extends StatelessWidget {
  const ShortlistedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: Text(l10n.drawerShortlist),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite_border_rounded,
                size: 64, color: AppColors.accentGold),
            const SizedBox(height: 16),
            Text('Coming Soon', style: AppTypography.titleLarge),
          ],
        ),
      ),
    );
  }
}
