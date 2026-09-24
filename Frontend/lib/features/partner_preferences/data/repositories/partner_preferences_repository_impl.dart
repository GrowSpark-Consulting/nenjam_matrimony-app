import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../registration/domain/models/profile_draft.dart';
import '../../../registration/presentation/utils/partner_preference_labels.dart';
import '../../domain/models/partner_preference_extended.dart';
import '../../domain/repositories/partner_preferences_repository.dart';

/// Real backend implementation of [PartnerPreferencesRepository], over
/// `GET`/`PUT /discover/preferences`.
///
/// Carries BOTH halves of the model: the 10 base fields below, and
/// [PartnerPreference.extended] — the advanced religion/education/family/
/// lifestyle/location/verification preferences — which ride as one JSON
/// object under `extended` and land in
/// `partner_preferences.extended_preferences`.
///
/// The 10 base fields are free-text range/single-choice **strings** on the
/// Flutter side (`"26-30"`, `"Same Caste"`, `"10-20 Lakhs"`, …) but numeric
/// min/max ints and string arrays on the wire
/// (`UpdatePartnerPreferenceDto`/`PartnerPreferenceResponseDto` — see
/// `backend/apps/api/src/modules/matches/dto/partner-preference.dto.ts`).
/// Every parse/format helper below is a direct Dart port of the backend's
/// own conversion functions in `profiles/services/profile.service.ts`
/// (`parseIntRange`, `parseHeightRangeToCm`, `parseLeadingNumber`,
/// `toStringArray`) — same regexes, same rounding, so a value round-trips
/// identically however it was written. Age uses the exact format
/// `age_range_sheet.dart`'s `parseAgeRange` already relies on; keep the two
/// in sync if either changes.
class PartnerPreferencesRepositoryImpl implements PartnerPreferencesRepository {
  PartnerPreferencesRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<PartnerPreference> getPreferences() async {
    final response =
        await _apiClient.get<Map<String, dynamic>>(ApiEndpoints.discoverPreferences);
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    return _fromResponse(data);
  }

  @override
  Future<PartnerPreference> updatePreferences(PartnerPreference preferences) async {
    final response = await _apiClient.put<Map<String, dynamic>>(
      ApiEndpoints.discoverPreferences,
      data: _toRequestBody(preferences),
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    return _fromResponse(data);
  }

  // ─── Flutter -> backend (PUT body) ─────────────────────────────────
  //
  // UpdatePartnerPreferenceDto: every field @IsOptional(). Two different
  // "nothing"s, and they must not be confused:
  //
  //  * an UNSET local value ("") is omitted — a partial PUT never touches a
  //    field the member didn't;
  //  * an explicit "Any" is sent as `null`, which CLEARS the saved limit.
  //
  // "Any" used to be omitted too, so it could never remove a range once saved.

  Map<String, dynamic> _toRequestBody(PartnerPreference p) {
    final ageRange = _parseIntRange(p.preferredAgeRange);
    final heightRange = _parseHeightRangeToCm(p.preferredHeightRange);
    final minIncome = _parseLeadingNumber(p.incomePref);

    return {
      if (ageRange != null) ...{
        'minAge': ageRange.$1,
        'maxAge': ageRange.$2,
      } else if (_isAny(p.preferredAgeRange)) ...{
        'minAge': null,
        'maxAge': null,
      },
      if (heightRange != null) ...{
        'minHeightCm': heightRange.$1,
        'maxHeightCm': heightRange.$2,
      } else if (_isAny(p.preferredHeightRange)) ...{
        'minHeightCm': null,
        'maxHeightCm': null,
      },
      if (minIncome != null)
        'minIncomeLakhs': minIncome
      else if (_isAny(p.incomePref))
        'minIncomeLakhs': null,
      ..._arrayField('preferredReligions', p.religionPref),
      ..._arrayField('preferredCastes', p.castePref),
      ..._arrayField('preferredMotherTongues', p.motherTonguePref),
      ..._arrayField('preferredEducation', p.educationPref),
      ..._arrayField('preferredOccupations', p.occupationPref),
      // The backend's own draft-materialize path stores this single
      // meta-choice/city string in `preferredCities`, never
      // `preferredStates` — see partner-preference-where.builder.ts's
      // comment on why "Same State" is still routed through this field.
      ..._arrayField('preferredCities', p.locationPref),
      ..._arrayField('maritalStatusPref', p.maritalStatusPref),
      // The advanced half, sent whole. The endpoint stores it wholesale in
      // `partner_preferences.extended_preferences` (supplying it replaces the
      // blob, omitting it leaves the saved one alone), and this page owns
      // every field in it — so the complete object is always the right thing
      // to send. Until the backend declared `extended`, sending it would have
      // been rejected outright by `forbidNonWhitelisted`, which is why these
      // edits used to be dropped on the floor.
      'extended': p.extended.toJson(),
    };
  }

  /// The picker's explicit "no limit" choice — as opposed to "" (untouched).
  bool _isAny(String value) => value.trim().toLowerCase() == 'any';

  /// `toStringArray` port: wraps a single non-empty value in a one-element
  /// array under `key`, or sends nothing at all when empty ("no preference"
  /// — never an explicit empty-array clear the user didn't ask for).
  Map<String, dynamic> _arrayField(String key, String value) =>
      value.isEmpty ? const {} : {key: [value]};

  // ─── backend -> Flutter (GET / PUT response) ───────────────────────

  PartnerPreference _fromResponse(Map<String, dynamic> data) {
    final minAge = (data['minAge'] as num?)?.toInt();
    final maxAge = (data['maxAge'] as num?)?.toInt();
    final minHeightCm = (data['minHeightCm'] as num?)?.toInt();
    final maxHeightCm = (data['maxHeightCm'] as num?)?.toInt();
    final minIncomeLakhs = (data['minIncomeLakhs'] as num?);

    return PartnerPreference(
      preferredAgeRange:
          minAge != null && maxAge != null ? '$minAge-$maxAge' : '',
      preferredHeightRange: _formatHeightRange(minHeightCm, maxHeightCm),
      religionPref: _firstOf(data['preferredReligions']),
      castePref: _firstOf(data['preferredCastes']),
      educationPref: _firstOf(data['preferredEducation']),
      occupationPref: _firstOf(data['preferredOccupations']),
      incomePref: _formatIncome(minIncomeLakhs),
      locationPref: _firstOf(data['preferredCities']),
      motherTonguePref: _firstOf(data['preferredMotherTongues']),
      maritalStatusPref: _firstOf(data['maritalStatusPref']),
      // The saved advanced preferences. Absent or malformed reads as empty
      // rather than throwing: a member who has never saved any gets `{}` from
      // the backend, and an older backend omits the key entirely.
      extended: _extendedOf(data['extended']),
    );
  }

  PartnerPreferenceExtended _extendedOf(dynamic value) {
    if (value is! Map) return const PartnerPreferenceExtended();
    return PartnerPreferenceExtended.fromJson(
      Map<String, dynamic>.from(value),
    );
  }

  String _firstOf(dynamic value) {
    if (value is! List || value.isEmpty) return '';
    final first = value.first;
    return first is String ? first : '';
  }

  /// No bound at all (null/null) is "no limit" and maps to "" — the same
  /// "Not set" placeholder a fresh [PartnerPreference] renders. (140/210 is
  /// the old stamped default, cleared by migration; treated the same in case
  /// a row slipped through.) A saved value matching one of the picker's own
  /// presets round-trips to that preset's exact string — including the
  /// open-ended "6'0\"+", stored with no maximum (or 250 by older builds). A
  /// value that matches none of them falls back to "" rather than fabricating
  /// a label the picker sheet has no way to reselect.
  String _formatHeightRange(int? minCm, int? maxCm) {
    if (minCm == null && maxCm == null) return '';
    if (minCm == 140 && maxCm == 210) return '';
    for (final preset in partnerPrefHeightRanges) {
      if (preset == 'Any') continue;
      final parsed = _parseHeightRangeToCm(preset);
      if (parsed == null || parsed.$1 != minCm) continue;
      final openEnded = parsed.$2 == null;
      if (openEnded ? (maxCm == null || maxCm >= 250) : parsed.$2 == maxCm) {
        return preset;
      }
    }
    return '';
  }

  /// Same reasoning as [_formatHeightRange]: `null` (never set) maps to ""；
  /// a value matching a preset's lower bound exactly round-trips to that
  /// preset; anything else falls back to "" instead of a fabricated label.
  String _formatIncome(num? minIncomeLakhs) {
    if (minIncomeLakhs == null) return '';
    for (final preset in partnerPrefIncomes) {
      if (preset == 'Any') continue;
      if (_parseLeadingNumber(preset) == minIncomeLakhs.toDouble()) {
        return preset;
      }
    }
    return '';
  }

  // ─── Parsers — direct ports of profile.service.ts's helpers ───────

  /// `parseIntRange`'s regex, `/(\d+)\D+(\d+)/` — matches age_range_sheet
  /// .dart's `parseAgeRange` (which this deliberately mirrors rather than
  /// imports, to keep the data layer independent of a presentation-layer
  /// file). Returns null for "Any"/empty/unparseable, so the caller omits
  /// the field rather than sending a meaningless range.
  (int, int)? _parseIntRange(String value) {
    final match = RegExp(r'(\d+)\D+(\d+)').firstMatch(value);
    if (match == null) return null;
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  /// `parseLeadingNumber` port: the first number in the string, or null.
  double? _parseLeadingNumber(String value) {
    if (value.isEmpty) return null;
    final match = RegExp(r'(\d+(\.\d+)?)').firstMatch(value);
    return match != null ? double.parse(match.group(1)!) : null;
  }

  /// `parseHeightToCm` port: feet'inches" -> cm, falling back to a plain
  /// leading number (already-cm values).
  double? _parseHeightToCm(String value) {
    final feetInches = RegExp(r"(\d+)\s*'\s*(\d+)").firstMatch(value);
    if (feetInches != null) {
      final feet = int.parse(feetInches.group(1)!);
      final inches = int.parse(feetInches.group(2)!);
      return ((feet * 12 + inches) * 2.54).roundToDouble();
    }
    return _parseLeadingNumber(value);
  }

  /// `parseHeightRangeToCm` port: handles the picker's bucketed
  /// feet'inches ranges ("4'6\"-5'0\"") and open-ended ("6'0\"+"). "Any"
  /// and anything unparseable return null here — the caller decides whether
  /// that means "leave alone" (unset) or "clear" ("Any").
  ///
  /// An open-ended preset has no maximum: `(min, null)`, sent as a cleared
  /// upper bound — the same thing the backend seeds for it from a draft.
  (int, int?)? _parseHeightRangeToCm(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'any') return null;

    final plusMatch = RegExp(r'^(.+?)\+$').firstMatch(trimmed);
    if (plusMatch != null) {
      final min = _parseHeightToCm(plusMatch.group(1)!);
      return min != null ? (min.round(), null) : null;
    }

    final dashIndex = trimmed.indexOf('-');
    if (dashIndex > 0) {
      final min = _parseHeightToCm(trimmed.substring(0, dashIndex));
      final max = _parseHeightToCm(trimmed.substring(dashIndex + 1));
      if (min != null && max != null) return (min.round(), max.round());
    }
    return null;
  }
}
