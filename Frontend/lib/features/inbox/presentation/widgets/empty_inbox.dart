import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/feedback/empty_state.dart';
import '../../../../l10n/app_localizations.dart';

/// Wraps the shared [NmEmptyState] rather than its `.noMessages` named
/// constructor — that constructor hardcodes English copy with no l10n hook,
/// and this feature needs both languages.
class EmptyInbox extends StatelessWidget {
  /// Whether to offer the "go to Discover" button. Off where the empty inbox is
  /// already shown on Discover, where the button would lead nowhere.
  final bool showAction;

  const EmptyInbox({super.key, this.showAction = true});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return NmEmptyState(
      title: l10n.inboxEmptyTitle,
      message: l10n.inboxEmptySubtitle,
      icon: Icons.forum_outlined,
      action: showAction
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: NmPrimaryButton(
                label: l10n.inboxEmptyCta,
                onPressed: () {
                  // The Inbox tab is a StatefulShellRoute branch — jump to the
                  // Discover branch (index 0) rather than pushing a new route
                  // on top of this one.
                  StatefulNavigationShell.maybeOf(context)?.goBranch(0);
                },
              ),
            )
          : null,
    );
  }
}
