import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/primary_button.dart';

/// Language selection page.
class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key});

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  String _selectedLanguage = 'en';

  static const _languages = [
    _Language('en', 'English', 'English'),
    _Language('ta', 'தமிழ்', 'Tamil'),
    _Language('hi', 'हिन्दी', 'Hindi'),

  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                'Choose Your\nLanguage',
                style: AppTypography.headlineLarge.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select your preferred language',
                style: AppTypography.bodyMedium.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 32),

              // Language Grid
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2.5,
                  ),
                  itemCount: _languages.length,
                  itemBuilder: (context, index) {
                    final lang = _languages[index];
                    final isSelected = lang.code == _selectedLanguage;

                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedLanguage = lang.code),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : (isDark
                                  ? AppColors.surfaceVariantDark
                                  : AppColors.surfaceVariantLight),
                          borderRadius: BorderRadius.circular(16),
                          border: isSelected
                              ? null
                              : Border.all(
                                  color: isDark
                                      ? AppColors.borderDark
                                      : AppColors.borderLight,
                                ),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              lang.nativeName,
                              style: AppTypography.titleSmall.copyWith(
                                color: isSelected
                                    ? Colors.white
                                    : null,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              lang.englishName,
                              style: AppTypography.labelSmall.copyWith(
                                color: isSelected
                                    ? Colors.white70
                                    : (isDark
                                        ? AppColors.textTertiaryDark
                                        : AppColors.textTertiaryLight),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Continue Button
              NmPrimaryButton(
                label: 'Continue',
                onPressed: () => context.go(RouteNames.onboarding),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Language {
  final String code;
  final String nativeName;
  final String englishName;
  const _Language(this.code, this.nativeName, this.englishName);
}
