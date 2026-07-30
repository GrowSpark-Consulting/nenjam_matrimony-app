import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/discover/domain/entities/discovery_profile_entity.dart';
import 'route_names.dart';

/// Everything `RouteNames.profileDetail`'s route needs: which profile, and
/// (optionally) which Hero tag its header photo should animate from.
///
/// [heroTag] matters because Discover and Matches are both permanently
/// mounted branches of the bottom-nav shell (`StatefulShellRoute.
/// indexedStack` keeps every branch's widgets alive via `IndexedStack`,
/// unlike a normal route push/pop, which Flutter's Navigator already
/// isolates Hero discovery around). If the same profile happens to appear
/// in both Discover's feed and Matches' reel at once — routine, since both
/// pull from the same `/discover` pool — their cards' `Hero`s coexist
/// forever in the shell's subtree. A plain `'profile-photo-$id'` tag on
/// both would trip Flutter's "multiple heroes share the same tag within a
/// subtree" assertion on every push/pop, since that subtree is an endpoint
/// of practically every hero flight in the app. Discover/Matches therefore
/// use their own scoped tags (`'profile-photo-discover-$id'` /
/// `'profile-photo-matches-$id'`) instead of the plain one, and pass that
/// exact tag here so the header matches whichever specific card the flight
/// is actually animating from. Screens that are only ever pushed on top of
/// the shell (Search, Similar Profiles, Shortlisted) don't have this
/// problem — Flutter's own Navigator already keeps distinct pushed routes
/// hero-isolated from each other — so they can omit [heroTag] and fall back
/// to the plain `'profile-photo-$id'` scheme.
/// Monotonic discriminator so two pushes of the same static
/// `/profile-detail` path always get distinct [ProfileDetailArgs.pageKey]s
/// — see that field's doc comment for why this is required at all.
int _pageKeySeq = 0;

class ProfileDetailArgs {
  final DiscoveryProfileEntity profile;
  final String? heroTag;
  /// Whether the caller already knows this member is currently blocked (only
  /// ever true from Chat, which carries its own `ConversationEntity.
  /// isBlocked` — there's no `GET` endpoint for block status, and every
  /// other entry point — Discover, Search, Matches, Similar Profiles — can
  /// never reach a blocked member's card in the first place, since those
  /// feeds already exclude blocked members server-side). Drives whether
  /// Profile Detail's "More" menu offers Block or Unblock.
  final bool isBlocked;

  /// Uniquely identifies THIS push of Profile Detail, for use as the
  /// route's `Page.key`.
  ///
  /// `RouteNames.profileDetail` ('/profile-detail') is a static path with no
  /// `:id` segment — the profile is carried via `extra`, not the URL. go_
  /// router's default `Page` key for a `builder:`-only route is
  /// `state.pageKey`, which for a plain path match is `ValueKey(fullPath)`:
  /// identical on every push of this route, regardless of `extra` or of
  /// going through `.push()` vs `.go()` (go_router's own per-push
  /// uniqueness — `_getUniqueValueKey()` — only wraps the *imperative match
  /// list entry* used for popping; the leaf `GoRouterState.pageKey` that
  /// actually becomes the rendered `Page`'s key still comes from the path-
  /// based match). Profile Detail is reachable recursively — tapping a
  /// "Similar Profiles" card from within Profile Detail pushes this exact
  /// route again on the SAME (root) Navigator (see
  /// `similar_profiles_section.dart`'s own doc comment: "the back stack
  /// grows Detail(A) → Detail(B)") — so two simultaneously-mounted pushes
  /// of this path previously produced two `Page`s with the identical key,
  /// which is exactly what trips Flutter's Navigator "!keyReservation.
  /// contains(key)" assertion. Combining the profile id (for
  /// debuggability) with a monotonic counter (for correctness even if the
  /// same profile is somehow opened twice in a row) guarantees every push
  /// gets its own key — the same role go_router's own internal
  /// `_getUniqueValueKey()` plays, just applied where it's actually needed:
  /// the leaf route's `Page`, not only the imperative stack bookkeeping.
  final ValueKey<String> pageKey;

  ProfileDetailArgs(this.profile, {this.heroTag, this.isBlocked = false})
      : pageKey = ValueKey<String>('profile-detail-${profile.id}-${_pageKeySeq++}');
}

/// Single entry point for navigating to Profile Detail.
///
/// Every profile card in the app (Discover, Matches, Search, Similar
/// Profiles, New Today, Hero Match cards, …) must push through this
/// helper rather than calling `context.push(RouteNames.profileDetail,
/// extra: profile)` directly, so the navigation call — and the `extra`
/// payload shape it relies on — stays consistent in exactly one place if
/// it ever needs to change (e.g. to a real `:id` route param).
///
/// Pass [heroTag] when the tapped card used a scoped Hero tag (see
/// [ProfileDetailArgs]) — Discover/Matches call sites must always supply
/// the one that matches their card's own `Hero`.
void openProfileDetail(
  BuildContext context,
  DiscoveryProfileEntity profile, {
  String? heroTag,
  bool isBlocked = false,
}) {
  context.push(
    RouteNames.profileDetail,
    extra: ProfileDetailArgs(profile, heroTag: heroTag, isBlocked: isBlocked),
  );
}
