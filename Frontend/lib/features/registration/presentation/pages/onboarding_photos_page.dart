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
import '../../../../core/utils/photo_trace.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/buttons/icon_button.dart';
import '../../../../core/widgets/layout/responsive_layout.dart';
import '../../../../core/widgets/system_ui/nm_status_bar_style.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../profile_photos/presentation/providers/photo_providers.dart';
import '../../data/services/pending_photo_store.dart';
import '../providers/registration_provider.dart';
import '../widgets/onboarding_scaffold.dart';

/// Step 8 — "Add Photos". **At least one photo is required**: Continue stays
/// disabled until one exists, and there is no "Add Photos Later" escape.
///
/// This screen is where the rule is enforced, because it is the only place
/// that can read the real count — uploaded photos come from
/// `GET /profiles/me/photos` via [PhotosController], not from the draft. The
/// draft gate can only see *staged* photos, so it applies the same rule only
/// for the pre-session caller that opts in (`gatePendingPhotos`); it must not
/// be applied to a restored backend draft, which never carries a gallery.
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

  /// At least one photo, and no upload still in flight. The single rule the
  /// button, its label and [_next] all read, so disabling the button is not
  /// the only thing enforcing it.
  bool get _canContinue => !_busy && _photoCount > 0;

  void _next() {
    if (!_canContinue) return;
    context.go(RouteNames.onboardingAbout);
  }

  Future<void> _add(ImageSource source) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);

    // Cancelled, denied, or failed — the picker has already explained
    // anything the member needs to know, so return to idle silently.
    PhotoTrace.begin('onboarding pick source=${source.name}');
    final file = await _picker.pick(
      context,
      source,
      maxWidth: 2048,
      imageQuality: 95,
    );
    if (file == null) {
      PhotoTrace.step('picker returned null (cancelled/denied/failed)');
      return;
    }
    PhotoTrace.step('image selected', {
      'name': file.name,
      'path': file.path,
      'mime': file.mimeType,
      'bytes': await file.length(),
    });
    if (!mounted) return;

    // The first photo becomes the avatar, which is why it crops to a circle
    // — the same rule the profile photo manager applies.
    final isFirst = _photoCount == 0;
    final cropped = await _cropService.pickAndCrop(
      context: context,
      sourceFile: file,
      shape: isFirst ? CropShape.circle : CropShape.square,
    );
    if (cropped == null) {
      PhotoTrace.step('crop cancelled');
      return;
    }
    PhotoTrace.step('crop+compress done', {
      'name': cropped.name,
      'bytes': await cropped.length(),
    });
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      // This screen sits BEFORE the credential exists: the session is minted
      // two steps later, at OTP (see OnboardingVerifyMobilePage). Uploading
      // here sent `POST /profiles/me/photos` with no bearer token, the
      // backend answered 401, and the member was told their photo failed —
      // logged as `token lookup ← hasToken=false`. So hold the file and let
      // the OTP step upload it through this same controller the moment a
      // session exists. Nothing about the picker, the crop, the endpoint or
      // the upload path changes — only when it runs.
      final session = await photoUploadSession(ref.read);
      if (!session.ok) {
        await _queuePendingPhoto(cropped, isPrimary: isFirst);
        return;
      }

      PhotoTrace.step('session ready — uploading now', {'uid': session.uid});
      await ref
          .read(myPhotosProvider.notifier)
          .upload(cropped, isPrimary: isFirst ? true : null);

      // PhotosController reports failure through the provider's state, not by
      // throwing — AsyncValue.guard absorbs the error. A failed upload here
      // used to look exactly like a successful one: no snackbar, and the
      // "N photos added" line simply stayed at its old count. Read the state
      // the mutation actually published, the same way PhotoManagerSection
      // does.
      final state = ref.read(myPhotosProvider);
      if (state.hasError && mounted) {
        PhotoTrace.fail('onboarding upload', state.error ?? 'unknown');
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.onboardingPhotosFailed)));
      }
    } catch (error, stackTrace) {
      PhotoTrace.fail('onboarding upload', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.onboardingPhotosFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Holds a cropped photo until there is a session to upload it with.
  ///
  /// Writes the bytes to durable storage first and queues *that* path.
  /// Queueing `cropped.path` directly is what lost the photo: the crop screen
  /// returns an `XFile.fromData`, whose io `path` is the empty string, so the
  /// image existed only as bytes in memory and the OTP-step drain reported
  /// `missing=1` without ever calling the backend.
  Future<void> _queuePendingPhoto(
    XFile cropped, {
    required bool isPrimary,
  }) async {
    final String stagedPath;
    try {
      stagedPath = await ref.read(pendingPhotoStoreProvider).stage(cropped);
    } catch (error, stackTrace) {
      // Staging is the only thing standing between the member and a lost
      // photo, so a failure here is worth saying out loud rather than
      // queueing a path that cannot be read back.
      PhotoTrace.fail('staging pending photo', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).onboardingPhotosFailed),
          ));
      }
      return;
    }

    final gallery = ref.read(registrationProvider).photoGallery;
    final updated = isPrimary
        ? gallery.copyWith(primaryPhotoPath: stagedPath)
        : gallery.copyWith(
            galleryPaths: [...gallery.galleryPaths, stagedPath],
          );
    ref.read(registrationProvider.notifier).updatePhotoGallery(updated);
    PhotoTrace.step('queued until sign-in', {
      'isPrimary': isPrimary,
      'pending': updated.pendingPaths.length,
    });
  }

  /// Photos already on the backend plus those waiting for a session — what
  /// the member has added, whichever side of OTP they are on.
  int get _photoCount {
    final uploaded = ref.watch(myPhotosProvider).valueOrNull?.length ?? 0;
    final pending =
        ref.watch(registrationProvider).photoGallery.pendingPaths.length;
    return uploaded + pending;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final count = _photoCount;

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
                        // At least one photo is required, so there is no
                        // "Add Photos Later" escape here any more: with none
                        // added the button stays disabled and the member
                        // stays on this step. `_canContinue` — not just a
                        // greyed-out label — is what `_next` is gated on, so
                        // an in-flight upload cannot slip through either.
                        TextButton(
                          onPressed: _canContinue ? _next : null,
                          child: Text(
                            l10n.commonContinue,
                            style: AppTypography.labelLarge.copyWith(
                              color: _canContinue
                                  ? colors.onSurfaceVariant
                                  : colors.onSurfaceVariant.withValues(
                                      alpha: 0.38,
                                    ),
                            ),
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
