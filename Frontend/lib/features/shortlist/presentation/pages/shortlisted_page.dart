import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/feedback/empty_state.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../providers/shortlist_provider.dart';
import '../widgets/shortlisted_profile_card.dart';

/// Shortlisted Profiles — route wired from the navigation drawer. Real
/// state via [shortlistNotifierProvider], the same single source of truth
/// Discover/Matches/Profile Detail/Search read and mutate — removing a
/// profile here is immediately reflected everywhere else.
class ShortlistedPage extends ConsumerStatefulWidget {
  const ShortlistedPage({super.key});

  @override
  ConsumerState<ShortlistedPage> createState() => _ShortlistedPageState();
}

class _ShortlistedPageState extends ConsumerState<ShortlistedPage> {
  // Tracks which specific profile currently has a remove request in
  // flight, so only that card shows a loading spinner and gets disabled —
  // not the whole list — and a rapid second tap on the same card no-ops
  // (the notifier itself also guards this, this is just the visual half).
  final Set<String> _busyIds = {};

  Future<void> _remove(String profileId) async {
    setState(() => _busyIds.add(profileId));
    try {
      await ref.read(shortlistNotifierProvider.notifier).removeFromShortlist(profileId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).shortlistActionFailed)),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(profileId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shortlistedAsync = ref.watch(shortlistNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.drawerShortlist)),
      body: SafeArea(
        child: shortlistedAsync.when(
          loading: () => const _LoadingView(),
          error: (error, _) => NmErrorWidget(
            onRetry: () => ref.read(shortlistNotifierProvider.notifier).refresh(),
          ),
          data: (profiles) => profiles.isEmpty
              ? _EmptyView(l10n: l10n)
              : RefreshIndicator(
                  onRefresh: () => ref.read(shortlistNotifierProvider.notifier).refresh(),
                  child: _ShortlistedList(
                    profiles: profiles,
                    busyIds: _busyIds,
                    onRemove: _remove,
                  ),
                ),
        ),
      ),
    );
  }
}

class _ShortlistedList extends StatelessWidget {
  final List<DiscoveryProfileEntity> profiles;
  final Set<String> busyIds;
  final void Function(String profileId) onRemove;

  const _ShortlistedList({
    required this.profiles,
    required this.busyIds,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      scrollCacheExtent: const ScrollCacheExtent.pixels(600),
      itemCount: profiles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final profile = profiles[index];
        return ShortlistedProfileCard(
          key: ValueKey(profile.id),
          profile: profile,
          isBusy: busyIds.contains(profile.id),
          onRemove: () => onRemove(profile.id),
        );
      },
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => const NmShimmer.card(),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final AppLocalizations l10n;
  const _EmptyView({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: NmEmptyState(
            title: l10n.shortlistEmptyTitle,
            message: l10n.shortlistEmptyMessage,
            icon: Icons.bookmark_border_rounded,
            action: SizedBox(
              width: 200,
              child: NmPrimaryButton(
                label: l10n.shortlistExploreProfiles,
                onPressed: () => context.go(RouteNames.discover),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
