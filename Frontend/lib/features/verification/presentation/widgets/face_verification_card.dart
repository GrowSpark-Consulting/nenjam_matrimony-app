import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/face_verification.dart';
import '../providers/face_verification_providers.dart';

/// Verification Center card for the selfie/Face Match check. Sits above
/// [StepVerification] on `verification_page.dart` — deliberately not inside
/// it, since that widget doubles as registration step 13 and face
/// verification is not part of the registration wizard (see
/// docs/development/selfie-verification-frontend-handoff.md §6.1).
class FaceVerificationCard extends ConsumerWidget {
  const FaceVerificationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(faceVerificationStatusProvider);

    return status.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (state) {
        if (state.blockedReason == FaceBlockedReason.notAvailable) {
          // The feature is off — no entry point to show.
          return const SizedBox.shrink();
        }
        final verified = state.status == FaceVerificationStatus.verified;
        final revoked = state.status == FaceVerificationStatus.revoked;
        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.base),
          child: ListTile(
            leading: Icon(
              Icons.face_rounded,
              color: verified ? AppColors.success : AppColors.primary,
            ),
            title: Text(
              l10n.fieldFaceMatch,
              style: AppTypography.titleSmall,
            ),
            subtitle: Text(
              verified
                  ? l10n.faceVerificationCenterVerified
                  : revoked
                  ? l10n.faceVerificationCenterReverify
                  : l10n.faceVerificationCenterIncomplete,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(RouteNames.faceVerification),
          ),
        );
      },
    );
  }
}
