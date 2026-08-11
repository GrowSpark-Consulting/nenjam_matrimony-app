import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../registration/presentation/providers/registration_provider.dart';
import '../../../../l10n/app_localizations.dart';

/// Hydrates the shared registration draft (`GET /profiles/draft`, via
/// [RegistrationNotifier.startEditMode] — the same call every other
/// post-registration edit entry point uses) then opens the standalone
/// Partner Preferences page pre-populated with the user's saved values.
/// Modeled directly on `open_edit_profile.dart`'s `openEditProfile`.
Future<void> openPartnerPreferences(BuildContext context, WidgetRef ref) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    await ref.read(registrationProvider.notifier).startEditMode();
  } catch (_) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loader
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).commonProfileLoadConnectionError),
      ),
    );
    return;
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // dismiss loader
  context.push(RouteNames.partnerPreferences);
}
