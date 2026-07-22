import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../l10n/app_localizations.dart';
import 'filter_bottom_sheet.dart';

/// Premium, clean AppBar — title only on the left, notification + filter
/// actions on the right. No extra branding.
class InboxAppBar extends StatelessWidget implements PreferredSizeWidget {
  const InboxAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppBar(
      title: Text(l10n.inboxTitle),
      actions: [
        IconButton(
          onPressed: () => context.push(RouteNames.notifications),
          icon: const Icon(Icons.notifications_none_rounded),
          tooltip: l10n.inboxNotificationsTooltip,
        ),
        IconButton(
          onPressed: () => showFilterBottomSheet(context),
          icon: const Icon(Icons.tune_rounded),
          tooltip: l10n.inboxFilterTooltip,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
