import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../profile_photos/presentation/widgets/photo_manager_section.dart';
import 'registration_helper_tip.dart';
import 'step_body.dart';

/// Step 11 — Photo Upload. Backed by the real PhotoController: photos are
/// uploaded to S3 and attached to the signed-in user immediately (they're an
/// independent resource, not part of the wizard draft), so they persist and
/// show up on the profile dashboard and edit-profile screens right away.
class StepPhotos extends ConsumerWidget {
  /// See [StepBody.scrollable].
  final bool scrollable;

  const StepPhotos({super.key, this.scrollable = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return StepBody(
      scrollable: scrollable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.registrationWizardPhotosHeadline,
            style: AppTypography.headlineSmall
                .copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.registrationWizardPhotosHook,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipPhotos),
          const SizedBox(height: 24),
          const PhotoManagerSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
