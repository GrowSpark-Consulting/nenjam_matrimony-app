import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../providers/registration_provider.dart';
import '../../../../l10n/app_localizations.dart';

/// Where a profile section is edited — every section has a page of its own.
///
/// [section] indices are [ProfileDraft] step indices, the values callers
/// have always passed (and that the backend returns as `wizardStep` on the
/// profile-completion modules). A null section opens Edit Profile's section
/// list.
///
/// Step 2 (languages) has no page: the registration flow does not collect it,
/// so Edit Profile does not edit it either. It, and any index this build does
/// not know, opens the section list rather than a page that does not exist.
String profileSectionRoute(int? section) => switch (section) {
      0 => RouteNames.basicInfoEdit,
      1 => RouteNames.religionCommunityEdit,
      3 => RouteNames.locationEdit,
      4 => RouteNames.educationWorkEdit,
      5 => RouteNames.physicalDetailsEdit,
      6 => RouteNames.lifestyleAboutEdit,
      7 => RouteNames.familyDetailsEdit,
      8 => RouteNames.horoscopeDetailsEdit,
      9 => RouteNames.psychologyQuiz,
      10 => RouteNames.partnerPreferences,
      11 => RouteNames.photosEdit,
      12 => RouteNames.verification,
      _ => RouteNames.editProfile,
    };

/// Switches the registration provider into EDIT MODE, fetches the logged-in
/// user's saved profile (`GET /profiles/draft`), then opens either Edit
/// Profile's section list or one section's edit page (see
/// [profileSectionRoute]), pre-populated with that data. A blocking loader
/// covers the fetch since it's a network round-trip. Shared by the
/// navigation drawer, the Profile screen and the Profile Completion screen —
/// every "edit this section" action from outside Edit Profile goes through
/// here.
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
      SnackBar(
        content: Text(AppLocalizations.of(context).commonProfileLoadConnectionError),
      ),
    );
    return;
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // dismiss loader

  context.push(profileSectionRoute(wizardStep));
}
