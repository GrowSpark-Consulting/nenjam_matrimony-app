import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/auth_error_mapper.dart';
import '../../../../core/services/media/attachment_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/cards/verification_status_card.dart';
import '../../../../core/widgets/inputs/otp_input.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../authentication/data/models/auth_user.dart';
import '../../../authentication/presentation/controllers/phone_auth_controller.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../verification/domain/models/verification_document.dart';
import '../../../verification/presentation/providers/verification_providers.dart';
import '../../domain/models/profile_draft.dart';
import 'registration_helper_tip.dart';

/// Max document/photo evidence size accepted for income/asset/Aadhaar/NRI
/// uploads. Generous relative to profile photos (which downscale to
/// `maxWidth: 1080`) since these need to stay legible.
const int _kMaxDocumentBytes = 8 * 1024 * 1024;

/// Step 13 — Verification.
///
/// AI Face Selfie Verification has been intentionally removed from this
/// screen (no camera capture, no registration-specific "faceVerified" UI
/// or demo toggle here anymore). [VerificationStatus.faceVerified] itself
/// is NOT deleted from the model — features/profile's NmVerificationCard
/// ("Face Match" tile) and features/verification's standalone VerificationPage
/// still read/display it, so removing the field would break those. This
/// step simply no longer writes to it.
///
/// Mobile and Email reflect the real, already-verified Firebase auth
/// session (nearly always true by the time a user reaches this step, since
/// both gates run earlier in signup) with a real fallback OTP/email-check
/// flow for the rare case they aren't. Income, Asset, Government
/// ID/Aadhaar, and NRI are real document uploads through the shared
/// [verificationStatusesProvider] — uploading a document only ever reaches
/// "Pending Review" locally; "Verified" only ever arrives from the backend.
class StepVerification extends ConsumerStatefulWidget {
  final VerificationStatus status;
  final void Function(VerificationStatus) onChanged;

  const StepVerification({
    super.key,
    required this.status,
    required this.onChanged,
  });

  @override
  ConsumerState<StepVerification> createState() => _StepVerificationState();
}

class _StepVerificationState extends ConsumerState<StepVerification> {
  final _attachmentPicker = AttachmentPicker();
  final Set<VerificationDocumentType> _pickingInProgress = {};
  bool _mobileSheetOpen = false;
  bool _emailSheetOpen = false;

  // ─── Mirroring real signals into ProfileDraft.verificationStatus ─────
  //
  // This screen never renders from `widget.status` for mobile/email/
  // document cards (those always read the live provider directly, see
  // `build()`); `widget.status`/`onChanged` exist purely so the profile
  // completion aggregator and the review screen — which only see
  // ProfileDraft, not these providers — stay in sync. Only ever flips a
  // flag false -> true, and only in response to a real VERIFIED signal.
  void _syncMirrors() {
    final authUser = ref.read(authRepositoryProvider).currentAuthUser;
    final docs = ref.read(verificationStatusesProvider).valueOrNull ?? const {};
    bool docVerified(VerificationDocumentType t) => docs[t]?.isVerified ?? false;

    var next = widget.status;
    var changed = false;
    void apply(bool shouldBe, bool already, VerificationStatus Function() next_) {
      if (shouldBe && !already) {
        next = next_();
        changed = true;
      }
    }

    apply(authUser?.phoneVerified ?? false, next.mobileVerified,
        () => next.copyWith(mobileVerified: true));
    apply(authUser?.emailVerified ?? false, next.emailVerified,
        () => next.copyWith(emailVerified: true));
    apply(docVerified(VerificationDocumentType.income), next.incomeVerified,
        () => next.copyWith(incomeVerified: true));
    apply(docVerified(VerificationDocumentType.asset), next.assetVerified,
        () => next.copyWith(assetVerified: true));
    apply(
        docVerified(VerificationDocumentType.aadhaar),
        next.aadhaarVerified && next.govIdVerified,
        () => next.copyWith(aadhaarVerified: true, govIdVerified: true));
    apply(docVerified(VerificationDocumentType.nri), next.nriVerified,
        () => next.copyWith(nriVerified: true));

    if (changed) widget.onChanged(next);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncMirrors());
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ─── Mobile (real Firebase phone OTP) ─────────────────────────────────

  Future<void> _openMobileOtpSheet() async {
    if (_mobileSheetOpen) return;
    final phone = ref.read(authRepositoryProvider).currentUser?.phoneNumber;
    if (phone == null || phone.isEmpty) {
      _snack('No phone number on file for this account.');
      return;
    }
    _mobileSheetOpen = true;
    try {
      final verified = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _MobileOtpSheet(phone: phone),
      );
      if (!mounted) return;
      if (verified == true) {
        _syncMirrors();
        setState(() {});
      }
    } finally {
      _mobileSheetOpen = false;
    }
  }

  // ─── Email (real Firebase email-link check) ────────────────────────────

  Future<void> _openEmailCheckSheet() async {
    if (_emailSheetOpen) return;
    _emailSheetOpen = true;
    try {
      final verified = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => const _EmailCheckSheet(),
      );
      if (!mounted) return;
      if (verified == true) {
        _syncMirrors();
        setState(() {});
      }
    } finally {
      _emailSheetOpen = false;
    }
  }

  // ─── Document uploads (income/asset/aadhaar/nri) ──────────────────────

  Future<void> _startDocumentUpload(VerificationDocumentType type) async {
    if (_pickingInProgress.contains(type)) return;
    final existing = ref.read(verificationStatusesProvider).valueOrNull?[type];
    if (existing?.isBusy ?? false) return;

    setState(() => _pickingInProgress.add(type));
    try {
      final source = await _chooseSource();
      if (source == null || !mounted) return;

      final file = await _attachmentPicker.pick(
        context,
        source,
        maxWidth: 2000,
        imageQuality: 85,
      );
      if (file == null || !mounted) return; // cancelled, denied, or failed

      final sizeBytes = await file.length();
      if (!mounted) return;
      if (sizeBytes > _kMaxDocumentBytes) {
        _snack('File is too large. Please choose a file under 8 MB.');
        return;
      }

      final confirmed = await _showPreviewSheet(file);
      if (confirmed != true || !mounted) return;

      try {
        await ref.read(verificationStatusesProvider.notifier).submit(type, file);
      } catch (_) {
        if (!mounted) return;
        _snack('Upload failed. Please check your connection and try again.');
        return;
      }
      if (!mounted) return;
      _syncMirrors();
      _snack('Document submitted for review.');
    } finally {
      if (mounted) setState(() => _pickingInProgress.remove(type));
    }
  }

  Future<ImageSource?> _chooseSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primary),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: AppColors.accentGold),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showPreviewSheet(File file) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Preview document', style: AppTypography.titleLarge),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(file, height: 240, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Choose again'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Confirm upload'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Subscribe for rebuilds on auth-state changes; the *value* used for
    // rendering is always freshly read (see below) because linking a phone
    // credential updates FirebaseAuth.currentUser without necessarily
    // emitting a new authStateChanges() event.
    ref.watch(currentAuthUserProvider);
    final authUser = ref.read(authRepositoryProvider).currentAuthUser;

    final docsAsync = ref.watch(verificationStatusesProvider);
    final docs = docsAsync.valueOrNull ?? const {};
    final progressMap = ref.watch(verificationUploadProgressProvider);

    ref.listen(currentAuthUserProvider, (prev, next) => _syncMirrors());
    ref.listen(verificationStatusesProvider, (prev, next) {
      if (next.hasValue) _syncMirrors();
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.registrationWizardVerificationHeadline,
            style: AppTypography.headlineSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.registrationWizardVerificationHook,
            style: AppTypography.bodyMedium.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipVerification),
          const SizedBox(height: 24),
          _mobileCard(l10n, authUser),
          const SizedBox(height: 16),
          _emailCard(l10n, authUser),
          const SizedBox(height: 16),
          _documentCard(
            l10n: l10n,
            type: VerificationDocumentType.income,
            icon: Icons.receipt_long_rounded,
            title: l10n.registrationVerifyIncomeTitle,
            subtitle: l10n.registrationVerifyIncomeSubtitle,
            record: docs[VerificationDocumentType.income],
            progress: progressMap[VerificationDocumentType.income],
          ),
          const SizedBox(height: 16),
          _documentCard(
            l10n: l10n,
            type: VerificationDocumentType.asset,
            icon: Icons.real_estate_agent_rounded,
            title: l10n.registrationVerifyAssetTitle,
            subtitle: l10n.registrationVerifyAssetSubtitle,
            record: docs[VerificationDocumentType.asset],
            progress: progressMap[VerificationDocumentType.asset],
          ),
          const SizedBox(height: 16),
          _documentCard(
            l10n: l10n,
            type: VerificationDocumentType.aadhaar,
            icon: Icons.verified_user_outlined,
            title: l10n.registrationVerifyIdTitle,
            subtitle: l10n.registrationVerifyIdSubtitle,
            record: docs[VerificationDocumentType.aadhaar],
            progress: progressMap[VerificationDocumentType.aadhaar],
          ),
          const SizedBox(height: 16),
          _documentCard(
            l10n: l10n,
            type: VerificationDocumentType.nri,
            icon: Icons.flight_takeoff_rounded,
            title: l10n.registrationVerifyNriTitle,
            subtitle: l10n.registrationVerifyNriSubtitle,
            record: docs[VerificationDocumentType.nri],
            progress: progressMap[VerificationDocumentType.nri],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_rounded, color: AppColors.success, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.registrationPrivacyTitle,
                        style: AppTypography.titleSmall.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.registrationPrivacySubtitle,
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _mobileCard(AppLocalizations l10n, AuthUser? authUser) {
    final verified = authUser?.phoneVerified ?? false;
    return NmVerificationStatusCard(
      icon: Icons.phone_android_rounded,
      title: l10n.registrationVerifyMobileTitle,
      subtitle: l10n.registrationVerifyMobileSubtitle,
      status: verified
          ? NmVerificationCardStatus.verified
          : NmVerificationCardStatus.notVerified,
      actionLabel: l10n.registrationVerifyButton,
      onAction: verified ? null : _openMobileOtpSheet,
    );
  }

  Widget _emailCard(AppLocalizations l10n, AuthUser? authUser) {
    final verified = authUser?.emailVerified ?? false;
    return NmVerificationStatusCard(
      icon: Icons.email_outlined,
      title: l10n.registrationVerifyEmailTitle,
      subtitle: l10n.registrationVerifyEmailSubtitle,
      status: verified
          ? NmVerificationCardStatus.verified
          : NmVerificationCardStatus.notVerified,
      actionLabel: l10n.registrationVerifyButton,
      onAction: verified ? null : _openEmailCheckSheet,
    );
  }

  Widget _documentCard({
    required AppLocalizations l10n,
    required VerificationDocumentType type,
    required IconData icon,
    required String title,
    required String subtitle,
    required VerificationDocumentRecord? record,
    required double? progress,
  }) {
    final busy = _pickingInProgress.contains(type) || (record?.isBusy ?? false);
    final status = busy
        ? NmVerificationCardStatus.uploading
        : switch (record?.status ?? VerificationSubmissionStatus.notSubmitted) {
            VerificationSubmissionStatus.notSubmitted =>
              NmVerificationCardStatus.notVerified,
            VerificationSubmissionStatus.uploading =>
              NmVerificationCardStatus.uploading,
            VerificationSubmissionStatus.pending => NmVerificationCardStatus.pending,
            VerificationSubmissionStatus.verified =>
              NmVerificationCardStatus.verified,
            VerificationSubmissionStatus.rejected =>
              NmVerificationCardStatus.rejected,
            VerificationSubmissionStatus.failed => NmVerificationCardStatus.failed,
          };
    final isRetryable = status == NmVerificationCardStatus.rejected ||
        status == NmVerificationCardStatus.failed;
    final isActionable = status == NmVerificationCardStatus.notVerified || isRetryable;

    return NmVerificationStatusCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      status: status,
      actionLabel:
          isRetryable ? l10n.registrationVerificationRetryButton : l10n.registrationVerifyButton,
      onAction: isActionable ? () => _startDocumentUpload(type) : null,
      progress: progress,
      statusLabel: switch (status) {
        NmVerificationCardStatus.pending => l10n.registrationVerificationPendingLabel,
        NmVerificationCardStatus.rejected => l10n.registrationVerificationRejectedLabel,
        NmVerificationCardStatus.failed => l10n.registrationVerificationFailedLabel,
        _ => null,
      },
      rejectionReason: record?.rejectionReason,
    );
  }
}

/// Inline mobile OTP verification — mirrors PhoneVerifyScreen's real
/// Firebase-backed flow (send/resend/auto-retrieve/manual entry) but as a
/// bottom sheet that just pops `true` on success instead of navigating, so
/// it can be opened mid-wizard without resetting the registration draft
/// (PhoneVerifyScreen's own success handler calls `startCreateMode()`,
/// which would wipe steps 0-12 if reused here).
class _MobileOtpSheet extends ConsumerStatefulWidget {
  const _MobileOtpSheet({required this.phone});
  final String phone;

  @override
  ConsumerState<_MobileOtpSheet> createState() => _MobileOtpSheetState();
}

class _MobileOtpSheetState extends ConsumerState<_MobileOtpSheet> {
  String _otp = '';
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(phoneAuthControllerProvider.notifier).sendCode(widget.phone);
    });
  }

  Future<void> _onAutoVerified() async {
    final controller = ref.read(phoneAuthControllerProvider.notifier);
    final credential = ref.read(phoneAuthControllerProvider).autoCredential;
    if (credential == null || _verifying) return;
    controller.clearAutoCredential();
    setState(() => _verifying = true);
    try {
      await ref.read(authRepositoryProvider).confirmAutoPhoneForSignup(credential);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      _showError(AuthErrorMapper.message(e));
    }
  }

  Future<void> _verifyManual() async {
    final state = ref.read(phoneAuthControllerProvider);
    if (_otp.length != 6 || state.verificationId == null || _verifying) return;
    setState(() => _verifying = true);
    try {
      await ref.read(authRepositoryProvider).confirmPhoneForSignup(
            verificationId: state.verificationId!,
            smsCode: _otp,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      _showError(AuthErrorMapper.message(e));
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(phoneAuthControllerProvider);

    ref.listen<PhoneAuthState>(phoneAuthControllerProvider, (prev, next) {
      if (next.status == PhoneAuthStatus.autoRetrieved && next.autoCredential != null) {
        _onAutoVerified();
      }
      if (next.status == PhoneAuthStatus.error && next.errorMessage != null) {
        _showError(next.errorMessage!);
      }
    });

    final isSending = state.status == PhoneAuthStatus.sending;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.authEnterVerificationCode,
              style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              isSending ? l10n.authSendingOtp : l10n.authOtpSentTo(widget.phone),
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: 24),
            Center(
              child: NmOtpInput(
                length: 6,
                onCompleted: (value) {
                  _otp = value;
                  _verifyManual();
                },
                onChanged: (value) => _otp = value,
              ),
            ),
            const SizedBox(height: 24),
            NmGradientButton(
              label: l10n.authVerifyAndContinue,
              icon: Icons.check_circle_outline_rounded,
              isLoading: _verifying,
              onPressed: _otp.length == 6 ? _verifyManual : null,
            ),
            const SizedBox(height: 16),
            Center(
              child: state.secondsRemaining > 0
                  ? Text(
                      '00:${state.secondsRemaining.toString().padLeft(2, '0')}',
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : TextButton.icon(
                      onPressed: isSending
                          ? null
                          : () => ref.read(phoneAuthControllerProvider.notifier).resend(),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(l10n.authResendOtp),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline email verification check — mirrors EmailVerifyScreen's real
/// Firebase-backed poll/resend/manual-check flow but as a bottom sheet that
/// pops `true` on success instead of navigating (EmailVerifyScreen's own
/// success handler calls `startCreateMode()`, unsafe to reuse mid-wizard).
class _EmailCheckSheet extends ConsumerStatefulWidget {
  const _EmailCheckSheet();

  @override
  ConsumerState<_EmailCheckSheet> createState() => _EmailCheckSheetState();
}

class _EmailCheckSheetState extends ConsumerState<_EmailCheckSheet> {
  Timer? _pollTimer;
  Timer? _resendTimer;
  bool _checking = false;
  int _resendCooldown = 0;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _check(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    if (!silent) setState(() => _checking = true);
    final verified = await ref.read(authRepositoryProvider).checkEmailVerified();
    if (!mounted) return;
    if (!silent) setState(() => _checking = false);
    if (verified) {
      _pollTimer?.cancel();
      Navigator.pop(context, true);
    } else if (!silent) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.authEmailNotVerifiedYet)));
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(authRepositoryProvider).resendEmailVerification();
      if (!mounted) return;
      setState(() => _resendCooldown = 60);
      _resendTimer?.cancel();
      _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (_resendCooldown <= 1) {
          t.cancel();
          setState(() => _resendCooldown = 0);
        } else {
          setState(() => _resendCooldown--);
        }
      });
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.authVerificationEmailSent)));
    } catch (_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.authGenericError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final email = ref.watch(firebaseAuthServiceProvider).currentUser?.email ?? '';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.authVerifyEmailTitle,
              style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(l10n.authVerifyEmailSentTo(email), style: AppTypography.bodySmall),
            const SizedBox(height: 20),
            NmGradientButton(
              label: l10n.authIveVerified,
              icon: Icons.check_circle_outline_rounded,
              isLoading: _checking,
              onPressed: () => _check(),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: _resendCooldown > 0 ? null : _resend,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(_resendCooldown > 0
                    ? l10n.authResendEmailIn(_resendCooldown.toString())
                    : l10n.authResendEmail),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
