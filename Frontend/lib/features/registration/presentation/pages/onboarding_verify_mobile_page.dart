
import 'package:flutter/foundation.dart';
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

  /// Why the correct code still did not produce a session — or why the
  /// profile could not be saved once it had. Rendered in the same line the
  /// wrong-code message uses: a member who answered correctly and got nothing
  /// is owed the reason, not a silent walk into an app where nothing they do
  /// will persist.
  String? _sessionError;

  /// Set once the backend has minted a session for this number. A failure
  /// after that point — saving the profile or finalizing it — is retried from
  /// the save onwards; the code and the session exchange are not repeated.
  bool _sessionReady = false;

  /// Whether the last attempt to save the profile failed. Turns the button
  /// into Retry, since the code the member entered is already accepted.
  bool _registrationFailed = false;

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
    // First, before anything else: one attempt at a time. Without this a
    // double tap on Retry — or the code box re-submitting — would start two
    // registrations and send every section twice.
    if (_verifying) return;

    // A session already exists — the code was accepted and the account
    // provisioned on an earlier attempt — so only the save that failed after
    // it is retried.
    if (_sessionReady) return _completeRegistration();

    final l10n = AppLocalizations.of(context);
    final verifier = ref.read(otpVerifierProvider);
    if (_otp.length != verifier.codeLength) return;
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
    _sessionReady = true;

    await _completeRegistration();
  }

  /// Sends the profile, finalizes it, and only then lets the member in.
  ///
  /// The order is the contract: **save → finalize → mark complete → Discover**,
  /// and any failure stops the sequence with the member still on this screen.
  ///
  /// It used to be the opposite. `onboardingCompleted` was written before
  /// anything was sent, the save swallowed its own errors, finalize ran
  /// "quietly", and the member was navigated to Discover regardless. So one
  /// rejected section — a 400 on religion, earlier a 400 on location — let
  /// the member into the app with an unfinalized profile: hidden from every
  /// feed, shown an empty one of their own, and sent back to an earlier step
  /// on their next login. A local flag claimed onboarding had finished while
  /// the backend held a half-written profile.
  ///
  /// Retrying is safe. Nothing the member entered is touched on failure; each
  /// section PATCH is a merge of the same values; finalize is idempotent; and
  /// photos that already uploaded leave the pending queue, so a retry sends
  /// only what did not.
  Future<void> _completeRegistration() async {
    final l10n = AppLocalizations.of(context);
    if (!_verifying) {
      setState(() {
        _verifying = true;
        _registrationFailed = false;
        _sessionError = null;
      });
    }

    // Cleared first so the flag can only ever describe the attempt that just
    // finished. A build that wrote it early may have left it set; if this
    // attempt fails, it must not keep claiming onboarding is done.
    await storageService.setOnboardingCompleted(false);

    final notifier = ref.read(registrationProvider.notifier);

    // 1. Save every section. Now that a session exists, the answers gathered
    //    along the way go out with a credential attached, so the backend can
    //    provision the internal User row and materialize the profile.
    try {
      await notifier.flushOnboardingToBackend();
    } catch (error) {
      return _registrationFailedWith(l10n, stage: 'save', error: error);
    }

    // 2. Upload any photo picked on the Add Photos step, which could not be
    //    sent then: that screen runs before this one, with no credential to
    //    attach. Non-fatal by design — a photo is not required to finalize,
    //    the queue keeps anything that did not upload, and the member is told.
    await _uploadPendingPhotos();

    // 3. Finalize — what marks the registration COMPLETE on the backend
    //    (`registration_steps.is_complete`, completion %, the welcome email).
    try {
      await notifier.finalizeToBackend();
    } catch (error) {
      return _registrationFailedWith(l10n, stage: 'finalize', error: error);
    }

    // 4. Only now is onboarding finished. The flag is written after the
    //    backend has confirmed it, never before, and the number stops being
    //    "pending" at the same moment.
    await storageService.setOnboardingCompleted(true);
    await storageService.clearPendingPhone();
    if (!mounted) return;
    AuthTrace.navigate(RouteNames.discover, reason: 'onboarding finalized');
    context.go(RouteNames.discover);
  }

  /// Keeps the member on this screen with a reason and a Retry.
  ///
  /// The original error is kept for diagnosis — logged in debug builds — but
  /// never shown: a backend validation message is not something a member can
  /// act on, and "your number is verified, your profile did not save, try
  /// again" is. The pending number and the local draft are both left as they
  /// are, so a retry, a relaunch or the next login all still have them.
  void _registrationFailedWith(
    AppLocalizations l10n, {
    required String stage,
    required Object error,
  }) {
    if (kDebugMode) {
      debugPrint('[ONBOARDING] registration $stage failed: $error');
    }
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _registrationFailed = true;
      _sessionError = l10n.onboardingVerifyMobileRegistrationFailed;
    });
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
                    // After a failed save the code is already accepted, so
                    // the one action left is to try the save again.
                    label: _registrationFailed
                        ? l10n.commonRetry
                        : l10n.authVerifyAndContinue,
                    icon: _registrationFailed
                        ? Icons.refresh_rounded
                        : Icons.arrow_forward_rounded,
                    isLoading: _verifying,
                    onPressed: _registrationFailed || _otp.length == length
                        ? _verify
                        : null,
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
