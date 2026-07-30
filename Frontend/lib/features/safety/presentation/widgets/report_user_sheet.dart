import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/report_reason.dart';
import '../providers/safety_providers.dart';
import '../utils/safety_error_message.dart';

class _ReportReasonOption {
  const _ReportReasonOption(this.label, this.reason, {this.descriptionPrefix});

  final String label;
  final ReportReason reason;
  /// Prepended to the optional free-text detail before it's sent — lets a
  /// reason that has no direct backend enum value (e.g. "Underage", which
  /// collapses onto [ReportReason.other]) stay distinguishable to a
  /// moderator reading the report's description.
  final String? descriptionPrefix;
}

/// Report flow body — reason selection, optional free-text detail, and
/// submit, all in one sheet (hosted by `AppSheets.show` via
/// `handleReportUser`). Owns its own loading/error state: a failed submit
/// shows a SnackBar and re-enables the Submit button without closing the
/// sheet; only a successful submit shows the success SnackBar and pops.
class ReportUserSheet extends ConsumerStatefulWidget {
  const ReportUserSheet({
    super.key,
    required this.userId,
    required this.userName,
  });

  final String userId;
  final String userName;

  @override
  ConsumerState<ReportUserSheet> createState() => _ReportUserSheetState();
}

class _ReportUserSheetState extends ConsumerState<ReportUserSheet> {
  final _descriptionController = TextEditingController();
  int? _selectedIndex;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  List<_ReportReasonOption> _options(AppLocalizations l10n) => [
        _ReportReasonOption(
          l10n.profileDetailReportReasonFakeProfile,
          ReportReason.fakeProfile,
        ),
        _ReportReasonOption(l10n.profileDetailReportReasonSpam, ReportReason.spam),
        _ReportReasonOption(
          l10n.profileDetailReportReasonHarassment,
          ReportReason.harassment,
        ),
        _ReportReasonOption(
          l10n.profileDetailReportReasonInappropriateContent,
          ReportReason.inappropriateContent,
        ),
        _ReportReasonOption(
          l10n.profileDetailReportReasonUnderage,
          ReportReason.other,
          descriptionPrefix: '[Underage] ',
        ),
        _ReportReasonOption(l10n.profileDetailReportReasonOther, ReportReason.other),
      ];

  Future<void> _submit(List<_ReportReasonOption> options) async {
    if (_selectedIndex == null || _isSubmitting) return;
    final option = options[_selectedIndex!];
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final description = _composeDescription(option);

    setState(() => _isSubmitting = true);
    try {
      await ref.read(safetyRepositoryProvider).reportUser(
            widget.userId,
            reason: option.reason,
            description: description,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      messenger.showSnackBar(SnackBar(content: Text(safetyErrorMessage(l10n, e))));
      return;
    }

    HapticFeedback.lightImpact();
    messenger.showSnackBar(SnackBar(content: Text(l10n.profileDetailReportSuccess)));
    if (mounted) Navigator.of(context).pop();
  }

  String? _composeDescription(_ReportReasonOption option) {
    final text = _descriptionController.text.trim();
    final combined = '${option.descriptionPrefix ?? ''}$text'.trim();
    return combined.isEmpty ? null : combined;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = _options(l10n);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < options.length; i++)
              _ReasonRow(
                label: options[i].label,
                selected: _selectedIndex == i,
                onTap: _isSubmitting
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedIndex = i);
                      },
              ),
            const SizedBox(height: 12),
            Text(
              l10n.profileDetailReportDescriptionLabel,
              style: AppTypography.labelMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              enabled: !_isSubmitting,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: l10n.profileDetailReportDescriptionHint,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_selectedIndex == null || _isSubmitting)
                    ? null
                    : () => _submit(options),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.profileDetailReportSubmit),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? AppColors.primary : null,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
