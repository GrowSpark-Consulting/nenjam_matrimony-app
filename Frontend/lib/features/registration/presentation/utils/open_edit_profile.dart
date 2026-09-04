import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../providers/registration_provider.dart';
import '../../../../l10n/app_localizations.dart';

/// Where a profile section is edited.
///
/// Most sections are field groups on the one editable page
/// (`ProfileEditPage`), which scrolls to [section] on open. Three are not:
/// the psychological quiz, partner preferences and verification are separate
/// features with pages of their own, and have been all along — the old
/// per-section wizard only ever embedded a CTA card that pushed those same
/// pages. They are linked directly rather than through a card that links
/// again.
///
/// [section] indices are [ProfileDraft] step indices, the values callers
/// have always passed (and that the backend returns as `wizardStep` on the
/// profile-completion modules). A null section opens the Edit Profile
/// summary.
String profileSectionRoute(int? section) => switch (section) {
      null => RouteNames.profileReview,
      9 => RouteNames.psychologyQuiz,
      10 => RouteNames.partnerPreferences,
      12 => RouteNames.verification,
      _ => '${RouteNames.profileEdit}?section=$section',
    };

/// Switches the registration provider into EDIT MODE, fetches the logged-in
/// user's saved profile (`GET /profiles/draft`), then opens either the
/// review summary (Edit Profile) or the editable page scrolled to a specific
/// section, pre-populated with that data. A blocking loader covers the fetch
/// since it's a network round-trip. Shared by the navigation drawer and the
/// Profile Completion screen — every "edit this section" action goes through
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
