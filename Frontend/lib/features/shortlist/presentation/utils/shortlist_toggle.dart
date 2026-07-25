import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../providers/shortlist_provider.dart';

/// Single place every shortlist/bookmark button in the app calls to toggle
/// — the notifier itself already applies the optimistic update
/// synchronously and rolls back on failure; this just adds the one thing
/// every call site would otherwise duplicate: showing an error SnackBar
/// when the rolled-back-to state reaches the user.
Future<void> handleShortlistToggle(
  BuildContext context,
  WidgetRef ref,
  DiscoveryProfileEntity profile,
) async {
  try {
    await ref.read(shortlistNotifierProvider.notifier).toggleShortlist(profile);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).shortlistActionFailed)),
    );
  }
}
