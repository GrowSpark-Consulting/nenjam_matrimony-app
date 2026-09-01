import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/media/attachment_picker.dart';
import '../../../../core/services/media/crop_service.dart';
import '../../../../core/services/media/photo_crop_screen.dart' show CropShape;
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/buttons/icon_button.dart';
import '../../../../core/widgets/layout/responsive_layout.dart';
import '../../../../core/widgets/system_ui/nm_status_bar_style.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../profile_photos/presentation/providers/photo_providers.dart';
import '../widgets/onboarding_scaffold.dart';

/// Step 8 — "Add Photos". Optional by design: the reference offers an
/// explicit "Add Photos Later", and no backend rule requires a photo before
/// a profile exists.
///
/// Owns no photo storage of its own. Picking, cropping and uploading all go
/// through the services the profile photo manager already uses
/// ([AttachmentPicker], [CropService], [PhotosController]), so a photo added
/// here is the same resource, on the same S3 bucket, that Edit Profile shows.
class OnboardingPhotosPage extends ConsumerStatefulWidget {
  const OnboardingPhotosPage({super.key});

  @override
  ConsumerState<OnboardingPhotosPage> createState() =>
      _OnboardingPhotosPageState();
}

class _OnboardingPhotosPageState extends ConsumerState<OnboardingPhotosPage> {
  final _picker = AttachmentPicker();
  final _cropService = const CropService();
  bool _busy = false;

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.onboardingIncome);
    }
  }

  void _next() => context.go(RouteNames.onboardingAbout);

  Future<void> _add(ImageSource source) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);

    // Cancelled, denied, or failed — the picker has already explained
    // anything the member needs to know, so return to idle silently.
    final file = await _picker.pick(
      context,
      source,
      maxWidth: 2048,
      imageQuality: 95,
    );
    if (file == null || !mounted) return;

    // The first photo becomes the avatar, which is why it crops to a circle
    // — the same rule the profile photo manager applies.
    final isFirst = (ref.read(myPhotosProvider).valueOrNull?.length ?? 0) == 0;
    final cropped = await _cropService.pickAndCrop(
      context: context,
      sourceFile: file,
      shape: isFirst ? CropShape.circle : CropShape.square,
    );
    if (cropped == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(myPhotosProvider.notifier)
          .upload(cropped, isPrimary: isFirst ? true : null);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.onboardingPhotosFailed)));
    }
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final count = ref.watch(myPhotosProvider).valueOrNull?.length ?? 0;

    return NmPageStatusBar(
      background: theme.scaffoldBackgroundColor,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: NmIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: l10n.registrationBack,
                      onPressed: _back,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    child: NmContentConstraint(
                      maxWidth: OnboardingScaffold.contentMaxWidth,
                      child: Column(
                        children: [
                          const SizedBox(height: AppSpacing.lg),
                          _PhotoCrest(count: count),
                          const SizedBox(height: AppSpacing.xl),
                          Text(
                            l10n.onboardingPhotosHeadline,
                            textAlign: TextAlign.center,
                            style: AppTypography.headlineSmall.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            l10n.onboardingPhotosSubtitle,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall
                                .copyWith(color: colors.onSurfaceVariant),
                          ),
                          if (count > 0) ...[
                            const SizedBox(height: AppSpacing.base),
                            Text(
                              count == 1
                                  ? l10n.onboardingPhotosAddedOne
                                  : l10n.onboardingPhotosAddedMany('$count'),
                              style: AppTypography.labelLarge
                                  .copyWith(color: colors.primary),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.base,
                  ),
                  child: NmContentConstraint(
                    maxWidth: OnboardingScaffold.contentMaxWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        NmGradientButton(
                          label: l10n.onboardingPhotosGallery,
                          icon: Icons.photo_library_rounded,
                          isLoading: _busy,
                          onPressed: () => _add(ImageSource.gallery),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextButton.icon(
                          onPressed:
                              _busy ? null : () => _add(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_rounded,
                              size: AppSpacing.lg),
                          label: Text(l10n.onboardingPhotosCamera),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        // Continuing is never blocked: photos are optional,
                        // and a member with one already added reads this as
                        // "done" rather than "skip".
                        TextButton(
                          onPressed: _busy ? null : _next,
                          child: Text(
                            count > 0
                                ? l10n.commonContinue
                                : l10n.onboardingPhotosLater,
                            style: AppTypography.labelLarge
                                .copyWith(color: colors.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed avatar ring with an add badge — the reference's placeholder, drawn
/// from theme tokens so it re-tints rather than needing artwork.
class _PhotoCrest extends StatelessWidget {
  final int count;

  const _PhotoCrest({required this.count});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: AppSpacing.xl7,
      height: AppSpacing.xl7,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: AppSpacing.xl7,
            height: AppSpacing.xl7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primaryContainer,
              border: Border.all(color: colors.outline),
            ),
            child: Icon(
              count > 0 ? Icons.check_rounded : Icons.person_rounded,
              size: AppSpacing.xl3,
              color: colors.primary,
            ),
          ),
          PositionedDirectional(
            end: 0,
            bottom: AppSpacing.xs,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary,
              ),
              child: Icon(
                Icons.add_rounded,
                size: AppSpacing.base,
                color: colors.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
