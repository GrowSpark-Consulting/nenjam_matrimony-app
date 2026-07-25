import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/profile_navigation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/cards/interest_card.dart';
import '../../../../core/widgets/feedback/empty_state.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../inbox/presentation/widgets/inbox_shimmer.dart';
import '../../domain/repositories/interests_repository.dart';
import '../providers/interests_provider.dart';
import '../utils/interest_status_label.dart';

/// Shared body content for both the Inbox's interests tabs and the
/// standalone Sent/Received Interests screens — one implementation, so the
/// two surfaces can never render or behave differently for the same data.
class InterestListView extends ConsumerStatefulWidget {
  final bool isReceived;

  const InterestListView({super.key, required this.isReceived});

  @override
  ConsumerState<InterestListView> createState() => _InterestListViewState();
}

class _InterestListViewState extends ConsumerState<InterestListView> {
  // Tracks which specific record currently has an accept/decline/withdraw
  // request in flight, so only that card's buttons show a loading spinner
  // and get disabled — not the whole list.
  final Set<String> _busyIds = {};

  Future<void> _respond(String id, {required bool accept}) async {
    setState(() => _busyIds.add(id));
    try {
      await ref.read(interestsNotifierProvider.notifier).respond(id, accept: accept);
    } catch (_) {
      if (mounted) _showError();
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> _withdraw(String id) async {
    setState(() => _busyIds.add(id));
    try {
      await ref.read(interestsNotifierProvider.notifier).withdraw(id);
    } catch (_) {
      if (mounted) _showError();
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  void _showError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).interestsActionFailed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isReceived = widget.isReceived;
    final interestsAsync =
        ref.watch(isReceived ? receivedInterestsProvider : sentInterestsProvider);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => ref.read(interestsNotifierProvider.notifier).refresh(),
      child: interestsAsync.when(
        loading: () => const InboxShimmer(),
        error: (error, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 40),
            NmErrorWidget(
              onRetry: () => ref.read(interestsNotifierProvider.notifier).refresh(),
            ),
          ],
        ),
        data: (records) {
          if (records.isEmpty) {
            return LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: NmEmptyState(
                    title: isReceived
                        ? l10n.interestsReceivedEmptyTitle
                        : l10n.interestsSentEmptyTitle,
                    message: isReceived
                        ? l10n.interestsReceivedEmptyMessage
                        : l10n.interestsSentEmptyMessage,
                    icon: isReceived
                        ? Icons.move_to_inbox_outlined
                        : Icons.outbox_outlined,
                  ),
                ),
              ),
            );
          }
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            cacheExtent: 600,
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              final isBusy = _busyIds.contains(record.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NmInterestCard(
                  name: record.profile.name,
                  details: '${record.profile.age} · ${record.profile.location}',
                  message: '',
                  gender: record.profile.gender,
                  isReceived: isReceived,
                  statusLabel: interestStatusLabel(record.status, l10n),
                  onTap: () => openProfileDetail(context, record.profile),
                  acceptLabel: l10n.inboxAccept,
                  declineLabel: l10n.inboxDecline,
                  withdrawLabel: l10n.interestsWithdraw,
                  isBusy: isBusy,
                  onAccept: record.status == InterestStatus.pending && isReceived && !isBusy
                      ? () => _respond(record.id, accept: true)
                      : null,
                  onDecline: record.status == InterestStatus.pending && isReceived && !isBusy
                      ? () => _respond(record.id, accept: false)
                      : null,
                  onWithdraw: record.status == InterestStatus.pending && !isReceived && !isBusy
                      ? () => _withdraw(record.id)
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
