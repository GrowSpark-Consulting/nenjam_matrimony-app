import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/dialogs/app_dialogs.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/support_ticket.dart';
import '../providers/support_providers.dart';

/// One reusable form serving Contact Support / Report a Bug / Feature
/// Request / App Feedback — the only thing that changes between them is
/// the [type] (drives the AppBar title) and the copy pulled from it.
class SupportTicketFormPage extends ConsumerStatefulWidget {
  final SupportTicketType type;

  const SupportTicketFormPage({super.key, required this.type});

  @override
  ConsumerState<SupportTicketFormPage> createState() => _SupportTicketFormPageState();
}

class _SupportTicketFormPageState extends ConsumerState<SupportTicketFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String _title(AppLocalizations l10n) => switch (widget.type) {
        SupportTicketType.contactSupport => l10n.supportContactTitle,
        SupportTicketType.bugReport => l10n.supportBugReportTitle,
        SupportTicketType.featureRequest => l10n.supportFeatureRequestTitle,
        SupportTicketType.appFeedback => l10n.supportAppFeedbackTitle,
      };

  Future<void> _submit() async {
    if (_submitting) return;
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    try {
      await ref.read(supportRepositoryProvider).submitTicket(
            type: widget.type,
            subject: _subjectController.text.trim(),
            message: _messageController.text.trim(),
          );
      if (!mounted) return;
      await AppDialogs.showSuccess(
        context,
        title: l10n.supportTicketFormSuccessTitle,
        message: l10n.supportTicketFormSuccessMessage,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      await AppDialogs.showError(context, message: l10n.supportTicketFormErrorMessage);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(_title(l10n))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _subjectController,
                  decoration: InputDecoration(
                    labelText: l10n.supportTicketFormSubjectLabel,
                    hintText: l10n.supportTicketFormSubjectHint,
                    border: const OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? l10n.supportTicketFormValidationError
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    labelText: l10n.supportTicketFormMessageLabel,
                    hintText: l10n.supportTicketFormMessageHint,
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  minLines: 5,
                  maxLines: 10,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? l10n.supportTicketFormValidationError
                      : null,
                ),
                const SizedBox(height: 24),
                NmPrimaryButton(
                  label: l10n.supportTicketFormSubmit,
                  onPressed: _submitting ? null : _submit,
                  isLoading: _submitting,
                  height: 52,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
