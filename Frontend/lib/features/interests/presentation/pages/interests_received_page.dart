import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../widgets/interest_list_view.dart';

/// Interests Received — route wired from the navigation drawer. Shares its
/// entire body (states, list rendering, Accept/Decline) with the Inbox's
/// "Interests Received" tab via [InterestListView], so the two surfaces can
/// never disagree.
class InterestsReceivedPage extends StatelessWidget {
  const InterestsReceivedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.drawerInterestReceived)),
      body: const SafeArea(child: InterestListView(isReceived: true)),
    );
  }
}
