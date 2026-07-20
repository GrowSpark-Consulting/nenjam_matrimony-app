import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/discover/domain/entities/discovery_profile_entity.dart';
import 'route_names.dart';

/// Single entry point for navigating to Profile Detail.
///
/// Every profile card in the app (Discover, Matches, Search, Similar
/// Profiles, New Today, Hero Match cards, …) must push through this
/// helper rather than calling `context.push(RouteNames.profileDetail,
/// extra: profile)` directly, so the navigation call — and the `extra`
/// payload shape it relies on — stays consistent in exactly one place if
/// it ever needs to change (e.g. to a real `:id` route param).
void openProfileDetail(BuildContext context, DiscoveryProfileEntity profile) {
  context.push(RouteNames.profileDetail, extra: profile);
}
