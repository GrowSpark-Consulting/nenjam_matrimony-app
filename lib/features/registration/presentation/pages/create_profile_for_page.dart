import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/registration_provider.dart';

/// "Who are you creating this profile for?" selection screen.
class CreateProfileForPage extends ConsumerStatefulWidget {
  const CreateProfileForPage({super.key});

  @override
  ConsumerState<CreateProfileForPage> createState() =>
      _CreateProfileForPageState();
}

class _CreateProfileForPageState extends ConsumerState<CreateProfileForPage> {
  String _selected = 'Myself';

  static const _options = [
    _ProfileForOption('Myself', Icons.person_rounded, 'I am looking for a match for myself'),
    _ProfileForOption('Son', Icons.boy_rounded, 'Finding a match for my son'),
    _ProfileForOption('Daughter', Icons.girl_rounded, 'Finding a match for my daughter'),
    _ProfileForOption('Brother', Icons.people_rounded, 'Finding a match for my brother'),
    _ProfileForOption('Sister', Icons.people_outline_rounded, 'Finding a match for my sister'),
    _ProfileForOption('Relative', Icons.family_restroom_rounded, 'Finding a match for a relative'),
    _ProfileForOption('Friend', Icons.handshake_rounded, 'Finding a match for a friend'),
  ];

  /// Localized display label for a stored relation value (value stays English).
  String _relationLabel(AppLocalizations l10n, String v) => switch (v) {
        'Myself' => l10n.authRegForMyself,
        'Son' => l10n.authRegForSon,
        'Daughter' => l10n.authRegForDaughter,
        'Brother' => l10n.authRegForBrother,
        'Sister' => l10n.authRegForSister,
        'Relative' => l10n.profileForRelative,
        'Friend' => l10n.authRegForFriend,
        _ => v,
      };

  String _relationSubtitle(AppLocalizations l10n, String v) => switch (v) {
        'Myself' => l10n.profileForMyselfSub,
        'Son' => l10n.profileForSonSub,
        'Daughter' => l10n.profileForDaughterSub,
        'Brother' => l10n.profileForBrotherSub,
        'Sister' => l10n.profileForSisterSub,
        'Relative' => l10n.profileForRelativeSub,
        'Friend' => l10n.profileForFriendSub,
        _ => v,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                l10n.registrationProfileForTitle,
                style: AppTypography.headlineLarge.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.registrationProfileForSubtitle,
                style: AppTypography.bodyMedium.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: _options.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final opt = _options[index];
                    final isSelected = _selected == opt.label;
                    return _ProfileForCard(
                      option: opt,
                      label: _relationLabel(l10n, opt.label),
                      subtitle: _relationSubtitle(l10n, opt.label),
                      isSelected: isSelected,
                      isDark: isDark,
                      onTap: () => setState(() => _selected = opt.label),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              NmGradientButton(
                label: l10n.commonContinue,
                icon: Icons.arrow_forward_rounded,
                onPressed: () {
                  ref
                      .read(registrationProvider.notifier)
                      .setProfileCreatedFor(_selected);
                  context.go(RouteNames.registrationWizard);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileForCard extends StatelessWidget {
  final _ProfileForOption option;
  final String label;
  final String subtitle;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _ProfileForCard({
    required this.option,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: isSelected
            ? AppDecorations.card(isDark: isDark).copyWith(
                border: Border.all(color: AppColors.primary, width: 2),
                color: AppColors.primary.withValues(alpha: 0.05),
              )
            : AppDecorations.card(isDark: isDark),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : (isDark
                        ? AppColors.surfaceVariantDark
                        : AppColors.surfaceVariantLight),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                option.icon,
                color: isSelected ? Colors.white : AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected ? AppColors.primary : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiaryLight,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.borderLight,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileForOption {
  final String label;
  final IconData icon;
  final String subtitle;
  const _ProfileForOption(this.label, this.icon, this.subtitle);
}
