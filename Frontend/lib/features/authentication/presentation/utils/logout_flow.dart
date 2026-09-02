import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/services/local_auth_session.dart';
import '../providers/auth_providers.dart';

/// Confirms with the user, then signs out and returns to the sign-up
/// landing screen with a cleared navigation stack.
///
/// The single logout entry point shared by every UI surface that can
/// trigger one (Settings, nav drawer, ...) — actual session teardown
/// (SharedPreferences, registration draft, pending OTP) happens once,
/// centrally, in NenjamMatrimonyApp's authStateChanges listener, regardless
/// of which entry point called this.
Future<void> confirmAndLogout(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.settingsLogout),
      content: Text(l10n.authLogoutConfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: Text(l10n.settingsLogout),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  await ref.read(authRepositoryProvider).logout();
  // A mobile login leaves no Firebase session for the sign-out above to
  // end, so the local one has to be closed explicitly — otherwise the
  // router's guard would keep letting the "logged out" user back in.
  await ref.read(localAuthSessionProvider).clear();
  if (!context.mounted) return;
  context.go(RouteNames.registrationLanding);
}
