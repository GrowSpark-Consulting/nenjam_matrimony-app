import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../avatars/app_avatars.dart';

/// App navigation drawer.
class NmDrawer extends StatelessWidget {
  final String? userName;
  final String? userEmail;
  final String? profileImageUrl;

  /// 'Male' / 'Female' / '' — picks the gender-aware placeholder icon
  /// when [profileImageUrl] is null.
  final String gender;
  final VoidCallback? onProfileTap;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onPremiumTap;
  final VoidCallback? onHelpTap;
  final VoidCallback? onLogoutTap;

  const NmDrawer({
    super.key,
    this.userName,
    this.userEmail,
    this.profileImageUrl,
    this.gender = '',
    this.onProfileTap,
    this.onSettingsTap,
    this.onPremiumTap,
    this.onHelpTap,
    this.onLogoutTap,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surfaceLight,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  NmCircleAvatar(
                    imageUrl: profileImageUrl,
                    size: 56,
                    gender: gender,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName ?? 'Guest User',
                          style: AppTypography.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (userEmail != null)
                          Text(
                            userEmail!,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textTertiaryLight,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Menu items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _DrawerItem(
                    icon: Icons.person_outline_rounded,
                    label: AppLocalizations.of(context).drawerProfile,
                    onTap: onProfileTap,
                  ),
                  _DrawerItem(
                    icon: Icons.workspace_premium_rounded,
                    label: AppLocalizations.of(context).navPremium,
                    onTap: onPremiumTap,
                    iconColor: AppColors.secondary,
                  ),
                  _DrawerItem(
                    icon: Icons.settings_outlined,
                    label: AppLocalizations.of(context).settingsTitle,
                    onTap: onSettingsTap,
                  ),
                  _DrawerItem(
                    icon: Icons.help_outline_rounded,
                    label: AppLocalizations.of(context).drawerHelp,
                    onTap: onHelpTap,
                  ),
                ],
              ),
            ),

            // Logout
            const Divider(height: 1),
            _DrawerItem(
              icon: Icons.logout_rounded,
              label: AppLocalizations.of(context).drawerLogout,
              onTap: onLogoutTap,
              iconColor: AppColors.error,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? iconColor;

  const _DrawerItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(label, style: AppTypography.bodyMedium),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
