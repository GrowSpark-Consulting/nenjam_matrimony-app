import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/nm_permission.dart';
import '../../../../core/permissions/permission_providers.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/permissions/permission_dialogs.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../authentication/presentation/utils/logout_flow.dart';

/// App settings screen.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches "opened Settings to grant notifications, came back" — the OS
    // status can only have changed while this screen wasn't in the
    // foreground, so refresh right when it is again.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(notificationPermissionStatusProvider);
    }
  }

  Future<void> _onNotificationsToggle(bool wantsEnabled) async {
    final permissions = ref.read(appPermissionServiceProvider);
    if (!wantsEnabled) {
      // The OS is the only source of truth for this permission — Nenjam
      // can't revoke it in-app, only direct the user to where they can.
      await showOpenSettingsDialog(
        context,
        title: 'Notifications',
        message:
            'To turn off notifications, disable them for Nenjam Matrimony '
            'in Settings.',
        onOpenSettings: permissions.openSettings,
      );
      return;
    }

    final status = await permissions.statusOf(NmPermission.notification);
    if (!mounted) return;
    if (status == NmPermissionStatus.permanentlyDenied) {
      await showOpenSettingsDialog(
        context,
        title: 'Notifications Disabled',
        message: 'Enable notifications from Settings to stay updated.',
        onOpenSettings: permissions.openSettings,
      );
      return;
    }

    final enable = await showPermissionPrimerDialog(
      context,
      icon: Icons.notifications_active_rounded,
      title: 'Enable Notifications',
      message:
          'Get notified when someone sends you an interest, accepts your '
          'request, or messages you.',
      proceedLabel: 'Enable',
      cancelLabel: 'Not now',
    );
    if (!enable) return;
    await permissions.request(NmPermission.notification);
    ref.invalidate(notificationPermissionStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Reflect the currently active locale in the Language row subtitle.
    final activeLanguage = Localizations.localeOf(context).languageCode == 'ta'
        ? l10n.languageTamil
        : l10n.languageEnglish;
    final notificationStatus = ref.watch(notificationPermissionStatusProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              l10n.settingsAccountSecuritySection,
              style: AppTypography.labelLarge,
            ),
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
              trailing: Switch(
                value: notificationStatus.valueOrNull?.isGranted ?? false,
                onChanged: notificationStatus.isLoading
                    ? null
                    : _onNotificationsToggle,
              ),
            ),
            const Divider(height: 32),
            Text(
              l10n.settingsAppPreferencesSection,
              style: AppTypography.labelLarge,
            ),
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
              title: Text(
                l10n.settingsLogout,
                style: AppTypography.bodyLarge.copyWith(color: AppColors.error),
              ),
              onTap: () => confirmAndLogout(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
