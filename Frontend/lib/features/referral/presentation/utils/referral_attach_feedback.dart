import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/services/referral_attachment_controller.dart';

/// The gentle, non-blocking line a member sees after an attach attempt, or
/// null when there is nothing to say (no code waiting, not signed in yet).
String? referralAttachMessage(
  AppLocalizations l10n,
  ReferralAttachOutcome outcome,
) => switch (outcome) {
  ReferralAttachOutcome.attached => l10n.referralCodeAttached,
  ReferralAttachOutcome.alreadyAttributed => l10n.referralCodeAlreadyLinked,
  ReferralAttachOutcome.codeNotFound => l10n.referralCodeNotApplied,
  ReferralAttachOutcome.notAllowed => l10n.referralCodeNotAllowed,
  ReferralAttachOutcome.retryLater => l10n.referralCodeRetryLater,
  ReferralAttachOutcome.gaveUp => l10n.referralCodeNotApplied,
  ReferralAttachOutcome.nothingPending ||
  ReferralAttachOutcome.notSignedIn => null,
};

/// Runs [attach] without holding anything up, then shows its message on
/// [messenger] — captured by the caller *before* it navigates, so the line
/// still appears on the next screen.
void attachReferralInBackground({
  required Future<ReferralAttachOutcome> Function() attach,
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
}) {
  attach().then((outcome) {
    final message = referralAttachMessage(l10n, outcome);
    if (message == null || !messenger.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }, onError: (Object _) {});
}
