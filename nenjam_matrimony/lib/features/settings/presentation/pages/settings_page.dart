import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// App settings screen.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Account & Security', style: AppTypography.labelLarge),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('ID Verification'),
              subtitle: const Text('Verify ID to get trust badge'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(RouteNames.verification),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Push Notifications'),
              trailing: Switch(value: true, onChanged: (_) {}),
            ),
            const Divider(height: 32),
            Text('App Preferences', style: AppTypography.labelLarge),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: const Text('Dark Mode'),
              trailing: Switch(value: false, onChanged: (_) {}),
            ),
            ListTile(
              leading: const Icon(Icons.translate_rounded),
              title: const Text('Language'),
              subtitle: const Text('English'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(RouteNames.language),
            ),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.help_outline_rounded),
              title: const Text('Help & Support'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(RouteNames.help),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: AppColors.error),
              title: Text('Logout',
                  style: AppTypography.bodyLarge.copyWith(color: AppColors.error)),
              onTap: () => context.go(RouteNames.login),
            ),
          ],
        ),
      ),
    );
  }
}
