import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/interest_card.dart';
import '../../../../core/widgets/feedback/empty_state.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../core/widgets/inputs/nm_toggle_row.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../safety/presentation/providers/blocked_users_provider.dart';
import '../../../safety/presentation/utils/handle_unblock_user.dart';
import '../../../settings/presentation/providers/settings_providers.dart';

const _shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatBlockedDate(DateTime date) =>
    '${_shortMonths[date.month - 1]} ${date.day}, ${date.year}';

/// Privacy & Safety screen — profile-visibility toggles (wired to the real,
/// if backend-dormant, `SettingsRepository`) and a Blocked Profiles list,
/// backed by `GET /users/blocked` via the existing `SafetyRepository` (the
/// same repository Profile Detail/Matches use to block/unblock) — so this
/// reflects every member the caller has ever blocked, not just the ones
/// reachable through an existing chat thread.
class PrivacyPage extends ConsumerStatefulWidget {
  const PrivacyPage({super.key});

  @override
  ConsumerState<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends ConsumerState<PrivacyPage> {
  final Set<String> _saving = {};

  Future<void> _toggle(String key, bool value) async {
    if (_saving.contains(key)) return;
    setState(() => _saving.add(key));
    try {
      await ref.read(settingsRepositoryProvider).updatePrivacySettings({key: value});
      if (!mounted) return;
      ref.invalidate(mySettingsProvider);
    } catch (_) {
      if (!mounted) return;
      ref.invalidate(mySettingsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).privacySaveErrorMessage)),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settingsAsync = ref.watch(mySettingsProvider);
    final blockedUsersAsync = ref.watch(blockedUsersNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.drawerPrivacy)),
      body: RefreshIndicator(
        color: AppColors.accentGold,
        onRefresh: () => Future.wait([
          ref.refresh(mySettingsProvider.future),
          ref.refresh(blockedUsersNotifierProvider.future),
        ]),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(l10n.privacyVisibilitySection, style: AppTypography.labelLarge),
            const SizedBox(height: 8),
            settingsAsync.when(
              data: (settings) => Column(
                children: [
                  NmToggleRow(
                    icon: Icons.workspace_premium_outlined,
                    title: l10n.privacyPremiumOnlyTitle,
                    subtitle: l10n.privacyPremiumOnlySubtitle,
                    value: settings['profileVisibleToPremiumOnly'] as bool? ?? false,
                    onChanged: _saving.contains('profileVisibleToPremiumOnly')
                        ? null
                        : (v) => _toggle('profileVisibleToPremiumOnly', v),
                  ),
                  NmToggleRow(
                    icon: Icons.photo_library_outlined,
                    title: l10n.privacyHidePhotosTitle,
                    subtitle: l10n.privacyHidePhotosSubtitle,
                    value: settings['hidePhotosFromNonConnections'] as bool? ?? false,
                    onChanged: _saving.contains('hidePhotosFromNonConnections')
                        ? null
                        : (v) => _toggle('hidePhotosFromNonConnections', v),
                  ),
                ],
              ),
              loading: () => const Column(
                children: [
                  NmShimmer(height: 64, borderRadius: 12),
                  SizedBox(height: 8),
                  NmShimmer(height: 64, borderRadius: 12),
                ],
              ),
              error: (_, __) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l10n.privacyLoadErrorMessage)),
                    TextButton(
                      onPressed: () => ref.invalidate(mySettingsProvider),
                      child: Text(AppLocalizations.of(context).commonRetry),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 40),
            Text(l10n.privacyBlockedSection, style: AppTypography.labelLarge),
            const SizedBox(height: 8),
            blockedUsersAsync.when(
              data: (blockedUsers) {
                if (blockedUsers.isEmpty) {
                  return NmEmptyState(
                    icon: Icons.block_rounded,
                    title: l10n.privacyBlockedEmptyTitle,
                    message: l10n.privacyBlockedEmptyMessage,
                  );
                }
                return Column(
                  children: [
                    for (final blockedUser in blockedUsers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: NmInterestCard(
                          name: blockedUser.profile.name,
                          details: '${blockedUser.profile.age} • '
                              '${blockedUser.profile.location} • '
                              '${l10n.privacyBlockedOnLabel(_formatBlockedDate(blockedUser.blockedAt))}',
                          message: '',
                          imageUrl: blockedUser.profile.photoUrls.isNotEmpty
                              ? blockedUser.profile.photoUrls.first
                              : null,
                          gender: blockedUser.profile.gender,
                          isReceived: false,
                          statusLabel: l10n.privacyBlockedStatusLabel,
                          statusBackgroundColor: AppColors.errorLight,
                          statusTextColor: AppColors.error,
                          withdrawLabel: l10n.privacyUnblockLabel,
                          // Reuses the same confirmation -> loading -> unblock
                          // -> SnackBar flow Profile Detail's "More" menu
                          // already uses — no second unblock implementation.
                          onWithdraw: () => handleUnblockUser(
                            context,
                            ref,
                            userId: blockedUser.profile.id,
                            userName: blockedUser.profile.name,
                            onUnblocked: () => ref
                                .read(blockedUsersNotifierProvider.notifier)
                                .removeBlockedUser(blockedUser.profile.id),
                          ),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const NmShimmer(height: 96, borderRadius: 20),
              error: (_, __) => NmEmptyState(
                icon: Icons.error_outline_rounded,
                title: l10n.privacyBlockedEmptyTitle,
                message: l10n.privacyLoadErrorMessage,
                action: TextButton(
                  onPressed: () => ref.invalidate(blockedUsersNotifierProvider),
                  child: Text(AppLocalizations.of(context).commonRetry),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
