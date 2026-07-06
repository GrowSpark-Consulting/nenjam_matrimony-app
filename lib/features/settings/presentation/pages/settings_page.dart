import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

/// App settings screen.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Reflect the currently active locale in the Language row subtitle.
    final activeLanguage = Localizations.localeOf(context).languageCode == 'ta'
        ? l10n.languageTamil
        : l10n.languageEnglish;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(l10n.settingsAccountSecuritySection,
                style: AppTypography.labelLarge),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: Text(l10n.settingsIdVerificationTitle),
              subtitle: Text(l10n.settingsIdVerificationSubtitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(RouteNames.verification),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: Text(l10n.settingsPushNotifications),
              trailing: Switch(value: true, onChanged: (_) {}),
            ),
            const Divider(height: 32),
            Text(l10n.settingsAppPreferencesSection,
                style: AppTypography.labelLarge),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: Text(l10n.settingsDarkMode),
              trailing: Switch(value: false, onChanged: (_) {}),
            ),
            ListTile(
              leading: const Icon(Icons.translate_rounded),
              title: Text(l10n.settingsLanguage),
              subtitle: Text(activeLanguage),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(RouteNames.language),
            ),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.help_outline_rounded),
              title: Text(l10n.settingsHelpSupport),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(RouteNames.help),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: AppColors.error),
              title: Text(l10n.settingsLogout,
                  style: AppTypography.bodyLarge.copyWith(color: AppColors.error)),
              onTap: () => context.go(RouteNames.login),
            ),
          ],
        ),
      ),
    );
  }
}
