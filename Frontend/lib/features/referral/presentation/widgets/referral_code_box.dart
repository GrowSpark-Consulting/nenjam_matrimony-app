import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/referral_models.dart';
import '../providers/referral_providers.dart';

enum _BoxState { collapsed, editing, checking, applied }

/// "Have a referral code?" — optional, on the name and date of birth step.
///
/// Validates with `POST /referrals/codes/validate` (no token needed — most
/// members have no session yet at this step) and, when the code is valid,
/// stores it in [pendingReferralStoreProvider]. It never attaches anything:
/// attaching needs a signed-in member and runs later, through
/// `ReferralAttachmentController`.
///
/// Nothing here affects whether the step can continue.
class ReferralCodeBox extends ConsumerStatefulWidget {
  const ReferralCodeBox({super.key});

  @override
  ConsumerState<ReferralCodeBox> createState() => _ReferralCodeBoxState();
}

class _ReferralCodeBoxState extends ConsumerState<ReferralCodeBox> {
  final _controller = TextEditingController();
  _BoxState _state = _BoxState.collapsed;
  PendingReferralCode? _applied;

  /// The one line under the field: invalid, rate-limited or unreachable.
  String? _error;

  /// The code that arrived with a shared link (`?ref=`) and was put in the
  /// field for the member. While the field still holds exactly this, the
  /// member has not touched it; any edit or removal drops the link copy so
  /// it can never overwrite what they chose.
  String? _linkCode;

  @override
  void initState() {
    super.initState();
    // Reopening the step (Back from Religion, or a relaunch mid-signup)
    // shows the code already applied rather than an empty box.
    final stored = ref.read(pendingReferralStoreProvider).read();
    if (stored != null) {
      _applied = stored;
      _state = _BoxState.applied;
      return;
    }
    // A code from a shared link: fill the field and run the SAME apply the
    // Apply button runs, once. Not when the feature is off.
    final link = ref.read(linkReferralStoreProvider).read();
    if (link != null && ref.read(referralCodeEntryEnabledProvider)) {
      _linkCode = link;
      _controller.text = link;
      _state = _BoxState.editing;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _state == _BoxState.editing) _apply();
      });
    }
  }

  /// The member changed or removed the code themselves, or it has been
  /// handled: forget the link copy so it is never re-applied.
  void _dropLinkCode() {
    if (_linkCode == null) return;
    _linkCode = null;
    ref.read(linkReferralStoreProvider).clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final l10n = AppLocalizations.of(context);
    final code = normalizeReferralCode(_controller.text);
    if (code == null) {
      _dropLinkCode();
      // A code that cannot match the contract's pattern is "not valid" —
      // the same single message, without spending an attempt on it.
      setState(() => _error = l10n.referralCodeInvalid);
      return;
    }
    setState(() {
      _state = _BoxState.checking;
      _error = null;
    });

    String? error;
    PendingReferralCode? applied;
    bool? transientFailure;
    try {
      final result = await ref
          .read(referralRepositoryProvider)
          .validateCode(code);
      if (result.valid) {
        applied = PendingReferralCode(
          code: code,
          agentDisplayName: result.agentDisplayName,
        );
        await ref.read(pendingReferralStoreProvider).write(applied);
      } else {
        error = l10n.referralCodeInvalid;
      }
    } on ApiException catch (e) {
      transientFailure = e.statusCode != 400;
      if (e.statusCode == 429) {
        final seconds = e.retryAfterSeconds;
        error = seconds != null
            ? l10n.referralCodeTooManyTriesSeconds(seconds)
            : l10n.referralCodeTooManyTries;
      } else if (e.statusCode == 400) {
        error = l10n.referralCodeInvalid;
      } else {
        error = l10n.referralCodeCheckFailed;
      }
    } catch (_) {
      transientFailure = true;
      error = l10n.referralCodeCheckFailed;
    }
    // Valid -> the persistent store owns it now. Definitively invalid -> do
    // not re-validate it on every return. Only a transient failure (rate
    // limit, network, 5xx) keeps the link copy, so it can be tried again.
    if (applied != null || transientFailure != true) _dropLinkCode();
    if (!mounted) return;
    setState(() {
      _error = error;
      _applied = applied;
      _state = applied != null ? _BoxState.applied : _BoxState.editing;
    });
  }

  Future<void> _remove() async {
    _dropLinkCode();
    await ref.read(pendingReferralStoreProvider).clear();
    if (!mounted) return;
    setState(() {
      _applied = null;
      _error = null;
      _controller.clear();
      _state = _BoxState.editing;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    if (_state == _BoxState.collapsed) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () => setState(() => _state = _BoxState.editing),
          icon: const Icon(Icons.card_giftcard_rounded),
          label: Text(l10n.referralCodePrompt),
        ),
      );
    }

    if (_state == _BoxState.applied && _applied != null) {
      final name = _applied!.agentDisplayName;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.referralCodePrompt, style: AppTypography.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: colors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  name != null
                      ? l10n.referralCodeReferredBy(name)
                      : _applied!.code,
                  style: AppTypography.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: _remove,
                child: Text(l10n.referralCodeRemove),
              ),
            ],
          ),
        ],
      );
    }

    final checking = _state == _BoxState.checking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.referralCodePrompt, style: AppTypography.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.referralCodeHelp,
          style: AppTypography.bodySmall.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: NmTextField(
                label: l10n.referralCodeLabel,
                controller: _controller,
                enabled: !checking,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _apply(),
                onChanged: (v) {
                  if (v != _linkCode) _dropLinkCode();
                  if (_error != null) setState(() => _error = null);
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: checking
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      onPressed: _apply,
                      child: Text(l10n.referralCodeApply),
                    ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _error!,
            style: AppTypography.bodySmall.copyWith(color: colors.error),
          ),
        ],
      ],
    );
  }
}
