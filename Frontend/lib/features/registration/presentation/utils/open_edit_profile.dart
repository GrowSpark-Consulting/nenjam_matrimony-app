import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../providers/registration_provider.dart';

/// Switches the registration provider into EDIT MODE, fetches the logged-in
/// user's saved profile (`GET /profiles/draft`), then opens either the
/// review summary (Edit Profile) or a specific wizard step pre-populated
/// with that data. A blocking loader covers the fetch since it's a network
/// round-trip. Shared by the navigation drawer and the Profile Completion
/// screen — every "edit this section" action goes through here.
Future<void> openEditProfile(
  BuildContext context,
  WidgetRef ref, {
  int? wizardStep,
}) async {
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
      const SnackBar(
        content: Text('Could not load your profile. Check your connection.'),
      ),
    );
    return;
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // dismiss loader

  if (wizardStep != null) {
    ref.read(registrationProvider.notifier).goToStep(wizardStep);
    context.push(RouteNames.registrationWizard);
  } else {
    context.push(RouteNames.profileReview);
  }
}
