import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../widgets/interest_list_view.dart';

/// Interests Sent — route wired from the navigation drawer. Shares its
/// entire body (states, list rendering, Withdraw) with the Inbox's
/// "Interests Sent" tab via [InterestListView], so the two surfaces can
/// never disagree.
class InterestsSentPage extends StatelessWidget {
  const InterestsSentPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.drawerInterestSent)),
      body: const SafeArea(child: InterestListView(isReceived: false)),
    );
  }
}
