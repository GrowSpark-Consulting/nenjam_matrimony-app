import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/feedback/empty_state.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/support_ticket.dart';
import '../providers/support_providers.dart';

class TicketHistoryPage extends ConsumerWidget {
  const TicketHistoryPage({super.key});

  Color _statusColor(SupportTicketStatus status) => switch (status) {
    SupportTicketStatus.open => AppColors.info,
    SupportTicketStatus.inProgress => AppColors.warning,
    SupportTicketStatus.resolved => AppColors.success,
    SupportTicketStatus.closed => AppColors.textTertiaryLight,
  };

  String _statusLabel(SupportTicketStatus status) => switch (status) {
    SupportTicketStatus.open => 'Open',
    SupportTicketStatus.inProgress => 'In Progress',
    SupportTicketStatus.resolved => 'Resolved',
    SupportTicketStatus.closed => 'Closed',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ticketsAsync = ref.watch(myTicketsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.supportTicketHistoryTitle)),
      body: RefreshIndicator(
        color: AppColors.secondary,
        onRefresh: () => ref.refresh(myTicketsProvider.future),
        child: ticketsAsync.when(
          data: (tickets) {
            if (tickets.isEmpty) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: 480,
                  child: NmEmptyState(
                    icon: Icons.confirmation_number_outlined,
                    title: l10n.supportTicketHistoryEmptyTitle,
                    message: l10n.supportTicketHistoryEmptyMessage,
                  ),
                ),
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              itemCount: tickets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final ticket = tickets[index];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.cardDark
                        : AppColors.cardLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              ticket.subject,
                              style: AppTypography.titleSmall,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(
                                ticket.status,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _statusLabel(ticket.status),
                              style: AppTypography.labelSmall.copyWith(
                                color: _statusColor(ticket.status),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ticket.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            );
          },
          loading: () => ListView(
            padding: const EdgeInsets.all(20),
            children: const [
              NmShimmer(height: 80, borderRadius: 16),
              SizedBox(height: 12),
              NmShimmer(height: 80, borderRadius: 16),
            ],
          ),
          error: (_, __) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: 480,
              child: NmEmptyState(
                icon: Icons.error_outline_rounded,
                title: l10n.supportTicketHistoryEmptyTitle,
                message: l10n.supportTicketHistoryErrorMessage,
                action: OutlinedButton.icon(
                  onPressed: () => ref.invalidate(myTicketsProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(AppLocalizations.of(context).commonRetry),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
