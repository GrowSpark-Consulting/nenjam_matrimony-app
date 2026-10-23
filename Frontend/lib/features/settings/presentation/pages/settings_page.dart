import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/content_width.dart';
import '../../../../core/permissions/nm_permission.dart';
import '../../../../core/permissions/permission_providers.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/dialogs/app_dialogs.dart';
import '../../../../core/widgets/inputs/nm_toggle_row.dart';
import '../../../../core/widgets/permissions/permission_dialogs.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../authentication/domain/services/local_auth_session.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../authentication/presentation/utils/logout_flow.dart';
import '../providers/settings_providers.dart';

/// App settings screen.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with WidgetsBindingObserver {
  bool _deletingAccount = false;

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
    final l10n = AppLocalizations.of(context);
    final permissions = ref.read(appPermissionServiceProvider);
    if (!wantsEnabled) {
      // The OS is the only source of truth for this permission — Nenjam
      // can't revoke it in-app, only direct the user to where they can.
      await showOpenSettingsDialog(
        context,
        title: l10n.notificationsTitle,
        message: l10n.settingsNotificationsOffMessage,
        onOpenSettings: permissions.openSettings,
      );
      return;
    }

    final status = await permissions.statusOf(NmPermission.notification);
    if (!mounted) return;
    if (status == NmPermissionStatus.permanentlyDenied) {
      await showOpenSettingsDialog(
        context,
        title: l10n.permissionNotificationsDisabledTitle,
        message: l10n.permissionNotificationsDisabledMessage,
        onOpenSettings: permissions.openSettings,
      );
      return;
    }

    final enable = await showPermissionPrimerDialog(
      context,
      icon: Icons.notifications_active_rounded,
      title: l10n.permissionNotificationsEnableTitle,
      message: l10n.permissionNotificationsEnableMessage,
      proceedLabel: l10n.commonEnable,
      cancelLabel: l10n.commonNotNow,
    );
    if (!enable) return;
    await permissions.request(NmPermission.notification);
    ref.invalidate(notificationPermissionStatusProvider);
  }

  Future<void> _handleDeleteAccount() async {
    if (_deletingAccount) return;
    final l10n = AppLocalizations.of(context);

    final confirmed = await AppDialogs.showDelete(
      context,
      title: l10n.settingsDeleteAccount,
      message: l10n.settingsDeleteAccountConfirmMessage,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingAccount = true);
    AppDialogs.showProgress(context, message: l10n.settingsDeleteAccountProgressMessage);
    try {
      await ref.read(settingsRepositoryProvider).deleteAccount();
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss progress dialog
      await ref.read(authRepositoryProvider).logout();
      // A mobile login (OTP or password) leaves no Firebase session for the
      // sign-out above to end, so the local one has to be closed explicitly
      // here too — see logout_flow.dart's confirmAndLogout, which this
      // mirrors. Without it, a deleted account whose only session was local
      // still satisfies the router guard, so the device stays "logged in"
      // to an account that no longer exists.
      await ref.read(localAuthSessionProvider).clear();
      if (!mounted) return;
      context.go(RouteNames.login);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss progress dialog
      await AppDialogs.showError(context, message: l10n.settingsDeleteAccountErrorMessage);
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
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
          padding: NmContentWidth.pagePadding(context, const EdgeInsets.all(20)),
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
            NmToggleRow(
              icon: Icons.notifications_outlined,
              title: l10n.settingsPushNotifications,
              value: notificationStatus.valueOrNull?.isGranted ?? false,
              onChanged: notificationStatus.isLoading ? null : _onNotificationsToggle,
            ),
            const Divider(height: 32),
            Text(
              l10n.settingsAppPreferencesSection,
              style: AppTypography.labelLarge,
            ),
            const SizedBox(height: 8),
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
            const Divider(height: 32),
            Text(
              l10n.settingsDangerZoneSection,
              style: AppTypography.labelLarge.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded, color: AppColors.error),
              title: Text(
                l10n.settingsDeleteAccount,
                style: AppTypography.bodyLarge.copyWith(color: AppColors.error),
              ),
              subtitle: Text(l10n.settingsDeleteAccountSubtitle),
              trailing: _deletingAccount
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: _deletingAccount ? null : _handleDeleteAccount,
            ),
          ],
        ),
      ),
    );
  }
}
