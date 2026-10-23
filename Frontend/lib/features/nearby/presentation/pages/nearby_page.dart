import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/content_width.dart';
import '../../../../core/permissions/permission_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/feedback/empty_state.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../providers/nearby_providers.dart';
import '../widgets/nearby_profile_card.dart';

/// Near Me — profiles within 100 km, nearest first.
///
/// Every branch of [NearbyState] gets its own copy and its own single action,
/// because the remedies genuinely differ: a denied permission needs the OS
/// dialog, a permanently denied one needs app settings, switched-off location
/// services need the device settings screen, and a failed request needs a
/// plain retry. Offering "Try Again" for all of them would leave a user tapping
/// a button that cannot possibly help.
class NearbyPage extends ConsumerStatefulWidget {
  const NearbyPage({super.key});

  @override
  ConsumerState<NearbyPage> createState() => _NearbyPageState();
}

class _NearbyPageState extends ConsumerState<NearbyPage> {
  @override
  void initState() {
    super.initState();
    // This screen is Near Me, so opening it is itself the request — resolve
    // straight away rather than making an already-granted user tap a button.
    // Never prompts (see [NearbyNotifier.resolveIfIdle]), and no-ops when the
    // Discover section has already loaded results, so arriving here from
    // Discover costs no second GPS read or API call.
    //
    // Deferred off the build phase: `resolveIfIdle` sets the notifier state
    // synchronously before its first await, and mutating a provider while the
    // widget tree is building throws.
    Future.microtask(
      () => ref.read(nearbyNotifierProvider.notifier).resolveIfIdle(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(nearbyNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.nearbyTitle)),
      body: SafeArea(
        child: switch (state) {
          // Idle is only ever momentary here — initState resolves it on the
          // next microtask — so it shows the same loading view rather than a
          // separate screen that would flash for one frame.
          NearbyIdle() || NearbyLoading() => const _LoadingView(),
          NearbyLoaded(profiles: final profiles) when profiles.isEmpty =>
            _EmptyView(radiusKm: state.radiusKm),
          NearbyLoaded(profiles: final profiles) => _NearbyList(
            profiles: profiles,
            isApproximate: state.isApproximate,
          ),
          NearbyPermissionRequired() => _PermissionView(
            isPermanentlyDenied: state.isPermanentlyDenied,
          ),
          NearbyLocationServicesOff() => const _ServicesOffView(),
          NearbyLocationFailure() => const _ErrorView(isLocationError: true),
          NearbyFetchFailure() => const _ErrorView(isLocationError: false),
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        Padding(
          padding: NmContentWidth.pagePadding(context, const EdgeInsets.fromLTRB(16, 16, 16, 8)),
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.nearbyLoading,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),
        // Card skeletons under the label, matching the list this resolves into
        // so the layout does not jump when results arrive.
        Expanded(
          child: ListView.separated(
            padding: NmContentWidth.pagePadding(context, const EdgeInsets.all(16)),
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) => const NmShimmer.card(),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Results
// ─────────────────────────────────────────────────────────────────────────────

class _NearbyList extends ConsumerWidget {
  const _NearbyList({required this.profiles, required this.isApproximate});

  final List<DiscoveryProfileEntity> profiles;
  final bool isApproximate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.read(nearbyNotifierProvider.notifier).refresh(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: NmContentWidth.pagePadding(context, const EdgeInsets.all(16)),
        // One extra leading item when the fix was coarse, so the header scrolls
        // with the list instead of pinning a banner over it.
        itemCount: profiles.length + (isApproximate ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (isApproximate && index == 0) return const _ApproximateNotice();
          final profile = profiles[index - (isApproximate ? 1 : 0)];
          return NearbyProfileCard(key: ValueKey(profile.id), profile: profile);
        },
      ),
    );
  }
}

/// Shown when the user granted "Approximate" location. Explains why distances
/// look rounder than expected rather than letting them look wrong — the
/// feature works fine on a coarse fix, it is just less precise.
class _ApproximateNotice extends StatelessWidget {
  const _ApproximateNotice();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.nearbyApproximateNotice,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondaryLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty / permission / error
// ─────────────────────────────────────────────────────────────────────────────

/// Scrollable so pull-to-refresh still works on a full-screen message, and so
/// nothing overflows on a short screen.
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.title,
    required this.message,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: NmEmptyState(
            title: title,
            message: message,
            icon: icon,
            action: actionLabel == null
                ? null
                : SizedBox(
                    width: 220,
                    child: NmPrimaryButton(
                      label: actionLabel!,
                      onPressed: onAction,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends ConsumerWidget {
  const _EmptyView({required this.radiusKm});

  final double radiusKm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return RefreshIndicator(
      onRefresh: () => ref.read(nearbyNotifierProvider.notifier).refresh(),
      child: _MessageView(
        title: l10n.nearbyEmptyTitle,
        message: l10n.nearbyEmptyMessage(radiusKm.round().toString()),
        icon: Icons.person_search_rounded,
        actionLabel: l10n.nearbyRefresh,
        onAction: () => ref.read(nearbyNotifierProvider.notifier).refresh(),
      ),
    );
  }
}

class _PermissionView extends ConsumerWidget {
  const _PermissionView({required this.isPermanentlyDenied});

  final bool isPermanentlyDenied;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    // Once the OS has stopped showing its dialog, "Enable Location" would do
    // nothing at all — the only honest offer left is the settings screen.
    if (isPermanentlyDenied) {
      return _MessageView(
        title: l10n.nearbyPermissionTitle,
        message: l10n.nearbyPermissionBlockedMessage,
        icon: Icons.location_off_rounded,
        actionLabel: l10n.nearbyOpenSettings,
        onAction: () =>
            ref.read(appPermissionServiceProvider).openSettings(),
      );
    }

    return _MessageView(
      title: l10n.nearbyPermissionTitle,
      message: l10n.nearbyPermissionMessage,
      icon: Icons.location_on_outlined,
      actionLabel: l10n.nearbyEnableLocation,
      onAction: () => ref
          .read(nearbyNotifierProvider.notifier)
          .requestPermissionAndLoad(),
    );
  }
}

class _ServicesOffView extends ConsumerWidget {
  const _ServicesOffView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return _MessageView(
      title: l10n.nearbyServicesOffTitle,
      message: l10n.nearbyServicesOffMessage,
      icon: Icons.gps_off_rounded,
      actionLabel: l10n.nearbyTurnOnLocation,
      onAction: () =>
          ref.read(nearbyNotifierProvider.notifier).openLocationSettings(),
    );
  }
}

class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.isLocationError});

  /// Distinguishes "we could not find you" from "we could not reach the
  /// server". Telling someone their location is broken when the network failed
  /// sends them to the wrong settings screen.
  final bool isLocationError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return _MessageView(
      title: l10n.nearbyErrorTitle,
      message: isLocationError
          ? l10n.nearbyLocationErrorMessage
          : l10n.nearbyFetchErrorMessage,
      icon: Icons.error_outline_rounded,
      actionLabel: l10n.nearbyRetry,
      onAction: () => ref.read(nearbyNotifierProvider.notifier).refresh(),
    );
  }
}
