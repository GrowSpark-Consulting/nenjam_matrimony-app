import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/agent_referral_link.dart';
import '../../domain/services/whatsapp_share.dart';
import '../providers/agent_program_providers.dart';

/// An agent's referral codes with "Copy code" and "Share on WhatsApp".
///
/// The WhatsApp text is the link's own `shareMessages` entry, exactly as the
/// backend returned it — never assembled here, and never from the
/// `GET /agent/config` templates. English or Tamil is the agent's choice,
/// starting from the app language.
///
/// Not routed anywhere yet: the member app has no agent session, and the
/// Partner Program entry point is the website landing page only.
class AgentReferralShareList extends ConsumerWidget {
  const AgentReferralShareList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(agentReferralLinksProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Text(l10n.agentShareLoadFailed),
          data: (links) => links.isEmpty
              ? Text(l10n.agentShareNoCodes)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final link in links) ...[
                      AgentReferralShareCard(link: link),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ],
                ),
        );
  }
}

class AgentReferralShareCard extends ConsumerStatefulWidget {
  const AgentReferralShareCard({super.key, required this.link});

  final AgentReferralLink link;

  @override
  ConsumerState<AgentReferralShareCard> createState() =>
      _AgentReferralShareCardState();
}

class _AgentReferralShareCardState
    extends ConsumerState<AgentReferralShareCard> {
  String? _language;

  Future<void> _copyCode() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: widget.link.code));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.agentShareCodeCopied)));
  }

  Future<void> _share(String message) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final opened = await shareOnWhatsApp(
      message,
      open: ref.read(urlOpenerProvider),
    );
    if (opened) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.agentShareFailed)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final link = widget.link;
    final language =
        _language ??
        (Localizations.localeOf(context).languageCode == 'ta' ? 'ta' : 'en');
    final message = link.shareTextFor(language);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The code is always shown and always copyable, link or not.
        Row(
          children: [
            Expanded(
              child: SelectableText(
                link.code,
                style: AppTypography.headlineSmall.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: link.code.isEmpty ? null : _copyCode,
              icon: const Icon(Icons.copy_rounded),
              label: Text(l10n.agentShareCopyCode),
            ),
          ],
        ),
        // `link` is null until the web address is decided: then it is hidden.
        if (link.link != null) ...[
          const SizedBox(height: AppSpacing.xs),
          SelectableText(link.link!, style: AppTypography.bodySmall),
        ],
        const SizedBox(height: AppSpacing.md),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'en',
              label: Text(l10n.agentShareLanguageEnglish),
            ),
            ButtonSegment(
              value: 'ta',
              label: Text(l10n.agentShareLanguageTamil),
            ),
          ],
          selected: {language},
          onSelectionChanged: (s) => setState(() => _language = s.first),
        ),
        const SizedBox(height: AppSpacing.md),
        if (message != null)
          Text(message, style: AppTypography.bodyMedium)
        else
          Text(
            l10n.agentShareNoMessage,
            style: AppTypography.bodySmall.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        if (!link.shareable) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.agentShareNotShareable,
            style: AppTypography.bodySmall.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: link.shareable && message != null
                ? () => _share(message)
                : null,
            icon: const Icon(Icons.share_rounded),
            label: Text(l10n.agentShareWhatsApp),
          ),
        ),
      ],
    );
  }
}
