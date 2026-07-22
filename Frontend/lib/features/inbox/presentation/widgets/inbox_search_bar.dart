import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/widgets/inputs/search_bar.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/inbox_providers.dart';

/// Thin wrapper around the shared [NmSearchBar], wired to
/// [inboxSearchQueryProvider] — the filter action lives in [InboxAppBar]
/// instead of inline here, per the Inbox's written spec.
class InboxSearchBar extends ConsumerWidget {
  const InboxSearchBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: NmSearchBar(
        hint: l10n.inboxSearchHint,
        onChanged: (value) => ref.read(inboxSearchQueryProvider.notifier).state = value,
      ),
    );
  }
}
