import '../../../registration/domain/models/profile_draft.dart';

/// The saved partner-preference **base fields** — the 10 columns that live
/// directly on the backend's `partner_preferences` row and that the
/// Discover/Search feed filter and compatibility scorer actually read:
/// age range, height range, religion, caste, education, occupation, income,
/// location, mother tongue, marital status.
///
/// `GET`/`PUT /discover/preferences` — the endpoint this repository talks
/// to — has no concept of [PartnerPreference.extended] (the advanced
/// religion/education/family/lifestyle/location/special-case/verification
/// fields the standalone Partner Preferences page also edits). That data is
/// a separate JSON column (`partner_preferences.extended_preferences`)
/// written only by the registration draft's materialize step, and this
/// repository does not touch it:
///
///  * [getPreferences] always returns `extended` empty
///    (`const PartnerPreferenceExtended()`) — it carries no information
///    about the caller's actual saved extended preferences.
///  * [updatePreferences] ignores whatever is set on the argument's
///    `extended` — it is never sent to the backend.
///
/// Callers that need both must track `extended` separately (see
/// `PartnerPreferencesPage`, which merges this repository's base fields
/// with `extended` sourced from the registration draft).
abstract interface class PartnerPreferencesRepository {
  /// `GET /discover/preferences`. Never 404s — a member who has never saved
  /// preferences gets the backend's schema defaults (see
  /// `PreferencesService.DEFAULTS`), so the form always has something valid
  /// to render.
  Future<PartnerPreference> getPreferences();

  /// `PUT /discover/preferences`. Partial update: only the fields present
  /// and non-empty on [preferences] are sent, so leaving a field unset here
  /// never clears an already-saved value. Returns the backend's
  /// post-write state (authoritative — not an echo of [preferences]).
  Future<PartnerPreference> updatePreferences(PartnerPreference preferences);
}
