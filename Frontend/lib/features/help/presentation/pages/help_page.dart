import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/layout/content_width.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../support/domain/models/support_ticket.dart';

/// Help & Support center screen.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  Future<void> _emailSupport(BuildContext context) async {
    final uri = Uri(scheme: 'mailto', path: 'support@nenjammatrimony.com');
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).helpNoEmailApp)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).drawerHelp)),
      body: SafeArea(
        child: ListView(
          padding: NmContentWidth.pagePadding(context, const EdgeInsets.all(20)),
          children: [
            Text(AppLocalizations.of(context).helpFaqTitle, style: AppTypography.titleLarge),
            const SizedBox(height: 16),
            const _FaqItem(
              question: 'How does AI matching work?',
              answer:
                  'Our AI evaluates over 50 compatibility markers including lifestyle, horoscope, and career preferences.',
            ),
            const _FaqItem(
              question: 'Is my phone number visible to everyone?',
              answer:
                  'No. Only premium members whom you have accepted can view your contact details.',
            ),
            const _FaqItem(
              question: 'How do I upgrade to Premium VIP?',
              answer:
                  'Go to the Premium tab from the bottom menu or navigation drawer to explore luxury membership plans.',
            ),
            const SizedBox(height: 32),
            Text(AppLocalizations.of(context).helpStillNeedHelp, style: AppTypography.titleLarge),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.support_agent_rounded),
              title: Text(l10n.supportContactTitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(
                RouteNames.supportTicketForm,
                extra: SupportTicketType.contactSupport,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: Text(l10n.supportEmailTitle),
              subtitle: Text(l10n.supportEmailSubtitle),
              onTap: () => _emailSupport(context),
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: Text(l10n.supportBugReportTitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(
                RouteNames.supportTicketForm,
                extra: SupportTicketType.bugReport,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.lightbulb_outline_rounded),
              title: Text(l10n.supportFeatureRequestTitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(
                RouteNames.supportTicketForm,
                extra: SupportTicketType.featureRequest,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.rate_review_outlined),
              title: Text(l10n.supportAppFeedbackTitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(
                RouteNames.supportTicketForm,
                extra: SupportTicketType.appFeedback,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: Text(l10n.supportTicketHistoryTitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(RouteNames.ticketHistory),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(question, style: AppTypography.titleSmall),
      childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      children: [
        Text(answer, style: AppTypography.bodyMedium),
      ],
    );
  }
}
