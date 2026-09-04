
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/auth_trace.dart';
import '../../../../core/utils/photo_trace.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/buttons/icon_button.dart';
import '../../../../core/widgets/inputs/otp_input.dart';
import '../../../../core/widgets/layout/responsive_layout.dart';
import '../../../../core/widgets/system_ui/nm_status_bar_style.dart';
import '../../../authentication/domain/services/dummy_otp_session.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../authentication/domain/services/otp_verifier.dart';
import '../../../profile_photos/presentation/providers/photo_providers.dart';
import '../../data/services/pending_photo_store.dart';
import '../../domain/services/pending_photo_uploader.dart';
import '../providers/registration_provider.dart';
import '../widgets/onboarding_scaffold.dart';

/// Step 10 — "Verify Mobile Number", the last screen before Discover.
///
/// Verification goes through [OtpVerifier], which is currently wired to
/// [MockOtpVerifier]: **no SMS is sent and no OTP provider is called.** The
/// screen, the flow position and the state it writes are all real, so
/// swapping the provider override turns real verification on without
/// touching this file.
///
/// The production phone-auth stack is untouched and still drives the sign-up
/// and login phone screens.
class OnboardingVerifyMobilePage extends ConsumerStatefulWidget {
  const OnboardingVerifyMobilePage({super.key});

  @override
  ConsumerState<OnboardingVerifyMobilePage> createState() =>
      _OnboardingVerifyMobilePageState();
}

class _OnboardingVerifyMobilePageState
    extends ConsumerState<OnboardingVerifyMobilePage> {
  String _otp = '';
  String _phone = '';
  bool _verifying = false;
  bool _wrongCode = false;

  /// Why the correct code still did not produce a session. Rendered in the
  /// same line the wrong-code message uses — a member who answered correctly
  /// and got nothing is owed the reason, not a silent walk into an app where
  /// nothing they do will persist.
  String? _sessionError;

  @override
  void initState() {
    super.initState();
    _phone = storageService.pendingPhone ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_phone.isNotEmpty) ref.read(otpVerifierProvider).send(_phone);
    });
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.onboardingAbout);
    }
  }

  /// Editing the number means verifying the new one, which the Email +
  /// Mobile step already owns — so Edit returns there rather than growing a
  /// second number field here.
  void _edit() => context.go(RouteNames.onboardingContact);

  /// Uploads the photos onboarding held back, oldest first, so the primary
  /// one lands first and becomes the avatar.
  ///
  /// Still non-fatal, for the same reason finalize is: the member has passed
  /// OTP and is one step from the app, so a photo that fails here must not
  /// strand them on this screen. What changed is that it is no longer
  /// *silent*. This used to clear the whole queue unconditionally and skip a
  /// missing file without a word, so a member who added a photo could finish
  /// signup with none and never be told — the photo was simply gone.
  ///
  /// Now the queue keeps whatever did not upload (see [drainPendingPhotos]),
  /// so a later pass retries it, and each outcome gets one message.
  Future<void> _uploadPendingPhotos() async {
    final gallery = ref.read(registrationProvider).photoGallery;
    if (gallery.pendingPaths.isEmpty) return;

    PhotoTrace.begin(
      'onboarding pending upload count=${gallery.pendingPaths.length}',
    );
    final photos = ref.read(myPhotosProvider.notifier);

    final result = await drainPendingPhotos(
      gallery: gallery,
      store: ref.read(pendingPhotoStoreProvider),
      upload: (file, {required bool isPrimary}) async {
        // PhotosController reports failure through the provider's state
        // rather than by throwing — AsyncValue.guard absorbs the error — so
        // the published state is what says whether this worked.
        PhotoTrace.step('upload started', {
          'bytes': await file.length(),
          'isPrimary': isPrimary,
        });
        await photos.upload(file, isPrimary: isPrimary ? true : null);
        final state = ref.read(myPhotosProvider);
        if (state.hasError) {
          PhotoTrace.fail('pending upload', state.error ?? 'unknown');
          return false;
        }
        // PhotosController re-reads GET /profiles/me/photos after the POST, so
        // this count is the backend's own answer, not the POST body's.
        PhotoTrace.step('upload completed', {
          'fetchedPhotos': state.valueOrNull?.length,
        });
        return true;
      },
    );

    // Retain exactly what still needs doing. Anything that uploaded is gone
    // from here; anything missing is dropped because retrying a file that no
    // longer exists can only fail again.
    ref
        .read(registrationProvider.notifier)
        .updatePhotoGallery(result.remaining);
    PhotoTrace.step('pending upload outcome', {
      'queuedBefore': gallery.pendingPaths.length,
      'uploaded': result.uploaded,
      'failed': result.failed,
      'missing': result.missing,
      'stillQueued': result.remaining.pendingPaths.length,
    });
    PhotoTrace.end('onboarding pending upload');

    if (!mounted) return;
    // One message, not one per photo — the member is mid-signup and a stack
    // of snackbars would bury the step they are on. A failure is the more
    // actionable of the two, so it wins when both happened.
    final l10n = AppLocalizations.of(context);
    final String? message = result.hasFailures
        ? l10n.onboardingPhotosPendingFailed
        : result.hasMissing
            ? l10n.onboardingPhotosPendingMissing
            : null;
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _verify() async {
    final l10n = AppLocalizations.of(context);
    final verifier = ref.read(otpVerifierProvider);
    if (_otp.length != verifier.codeLength || _verifying) return;
    setState(() {
      _verifying = true;
      _wrongCode = false;
      _sessionError = null;
    });

    final ok = await verifier.verify(_otp);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _verifying = false;
        _wrongCode = true;
      });
      return;
    }

    // Reaching here means the verifier said yes. With real phone auth that is
    // FirebasePhoneOtpVerifier, so a Firebase session already exists: the
    // credential either signed the member in or was linked to the account
    // they already had, and the router guard sees a genuine user from here.
    //
    // With the dummy OTP there is no credential to exchange, so the backend
    // mints one: `POST /auth/dummy-otp/session` creates (or reuses) the real
    // Firebase Auth account and the internal `users` row for this number, and
    // returns a custom token this signs in with. That is what a pass has to
    // produce. It used to open a LocalAuthSession instead — a device-local
    // marker with an `X-Dev-Auth-Phone` header behind it — and a member could
    // finish signup with no Firebase account and no `users` row at all: the
    // flush below sent nothing, no `user_profiles` row was ever written, and
    // every screen afterwards answered 401.
    final phone = storageService.pendingPhone;
    if (phone == null || phone.isEmpty) {
      setState(() {
        _verifying = false;
        _sessionError = l10n.onboardingVerifyMobileSessionFailed;
      });
      return;
    }
    try {
      await ref.read(dummyOtpSessionStarterProvider).start(
            phoneE164: phone,
            // Carried so an email signup lands on this same single account
            // rather than a second one.
            email: storageService.pendingEmail,
          );
    } on DummyOtpSessionException catch (error) {
      if (!mounted) return;
      // No session was opened, so there is nothing to flush and nothing to
      // finalize. Staying here with the reason is the honest outcome — the
      // alternative is the exact silent half-signup this replaced.
      AuthTrace.firebaseAuth(channel: 'dummy-otp', success: false);
      setState(() {
        _verifying = false;
        _sessionError = error.message;
      });
      return;
    }
    if (!mounted) return;
    AuthTrace.firebaseAuth(channel: 'dummy-otp', success: true);

    // Still written for the router's own local-completion bridge, and cleared
    // on sign-out along with everything else.
    await storageService.setOnboardingCompleted(true);

    // Now that a session exists, the answers gathered along the way are sent
    // with a credential attached, so the backend can provision the internal
    // User row and materialize the profile.
    final notifier = ref.read(registrationProvider.notifier);
    await notifier.flushOnboardingToBackend();

    // ...including any photo picked on the Add Photos step, which could not
    // be uploaded when it was chosen: that screen runs before this one, so
    // there was no credential to attach and the POST came back 401. Same
    // controller, same repository, same endpoint Edit Profile uses — only
    // now, with a session.
    await _uploadPendingPhotos();

    // ...and then finalize, which is what marks the registration COMPLETE.
    //
    // Onboarding never called this. The per-step PATCHes already materialize
    // `user_profiles` on their own (syncMatchableFromDraft runs on every save),
    // so a profile did exist — but `registration_steps.is_complete` stayed
    // false, `profile_complete_pct` stayed 0, and the welcome email never
    // went out, for every member who signed up through this flow.
    //
    // It could not have been called before this commit: finalize's location
    // contract demanded `area`, `pinCode` and `nativePlace`, which no
    // onboarding screen collects, so it would have thrown BadRequestException
    // for every member. That contract now asks for country/state/city, which
    // is what the flow actually gathers.
    //
    // Deliberately non-fatal. The member has answered everything, their
    // profile row already exists, and the OTP they just passed is the last
    // thing standing between them and the app — a failed bookkeeping call
    // must not strand them on this screen. finalize is idempotent, and
    // PostAuthDestination re-runs the same check on the next launch.
    await notifier.finalizeOnboardingQuietly();

    // Onboarding is finished. The number stops being "pending" the moment
    // it is verified.
    await storageService.clearPendingPhone();
    if (!mounted) return;
    AuthTrace.navigate(RouteNames.discover, reason: 'onboarding finalized');
    context.go(RouteNames.discover);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final length = ref.watch(otpVerifierProvider).codeLength;

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
                          const Center(
                            child: OnboardingCrest(
                              icon: Icons.verified_user_rounded,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            l10n.onboardingVerifyMobileHeadline,
                            textAlign: TextAlign.center,
                            style: AppTypography.headlineSmall.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            l10n.onboardingVerifyMobileSentTo,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMedium
                                .copyWith(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                _phone,
                                style: AppTypography.titleMedium.copyWith(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextButton(
                                onPressed: _verifying ? null : _edit,
                                child: Text(l10n.onboardingVerifyMobileEdit),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          NmOtpInput(
                            length: length,
                            onCompleted: (value) {
                              _otp = value;
                              _verify();
                            },
                            onChanged: (value) => setState(() {
                              _otp = value;
                              _wrongCode = false;
                              _sessionError = null;
                            }),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            _sessionError ??
                                (_wrongCode
                                    ? l10n.authInvalidOtp
                                    : l10n.onboardingVerifyMobileEnter),
                            textAlign: TextAlign.center,
                            style: AppTypography.labelSmall.copyWith(
                              color: _wrongCode || _sessionError != null
                                  ? colors.error
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                OnboardingFooter(
                  child: NmGradientButton(
                    label: l10n.authVerifyAndContinue,
                    icon: Icons.arrow_forward_rounded,
                    isLoading: _verifying,
                    onPressed: _otp.length == length ? _verify : null,
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
