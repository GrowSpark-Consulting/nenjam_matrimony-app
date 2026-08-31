import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../registration/domain/models/profile_draft.dart';
import '../../../registration/presentation/widgets/step_verification.dart';
import '../providers/verification_providers.dart';

/// Trust & Verification center screen.
///
/// Renders the same [StepVerification] widget the registration wizard's
/// step 13 uses — real Firebase mobile/email checks, real document
/// upload/progress/retry via [verificationStatusesProvider] — rather than a
/// second, static implementation. [status]/`onChanged` only exist so that
/// widget can mirror results into a `ProfileDraft` mid-wizard; standalone
/// here, there is no draft to mirror into, so a throwaway value and a
/// no-op are passed.
class VerificationPage extends ConsumerWidget {
  const VerificationPage({super.key});

  static void _noop(VerificationStatus _) {}

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.registrationVerificationTitle)),
      body: SafeArea(
        // StepVerification already wraps its own content in a
        // SingleChildScrollView — RefreshIndicator only needs a Scrollable
        // descendant somewhere in its subtree to detect the pull gesture,
        // not to be the scrollable itself, so it's not wrapped again here
        // (nesting two vertical scroll views causes an unbounded-height
        // layout assertion).
        child: RefreshIndicator(
          color: AppColors.secondary,
          onRefresh: () =>
              ref.read(verificationStatusesProvider.notifier).refresh(),
          child: const StepVerification(
            status: VerificationStatus(),
            onChanged: _noop,
          ),
        ),
      ),
    );
  }
}
