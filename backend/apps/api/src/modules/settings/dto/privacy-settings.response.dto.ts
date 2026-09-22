/**
 * Response for `GET /settings` and `PATCH /settings/privacy`.
 *
 * Both privacy features are premium-only, so every flag here is the EFFECTIVE
 * value — what the backend actually enforces — not merely what is stored: for
 * a member without an active premium subscription they always read `false`,
 * because the feed/search/photo queries ignore them. The app therefore never
 * shows a non-premium member a privacy feature as switched on.
 */
export interface PrivacySettingsResponse {
  /** Whether the caller has an active premium subscription, derived from
   *  their UserSubscription rows on every request — never client-supplied.
   *  The app locks both toggles behind an upgrade prompt when false. */
  isPremium: boolean;
  /** Hidden from Discover, Search, Near Me and the weekly digest. */
  hideMyProfile: boolean;
  /** Photos withheld from members who aren't accepted connections. */
  hidePhotosFromNonConnections: boolean;
  /** @deprecated The pre-premium name of `hideMyProfile` (same column, same
   *  value), kept so app builds that still read it keep working. */
  profileVisibleToPremiumOnly: boolean;
}
