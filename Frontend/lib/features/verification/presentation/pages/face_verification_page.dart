import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/widgets/buttons/icon_button.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/sheets/app_sheets.dart';
import '../../../profile_photos/presentation/providers/photo_providers.dart';
import '../../../profile_photos/presentation/providers/primary_photo_updater.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/face_verification.dart';
import '../providers/face_verification_providers.dart';

/// "Account on hold" — the mandatory selfie-verification screen a member
/// with an unresolved required verification lands on after OTP, before
/// Discover. See docs/development/selfie-verification-frontend-handoff.md
/// §6.2 for the copy this implements.
class FaceVerificationPage extends ConsumerWidget {
  const FaceVerificationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(faceVerificationFlowProvider);
    final l10n = AppLocalizations.of(context);

    ref.listen(faceVerificationFlowProvider, (previous, next) {
      if (next.phase == FaceVerificationFlowPhase.verified) {
        ref.invalidate(faceVerificationStatusProvider);
        if (context.mounted) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(RouteNames.discover);
          }
        }
      }
    });

    return PopScope(
      // Back must not reach Discover through the back stack while
      // verification is still required — see app_router.dart's redirect,
      // which is the actual gate; this only stops an in-app back gesture
      // from feeling like it worked when it can't.
      canPop: flow.phase != FaceVerificationFlowPhase.capturing &&
          flow.phase != FaceVerificationFlowPhase.completing,
      child: Scaffold(
        backgroundColor: AppColors.surfaceLight,
        body: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: AppSpacing.pagePadding,
                child: _FaceVerificationBody(flow: flow, l10n: l10n),
              ),
              // Overlaid rather than placed in the Column so it costs the
              // body no vertical space and the centered header composition
              // stays exactly as it lays out without it.
              PositionedDirectional(
                top: 0,
                start: 0,
                child: _FaceVerificationBackButton(flow: flow, l10n: l10n),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top-left back affordance. Shown only when there is somewhere valid to go
/// back to — i.e. the page was pushed (from the Verification Center), not
/// landed on as the post-OTP gate, where popping would otherwise expose
/// Discover behind the still-unsatisfied verification requirement.
///
/// Deliberately defers to the same `canPop`/`pop` pair the page's [PopScope]
/// and the system back gesture already use, so this adds an affordance, not
/// a second navigation mechanism.
class _FaceVerificationBackButton extends StatelessWidget {
  const _FaceVerificationBackButton({required this.flow, required this.l10n});

  final FaceVerificationFlowState flow;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    // Navigator, not go_router's context.canPop(): this runs during build,
    // and the go_router extension asserts when no GoRouter is in the tree.
    // Both read the same back stack, so the decision is identical.
    if (!Navigator.of(context).canPop()) return const SizedBox.shrink();

    // Same condition as the page's PopScope: an attempt in flight must not
    // be abandoned mid-capture.
    final locked = flow.phase == FaceVerificationFlowPhase.capturing ||
        flow.phase == FaceVerificationFlowPhase.completing;

    return NmIconButton(
      icon: Icons.arrow_back_rounded,
      tooltip: l10n.registrationBack,
      onPressed: locked ? null : () => Navigator.of(context).maybePop(),
    );
  }
}

class _FaceVerificationBody extends ConsumerStatefulWidget {
  const _FaceVerificationBody({required this.flow, required this.l10n});

  final FaceVerificationFlowState flow;
  final AppLocalizations l10n;

  @override
  ConsumerState<_FaceVerificationBody> createState() =>
      _FaceVerificationBodyState();
}

class _FaceVerificationBodyState extends ConsumerState<_FaceVerificationBody> {
  bool _consentChecked = false;

  /// The full, unabridged consent/privacy wording. The page shows the
  /// shortened form so it fits one viewport; this keeps the complete text
  /// reachable without reintroducing page scrolling.
  Future<void> _showConsentDetail(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return AppSheets.show<void>(
      context,
      title: l10n.faceVerificationTitle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.base,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.faceVerificationConsent,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.faceVerificationPrivacyNote,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final flow = widget.flow;

    final busy = flow.phase == FaceVerificationFlowPhase.checkingPermission ||
        flow.phase == FaceVerificationFlowPhase.creatingSession ||
        flow.phase == FaceVerificationFlowPhase.capturing ||
        flow.phase == FaceVerificationFlowPhase.completing;

    // A photo update in flight must not race a liveness attempt: the backend
    // matches against whichever photo is primary at capture time, so starting
    // one mid-update could compare against the photo being replaced. Covers
    // the pick/crop legs too, not just the upload request.
    final photoBusy = ref.watch(primaryPhotoUpdateInProgressProvider) ||
        ref.watch(myPhotosProvider).isLoading;

    // The mismatch/failure card describes the outcome of a *finished*
    // attempt. `idle` is also the phase a member lands on when they first
    // open this page, so anything error-shaped stays hidden until the flow
    // has actually run — see the phase list in
    // face_verification_providers.dart.
    final resultCard = switch (flow.phase) {
      FaceVerificationFlowPhase.blocked =>
        _BlockedMessage(reason: flow.blockedReason, l10n: l10n),
      FaceVerificationFlowPhase.failed => _FailedMessage(flow: flow, l10n: l10n),
      FaceVerificationFlowPhase.permissionDenied => _PermissionDeniedMessage(
        permanentlyDenied: flow.permanentlyDenied,
        l10n: l10n,
      ),
      FaceVerificationFlowPhase.networkError => _NetworkErrorMessage(l10n: l10n),
      _ => null,
    };

    // One viewport, no scrolling: the header, information and CTA take their
    // intrinsic height, and the illustration absorbs whatever is left. It is
    // the only elastic child, so on a short screen — or once a result card
    // appears — it gives up its own height instead of overflowing.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.faceVerificationTitle,
          textAlign: TextAlign.center,
          style: AppTypography.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.faceVerificationExplanation,
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Expanded so the illustration surrenders space on a short screen
        // instead of overflowing. The Align is load-bearing: Expanded hands
        // down a *tight* height, which would override the card's own
        // maxHeight cap and let it grow to half a tall phone's screen.
        // Align relaxes that to a loose constraint so the cap applies.
        const Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: _FaceVerificationIllustration(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (resultCard != null) ...[
          resultCard,
          const SizedBox(height: AppSpacing.md),
        ],
        if (flow.phase != FaceVerificationFlowPhase.blocked) ...[
          // The consent line is also the privacy explanation (AWS-only use,
          // nothing stored, result kept). The short form keeps the page to
          // one viewport; "Learn more" opens the full wording.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: AppSpacing.xl,
                height: AppSpacing.xl,
                child: Checkbox(
                  value: _consentChecked,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: busy
                      ? null
                      : (value) =>
                          setState(() => _consentChecked = value ?? false),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.faceVerificationConsentShort,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    // The full wording stays one tap away rather than
                    // costing ~190dp of a 568dp-tall screen.
                    GestureDetector(
                      onTap: () => _showConsentDetail(context, l10n),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
                        child: Text(
                          l10n.faceVerificationConsentLearnMore,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        NmPrimaryButton(
          label: busy
              ? l10n.faceVerificationVerifying
              : l10n.faceVerificationCta,
          isLoading: busy,
          onPressed:
              flow.phase == FaceVerificationFlowPhase.blocked ||
                  busy ||
                  photoBusy ||
                  !_consentChecked
              ? null
              : () => ref
                    .read(faceVerificationFlowProvider.notifier)
                    .startVerification(),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.faceVerificationPrivacyNote,
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Ceiling for the illustration card. The old [AspectRatio]-based version
/// grew with page width, which is what pushed the CTA off a normal phone
/// screen; this keeps it a medium-height band at every width. There is
/// deliberately no matching floor: the illustration is the page's only
/// elastic child, so it has to be able to give up height down to nothing
/// on a short viewport rather than force a RenderFlex overflow.
const double _illustrationMaxHeight = 200;

class _FaceVerificationIllustration extends StatelessWidget {
  const _FaceVerificationIllustration();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fill the slot the Column granted, but never past the cap — under
        // the loose constraint an Align passes down, sizing has to be
        // explicit or the card would shrink to just its icon.
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight.clamp(0.0, _illustrationMaxHeight)
            : _illustrationMaxHeight;
        return Container(
          width: double.infinity,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(24),
          ),
          // Scales with the band actually granted, so the icon never
          // leaves a large empty margin inside the card. FittedBox keeps a
          // collapsed card from clipping it.
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Icon(
                Icons.face_retouching_natural_rounded,
                size: (height * 0.5).clamp(24.0, 96.0),
                color: AppColors.primary,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BlockedMessage extends StatelessWidget {
  const _BlockedMessage({required this.reason, required this.l10n});

  final FaceBlockedReason? reason;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final message = switch (reason) {
      FaceBlockedReason.alreadyVerified => l10n.faceVerificationAlreadyVerified,
      FaceBlockedReason.noPrimaryPhoto => l10n.faceVerificationNoPrimaryPhoto,
      FaceBlockedReason.unsupportedPhoto =>
        l10n.faceVerificationUnsupportedPhoto,
      FaceBlockedReason.attemptLimit => l10n.faceVerificationAttemptLimit,
      _ => l10n.faceVerificationUnavailable,
    };
    final offersPhotoUpdate = reason == FaceBlockedReason.noPrimaryPhoto ||
        reason == FaceBlockedReason.unsupportedPhoto;
    return _InlineMessage(
      message: message,
      color: AppColors.textSecondary,
      background: AppColors.primarySurface,
      actionLabel: offersPhotoUpdate ? l10n.faceVerificationUpdatePhoto : null,
      updatesPrimaryPhoto: offersPhotoUpdate,
    );
  }
}

class _FailedMessage extends ConsumerWidget {
  const _FailedMessage({required this.flow, required this.l10n});

  final FaceVerificationFlowState flow;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reason = flow.failureReason;
    final message = switch (reason) {
      FaceVerificationFailureReason.failedLiveness =>
        l10n.faceVerificationFailedLiveness,
      FaceVerificationFailureReason.failedMatch =>
        l10n.faceVerificationFailedMatch,
      FaceVerificationFailureReason.noFaceInPhoto =>
        l10n.faceVerificationNoFaceInPhoto,
      FaceVerificationFailureReason.multipleFacesInPhoto =>
        l10n.faceVerificationMultipleFaces,
      FaceVerificationFailureReason.unsupportedPhoto =>
        l10n.faceVerificationUnsupportedPhoto,
      FaceVerificationFailureReason.noReferenceImage =>
        l10n.faceVerificationNoPrimaryPhoto,
      FaceVerificationFailureReason.photoChanged =>
        l10n.faceVerificationPhotoChanged,
      FaceVerificationFailureReason.expired =>
        l10n.faceVerificationExpired,
      FaceVerificationFailureReason.cancelled =>
        l10n.faceVerificationCancelled,
      _ => l10n.faceVerificationFailedGeneric,
    };
    return _InlineMessage(
      message: message,
      color: AppColors.error,
      background: AppColors.errorLight,
      actionLabel: reason?.suggestsPhotoUpdate == true
          ? l10n.faceVerificationUpdatePhoto
          : null,
      updatesPrimaryPhoto: reason?.suggestsPhotoUpdate == true,
    );
  }
}

class _PermissionDeniedMessage extends ConsumerWidget {
  const _PermissionDeniedMessage({
    required this.permanentlyDenied,
    required this.l10n,
  });

  final bool permanentlyDenied;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _InlineMessage(
      message: l10n.faceVerificationCameraPermissionDenied,
      color: AppColors.error,
      background: AppColors.errorLight,
      actionLabel: permanentlyDenied ? l10n.faceVerificationOpenSettings : null,
      onAction: permanentlyDenied
          ? () => ref.read(appPermissionServiceProvider).openSettings()
          : null,
    );
  }
}

class _NetworkErrorMessage extends StatelessWidget {
  const _NetworkErrorMessage({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return _InlineMessage(
      message: l10n.faceVerificationNetworkError,
      color: AppColors.error,
      background: AppColors.errorLight,
    );
  }
}

class _InlineMessage extends ConsumerStatefulWidget {
  const _InlineMessage({
    required this.message,
    required this.color,
    required this.background,
    this.actionLabel,
    this.onAction,
    this.updatesPrimaryPhoto = false,
  });

  final String message;
  final Color color;
  final Color background;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// When true the action runs the in-place "update main photo" flow instead
  /// of invoking [onAction]. Deliberately stays on this page: navigating to
  /// the photo editor from here would leave the Face Verification gate and,
  /// from the post-OTP landing, re-enter onboarding/OTP routing.
  final bool updatesPrimaryPhoto;

  @override
  ConsumerState<_InlineMessage> createState() => _InlineMessageState();
}

class _InlineMessageState extends ConsumerState<_InlineMessage> {
  bool _uploading = false;

  Future<void> _updatePrimaryPhoto() async {
    // Local re-entrancy guard on top of PhotosController's own `_busy`: this
    // one also covers the pick/crop leg, before any upload starts.
    if (_uploading) return;
    setState(() => _uploading = true);
    ref.read(primaryPhotoUpdateInProgressProvider.notifier).set(running: true);

    final l10n = AppLocalizations.of(context);
    try {
      final result = await ref
          .read(primaryPhotoUpdaterProvider)
          .pickAndUpload(context: context);
      if (!mounted) return;

      if (result.isSuccess) {
        // Clear only the previous attempt's result, returning the page to its
        // initial state so "Verify with Selfie" is available again. This does
        // NOT mark the member verified and does not start liveness — the next
        // attempt is theirs to trigger.
        ref.read(faceVerificationFlowProvider.notifier).reset();
        return;
      }
      if (result.isFailure) {
        _snack(result.message ?? l10n.authGenericError);
      }
    } finally {
      ref
          .read(primaryPhotoUpdateInProgressProvider.notifier)
          .set(running: false);
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.actionLabel;
    final hasAction =
        label != null && (widget.updatesPrimaryPhoto || widget.onAction != null);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: widget.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.message,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: widget.color),
          ),
          if (hasAction) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _uploading
                  ? null
                  : widget.updatesPrimaryPhoto
                  ? _updatePrimaryPhoto
                  : widget.onAction,
              child: _uploading
                  ? const SizedBox(
                      height: AppSpacing.base,
                      width: AppSpacing.base,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(label),
            ),
          ],
        ],
      ),
    );
  }
}
