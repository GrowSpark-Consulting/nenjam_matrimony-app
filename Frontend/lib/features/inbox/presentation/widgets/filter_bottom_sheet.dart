import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/chips/app_chips.dart';
import '../../../../core/widgets/sheets/app_sheets.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/inbox_providers.dart';

Future<void> showFilterBottomSheet(BuildContext context) {
  return AppSheets.show<void>(
    context,
    title: AppLocalizations.of(context).inboxFilterSheetTitle,
    child: const FilterBottomSheet(),
  );
}

/// Multi-select filter chips for [InboxFilter] — writes directly to
/// [inboxFilterProvider], so [filteredConversationsProvider] re-derives
/// the list live as chips are toggled (no separate "Apply" step needed for
/// a lightweight set of independent boolean filters like this).
class FilterBottomSheet extends ConsumerWidget {
  const FilterBottomSheet({super.key});

  String _label(AppLocalizations l10n, InboxFilter filter) => switch (filter) {
        InboxFilter.unread => l10n.inboxFilterUnread,
        InboxFilter.online => l10n.inboxFilterOnline,
        InboxFilter.verified => l10n.inboxFilterVerified,
        InboxFilter.premium => l10n.inboxFilterPremium,
        InboxFilter.recent => l10n.inboxFilterRecent,
        InboxFilter.archived => l10n.inboxFilterArchived,
        InboxFilter.blocked => l10n.inboxFilterBlocked,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(inboxFilterProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final filter in InboxFilter.values)
            NmFilterChip(
              label: _label(l10n, filter),
              isSelected: selected.contains(filter),
              onSelected: (isSelected) {
                final next = Set<InboxFilter>.from(selected);
                if (isSelected) {
                  next.add(filter);
                } else {
                  next.remove(filter);
                }
                ref.read(inboxFilterProvider.notifier).state = next;
              },
            ),
        ],
      ),
    );
  }
}
