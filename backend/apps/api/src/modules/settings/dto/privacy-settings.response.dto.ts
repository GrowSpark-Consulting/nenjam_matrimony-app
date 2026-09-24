/**
 * Response for `GET /settings` and `PATCH /settings/privacy`.
 *
 * Every flag here is the EFFECTIVE value — what the backend actually enforces —
 * not merely what is stored. While `ALLOW_FREE_PRIVACY_CONTROLS` is on, both
 * flags are the stored value for every member. Otherwise both are
 * premium-only and always read `false` without an active premium
 * subscription, because discovery and the photo gate ignore them.
 */
export interface PrivacySettingsResponse {
  /** Whether the caller has an active premium subscription, derived from
   *  their UserSubscription rows on every request — never client-supplied.
   *  Reported as-is; unlocking the privacy controls never changes it. */
  isPremium: boolean;
  /** Hidden from Discover, Search, Near Me and the weekly digest. */
  hideMyProfile: boolean;
  /** Photos withheld from members who aren't accepted connections. */
  hidePhotosFromNonConnections: boolean;
  /** @deprecated The pre-premium name of `hideMyProfile` (same column, same
   *  value), kept so app builds that still read it keep working. */
  profileVisibleToPremiumOnly: boolean;
}
