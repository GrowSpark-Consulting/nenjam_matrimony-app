import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

/// Profile Visitors placeholder — route wired from the navigation drawer.
class VisitorsPage extends StatelessWidget {
  const VisitorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      // Default AppBar back button: automatically shown only when there's
      // something to pop back to, so it never crashes on a dead-end route.
      appBar: AppBar(
        title: Text(l10n.drawerVisitors),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility_outlined,
                size: 64, color: AppColors.accentGold),
            const SizedBox(height: 16),
            Text('Coming Soon', style: AppTypography.titleLarge),
          ],
        ),
      ),
    );
  }
}
