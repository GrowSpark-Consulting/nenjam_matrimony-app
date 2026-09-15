import '../../../location/domain/models/location_models.dart';

/// A religion or community from the backend's reference data.
///
/// This is [LocationOption] under a name that fits the second cascade. The
/// shape a reference-data option needs is identical at every level of both
/// hierarchies — a stable `code` to store, a `label` to show, and the
/// `parentCode` that scopes it — so aliasing the existing class reuses the
/// model, `resolveStoredLocation` and the whole picker widget without
/// duplicating any of them.
///
/// The name says "Location" because location was the first cascade to need
/// it, not because the class is location-specific. Renaming it to something
/// neutral (`ReferenceOption`) is worth doing, but it would touch every
/// location file, so it is left as follow-up rather than folded into this
/// change.
///
/// Resolving a stored (code, label) pair against what the API returned is
/// done with `resolveStoredLocation` — same semantics, and the reason it
/// matters here is the same: every profile written before this existed stores
/// `religion` and `community` as free text with no code, so the stored label
/// is matched against the API's own list rather than being invented.
typedef ReligionOption = LocationOption;
