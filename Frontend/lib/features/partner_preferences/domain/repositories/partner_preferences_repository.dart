import '../../../registration/domain/models/profile_draft.dart';

/// The saved partner preferences, both halves of them.
///
///  * The 10 **base** fields — age range, height range, religion, caste,
///    education, occupation, income, location, mother tongue, marital status
///    — are columns on the backend's `partner_preferences` row, and are what
///    the Discover/Search feed filter and the compatibility scorer read.
///  * [PartnerPreference.extended] — the advanced religion/community,
///    education/career, family, lifestyle, location, special-case and
///    verification preferences — is one JSON object in
///    `partner_preferences.extended_preferences`. The feed reads it too: the
///    WHERE builder applies diet/smoking/drinking/country/ethnicity/subCaste
///    from it, and the lifestyle scoring signal weighs it.
///
/// Both travel over `GET`/`PUT /discover/preferences`, so this repository is
/// the whole story for the standalone Partner Preferences page — no caller
/// needs to source `extended` from anywhere else.
///
/// It was not always so: the endpoint had no `extended` field, the API
/// rejects undeclared keys outright, and the page's advanced edits were
/// therefore discarded on every save while the UI reported success.
abstract interface class PartnerPreferencesRepository {
  /// `GET /discover/preferences`. Never 404s — a member who has never saved
  /// preferences gets the backend's schema defaults (see
  /// `PreferencesService.DEFAULTS`), so the form always has something valid
  /// to render.
  Future<PartnerPreference> getPreferences();

  /// `PUT /discover/preferences`. Partial update for the base fields: only
  /// the ones present and non-empty on [preferences] are sent, so leaving a
  /// field unset here never clears an already-saved value. `extended` is the
  /// exception and is always sent whole, because the page owns every field in
  /// it. Returns the backend's post-write state (authoritative — not an echo
  /// of [preferences]), `extended` included.
  Future<PartnerPreference> updatePreferences(PartnerPreference preferences);
}
