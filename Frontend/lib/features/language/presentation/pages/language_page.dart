import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/locale_provider.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../l10n/app_localizations.dart';

/// Language selection screen.
///
/// Tapping a card switches the app locale instantly (and persists it via
/// [localeProvider]); Continue proceeds to authentication. Localized
/// labels update live as the selection changes.
class LanguagePage extends ConsumerStatefulWidget {
  const LanguagePage({super.key});

  @override
  ConsumerState<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends ConsumerState<LanguagePage> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = ref.watch(localeProvider).languageCode;

    final options = <_LanguageOption>[
      _LanguageOption(code: 'en', nativeName: 'English', label: l10n.languageEnglish),
      _LanguageOption(code: 'ta', nativeName: 'தமிழ்', label: l10n.languageTamil),
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppConstants.maxContentWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    l10n.languageChooseTitle,
                    style: AppTypography.headlineLarge.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.languageChooseSubtitle,
                    style: AppTypography.bodyMedium.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ─── Language cards ──────────────────────────────
                  Expanded(
                    child: ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      itemCount: options.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final option = options[index];
                        return _LanguageCard(
                          option: option,
                          isSelected: option.code == selected,
                          isDark: isDark,
                          onTap: () => _onSelect(option.code),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ─── Continue ────────────────────────────────────
                  NmGradientButton(
                    label: l10n.commonContinue,
                    icon: Icons.arrow_forward_rounded,
                    onPressed: _onContinue,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Applies the locale immediately (whole app) and persists the choice.
  void _onSelect(String code) {
    ref.read(localeProvider.notifier).changeLocale(code);
  }

  void _onContinue() {
    // Ensure the currently-active locale is persisted before leaving —
    // covers the case where the user accepts the default without tapping.
    ref.read(localeProvider.notifier).changeLocale(
          ref.read(localeProvider).languageCode,
        );
    context.go(RouteNames.onboarding);
  }
}

/// A single selectable language, with its native script name and a
/// localized descriptor.
class _LanguageOption {
  final String code;
  final String nativeName;
  final String label;

  const _LanguageOption({
    required this.code,
    required this.nativeName,
    required this.label,
  });
}

/// Premium selection card with an animated selected state and check badge.
class _LanguageCard extends StatelessWidget {
  final _LanguageOption option;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _LanguageCard({
    required this.option,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final baseSurface =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;
    final borderColor = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Semantics(
      button: true,
      selected: isSelected,
      label: option.label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? AppColors.primary.withValues(alpha: 0.18)
                  : AppColors.primarySurface)
              : baseSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.primary : borderColor,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              child: Row(
                children: [
                  // Language glyph badge
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark
                              ? AppColors.surfaceDark
                              : Colors.white),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      option.nativeName.characters.first,
                      style: AppTypography.titleLarge.copyWith(
                        color: isSelected
                            ? Colors.white
                            : AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Names
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.nativeName,
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          option.label,
                          style: AppTypography.bodySmall.copyWith(
                            color: isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Animated check indicator
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: isSelected
                        ? Container(
                            key: const ValueKey('checked'),
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              color: AppColors.accentGold,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 17,
                              color: Colors.white,
                            ),
                          )
                        : Container(
                            key: const ValueKey('unchecked'),
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? AppColors.borderDark
                                    : AppColors.borderLight,
                                width: 1.5,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
