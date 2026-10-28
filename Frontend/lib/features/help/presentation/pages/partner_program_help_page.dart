import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

/// The Nenjam team's support contact for agents. **Not supplied yet** (Raja
/// to confirm) — an explicit placeholder, never a guessed address.
const String kPartnerSupportContactPlaceholder =
    '<support contact to be confirmed>';

/// Help & Support for the Nenjam Partner Program, in the supplied wording.
///
/// Static copy only. It names no agent status, referral stage or other label
/// — those come from `GET /agent/config` — and links to no portal: the
/// Partner Program entry point is the website landing page only.
class PartnerProgramHelpPage extends StatelessWidget {
  const PartnerProgramHelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.partnerHelpTitle)),
      body: SafeArea(
        child: ListView(
          padding: NmContentWidth.pagePadding(
            context,
            const EdgeInsets.all(20),
          ),
          children: [
            Text(l10n.partnerHelpWelcome, style: AppTypography.titleLarge),
            _Section(
              title: l10n.partnerHelpGettingStartedTitle,
              body: l10n.partnerHelpGettingStartedBody,
            ),
            _Section(
              title: l10n.partnerHelpReferringTitle,
              body: l10n.partnerHelpReferringBody,
            ),
            _Section(
              title: l10n.partnerHelpTrackingTitle,
              body: l10n.partnerHelpTrackingBody,
            ),
            _Section(
              title: l10n.partnerHelpBankTitle,
              body: l10n.partnerHelpBankBody,
            ),
            _Section(
              title: l10n.partnerHelpTermsTitle,
              children: [
                for (final term in [
                  l10n.partnerHelpTermNoFees,
                  l10n.partnerHelpTermNoFalsePromises,
                  l10n.partnerHelpTermNoSharing,
                  l10n.partnerHelpTermConsent,
                ])
                  _Bullet(term),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.partnerHelpTermsConsequence,
                  style: AppTypography.bodyMedium,
                ),
              ],
            ),
            _Section(
              title: l10n.partnerHelpNeedHelpTitle,
              children: [
                Text(
                  l10n.partnerHelpContact(kPartnerSupportContactPlaceholder),
                  style: AppTypography.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.partnerHelpOtpWarning,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.body, this.children = const []});

  final String title;
  final String? body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: AppTypography.titleMedium),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (body != null) Text(body!, style: AppTypography.bodyMedium),
          ...children,
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: AppTypography.bodyMedium),
          Expanded(child: Text(text, style: AppTypography.bodyMedium)),
        ],
      ),
    );
  }
}
