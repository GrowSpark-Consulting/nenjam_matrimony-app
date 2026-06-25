import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/storage_service.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';

/// Language selection page with rich Indian language support.
class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key});

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  late String _selectedLanguage;

  static const _languages = [
    _Language('en', 'English', 'English'),
    _Language('ta', 'தமிழ்', 'Tamil'),
    _Language('te', 'తెలుగు', 'Telugu'),
    _Language('ml', 'മലയാളം', 'Malayalam'),
    _Language('kn', 'ಕನ್ನಡ', 'Kannada'),
    _Language('hi', 'हिन्दी', 'Hindi'),
    _Language('mr', 'മറാഠി / मराठी', 'Marathi'),
    _Language('bn', 'বাংলা', 'Bengali'),
    _Language('gu', 'ગુજરાતી', 'Gujarati'),
    _Language('ur', 'اردو', 'Urdu'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedLanguage = storageService.language;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text(
                'Choose Your\nLanguage',
                style: AppTypography.headlineLarge.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select your preferred language for matchmaking',
                style: AppTypography.bodyMedium.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 24),

              // Language Grid
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2.2,
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
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              lang.nativeName,
                              style: AppTypography.titleMedium.copyWith(
                                color: isSelected ? Colors.white : null,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
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
              const SizedBox(height: 16),

              // Continue Button
              NmGradientButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                onPressed: () async {
                  await storageService.setLanguage(_selectedLanguage);
                  if (context.mounted) {
                    context.go(RouteNames.onboarding);
                  }
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

class _Language {
  final String code;
  final String nativeName;
  final String englishName;
  const _Language(this.code, this.nativeName, this.englishName);
}
