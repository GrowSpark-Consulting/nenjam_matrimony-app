/// Advanced Partner Preference fields — everything beyond the original 10
/// base fields on `PartnerPreference` (registration/domain/models/
/// profile_draft.dart). Kept as a nested object (`PartnerPreference.extended`)
/// rather than flattened, so the base fields' shape — and every existing
/// call site that constructs a `PartnerPreference` — stays untouched.
///
/// Mirrors backend/apps/api/src/modules/profiles/dto/partner-preference.dto.ts
/// `extended` (a permissive `Record<string, unknown>`, stored as-is in the
/// `partner_preferences.extended_preferences` JSON column).
library;

/// Matching-engine importance for a given criterion. Not every field needs
/// one — plain boolean filters (verification flags, willingToRelocate) are
/// self-describing: "on" already means "required". This applies to the
/// selectable criteria in [PartnerPreferenceExtended.requirements] (and,
/// via the same keys, to the base 10 fields on `PartnerPreference`).
///
/// The matching engine interprets these as:
///  - [required]  — hard filter: candidates that don't match are excluded.
///  - [optional]  — soft preference: used for ranking/scoring, never excludes.
///
/// [doesntMatter] is a **legacy value only** — the importance selector used
/// to offer Required/Optional/Doesn't Matter as three UI options, but was
/// simplified to just Required/Optional. It's kept here purely so
/// previously-saved backend/local data (or an old app build) that still has
/// `"doesntMatter"` in a `requirements` map deserializes without error.
/// [normalized] is how that legacy value gets folded into [optional] — the
/// UI never shows it and never writes it back out.
enum PreferenceRequirement {
  required,
  optional,
  doesntMatter;

  static PreferenceRequirement fromName(String? name) =>
      PreferenceRequirement.values.firstWhere(
        (e) => e.name == name,
        orElse: () => PreferenceRequirement.optional,
      );

  /// Collapses the legacy [doesntMatter] value down to [optional] — the
  /// only two values the UI (and newly-saved data) ever use.
  PreferenceRequirement get normalized =>
      this == PreferenceRequirement.doesntMatter ? PreferenceRequirement.optional : this;
}

/// Acceptance tri-state used by the "Special Cases" fields (Divorced
/// Accepted, Widowed Accepted, etc.): distinct from [PreferenceRequirement]
/// because these aren't a value + importance pair, just "will you consider
/// this?" with an explicit opt-out.
enum AcceptancePreference {
  accepted,
  notAccepted,
  doesntMatter;

  static AcceptancePreference fromName(String? name) =>
      AcceptancePreference.values.firstWhere(
        (e) => e.name == name,
        orElse: () => AcceptancePreference.doesntMatter,
      );
}

class PartnerPreferenceExtended {
  // ─── Religion & Community ─────────────────────────────────────────
  final String ethnicity;
  final String subCaste;
  final String mangalikStatus;

  // ─── Education & Career ────────────────────────────────────────────
  final String minEducation;
  final List<String> preferredEducationLevels;
  final String preferredColleges;
  final String fieldOfStudy;
  final String industry;
  final String employmentType;

  // ─── Family ─────────────────────────────────────────────────────────
  final String familyStatusPref;
  final String familyTypePref;
  final String familyValuesPref;

  // ─── Profile ────────────────────────────────────────────────────────
  final String profileManagedBy;

  // ─── Lifestyle ──────────────────────────────────────────────────────
  final String diet;
  final String drinking;
  final String smoking;

  // ─── Location ───────────────────────────────────────────────────────
  final String country;
  final String state;
  final String city;
  final bool willingToRelocate;
  final bool nriAccepted;

  // ─── Special Cases (optional, skippable) ───────────────────────────
  final AcceptancePreference divorcedAccepted;
  final AcceptancePreference widowedAccepted;
  final AcceptancePreference awaitingDivorceAccepted;
  final AcceptancePreference physicallyChallengedAccepted;
  final bool anySpecialCase;

  // ─── Verification / Other filters ──────────────────────────────────
  final bool horoscopeMatchRequired;
  final bool verifiedProfilesOnly;
  final bool hasProfilePhoto;
  final bool hasHoroscope;
  final bool aadhaarVerified;
  final bool phoneVerified;

  /// Matching-engine importance per criterion, keyed by a logical field
  /// name (e.g. 'religion', 'caste', 'education', 'income', 'motherTongue',
  /// 'maritalStatus', 'mangalik', 'diet', 'age', 'height'). Missing keys
  /// default to [PreferenceRequirement.optional].
  final Map<String, PreferenceRequirement> requirements;

  const PartnerPreferenceExtended({
    this.ethnicity = '',
    this.subCaste = '',
    this.mangalikStatus = '',
    this.minEducation = '',
    this.preferredEducationLevels = const [],
    this.preferredColleges = '',
    this.fieldOfStudy = '',
    this.industry = '',
    this.employmentType = '',
    this.familyStatusPref = '',
    this.familyTypePref = '',
    this.familyValuesPref = '',
    this.profileManagedBy = '',
    this.diet = '',
    this.drinking = '',
    this.smoking = '',
    this.country = '',
    this.state = '',
    this.city = '',
    this.willingToRelocate = false,
    this.nriAccepted = false,
    this.divorcedAccepted = AcceptancePreference.doesntMatter,
    this.widowedAccepted = AcceptancePreference.doesntMatter,
    this.awaitingDivorceAccepted = AcceptancePreference.doesntMatter,
    this.physicallyChallengedAccepted = AcceptancePreference.doesntMatter,
    this.anySpecialCase = false,
    this.horoscopeMatchRequired = false,
    this.verifiedProfilesOnly = false,
    this.hasProfilePhoto = false,
    this.hasHoroscope = false,
    this.aadhaarVerified = false,
    this.phoneVerified = false,
    this.requirements = const {},
  });

  PartnerPreferenceExtended copyWith({
    String? ethnicity,
    String? subCaste,
    String? mangalikStatus,
    String? minEducation,
    List<String>? preferredEducationLevels,
    String? preferredColleges,
    String? fieldOfStudy,
    String? industry,
    String? employmentType,
    String? familyStatusPref,
    String? familyTypePref,
    String? familyValuesPref,
    String? profileManagedBy,
    String? diet,
    String? drinking,
    String? smoking,
    String? country,
    String? state,
    String? city,
    bool? willingToRelocate,
    bool? nriAccepted,
    AcceptancePreference? divorcedAccepted,
    AcceptancePreference? widowedAccepted,
    AcceptancePreference? awaitingDivorceAccepted,
    AcceptancePreference? physicallyChallengedAccepted,
    bool? anySpecialCase,
    bool? horoscopeMatchRequired,
    bool? verifiedProfilesOnly,
    bool? hasProfilePhoto,
    bool? hasHoroscope,
    bool? aadhaarVerified,
    bool? phoneVerified,
    Map<String, PreferenceRequirement>? requirements,
  }) {
    return PartnerPreferenceExtended(
      ethnicity: ethnicity ?? this.ethnicity,
      subCaste: subCaste ?? this.subCaste,
      mangalikStatus: mangalikStatus ?? this.mangalikStatus,
      minEducation: minEducation ?? this.minEducation,
      preferredEducationLevels:
          preferredEducationLevels ?? this.preferredEducationLevels,
      preferredColleges: preferredColleges ?? this.preferredColleges,
      fieldOfStudy: fieldOfStudy ?? this.fieldOfStudy,
      industry: industry ?? this.industry,
      employmentType: employmentType ?? this.employmentType,
      familyStatusPref: familyStatusPref ?? this.familyStatusPref,
      familyTypePref: familyTypePref ?? this.familyTypePref,
      familyValuesPref: familyValuesPref ?? this.familyValuesPref,
      profileManagedBy: profileManagedBy ?? this.profileManagedBy,
      diet: diet ?? this.diet,
      drinking: drinking ?? this.drinking,
      smoking: smoking ?? this.smoking,
      country: country ?? this.country,
      state: state ?? this.state,
      city: city ?? this.city,
      willingToRelocate: willingToRelocate ?? this.willingToRelocate,
      nriAccepted: nriAccepted ?? this.nriAccepted,
      divorcedAccepted: divorcedAccepted ?? this.divorcedAccepted,
      widowedAccepted: widowedAccepted ?? this.widowedAccepted,
      awaitingDivorceAccepted:
          awaitingDivorceAccepted ?? this.awaitingDivorceAccepted,
      physicallyChallengedAccepted:
          physicallyChallengedAccepted ?? this.physicallyChallengedAccepted,
      anySpecialCase: anySpecialCase ?? this.anySpecialCase,
      horoscopeMatchRequired:
          horoscopeMatchRequired ?? this.horoscopeMatchRequired,
      verifiedProfilesOnly: verifiedProfilesOnly ?? this.verifiedProfilesOnly,
      hasProfilePhoto: hasProfilePhoto ?? this.hasProfilePhoto,
      hasHoroscope: hasHoroscope ?? this.hasHoroscope,
      aadhaarVerified: aadhaarVerified ?? this.aadhaarVerified,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      requirements: requirements ?? this.requirements,
    );
  }

  /// Sets/clears the requirement tag for [key], returning a new instance.
  /// Normalizes [value] first — the importance selector only ever offers
  /// Required/Optional, so nothing new is ever written as the legacy
  /// `doesntMatter` value, even if a stale caller somehow passes it in.
  PartnerPreferenceExtended withRequirement(
    String key,
    PreferenceRequirement value,
  ) {
    final next = Map<String, PreferenceRequirement>.from(requirements);
    next[key] = value.normalized;
    return copyWith(requirements: next);
  }

  /// The current importance for [key], with any legacy `doesntMatter` value
  /// (from data saved before the selector was simplified) folded into
  /// [PreferenceRequirement.optional].
  PreferenceRequirement requirementFor(String key) =>
      (requirements[key] ?? PreferenceRequirement.optional).normalized;

  factory PartnerPreferenceExtended.fromJson(Map<String, dynamic> json) {
    final rawRequirements = json['requirements'];
    return PartnerPreferenceExtended(
      ethnicity: json['ethnicity'] as String? ?? '',
      subCaste: json['subCaste'] as String? ?? '',
      mangalikStatus: json['mangalikStatus'] as String? ?? '',
      minEducation: json['minEducation'] as String? ?? '',
      preferredEducationLevels:
          (json['preferredEducationLevels'] as List?)?.cast<String>() ??
              const [],
      preferredColleges: json['preferredColleges'] as String? ?? '',
      fieldOfStudy: json['fieldOfStudy'] as String? ?? '',
      industry: json['industry'] as String? ?? '',
      employmentType: json['employmentType'] as String? ?? '',
      familyStatusPref: json['familyStatusPref'] as String? ?? '',
      familyTypePref: json['familyTypePref'] as String? ?? '',
      familyValuesPref: json['familyValuesPref'] as String? ?? '',
      profileManagedBy: json['profileManagedBy'] as String? ?? '',
      diet: json['diet'] as String? ?? '',
      drinking: json['drinking'] as String? ?? '',
      smoking: json['smoking'] as String? ?? '',
      country: json['country'] as String? ?? '',
      state: json['state'] as String? ?? '',
      city: json['city'] as String? ?? '',
      willingToRelocate: json['willingToRelocate'] as bool? ?? false,
      nriAccepted: json['nriAccepted'] as bool? ?? false,
      divorcedAccepted:
          AcceptancePreference.fromName(json['divorcedAccepted'] as String?),
      widowedAccepted:
          AcceptancePreference.fromName(json['widowedAccepted'] as String?),
      awaitingDivorceAccepted: AcceptancePreference.fromName(
          json['awaitingDivorceAccepted'] as String?),
      physicallyChallengedAccepted: AcceptancePreference.fromName(
          json['physicallyChallengedAccepted'] as String?),
      anySpecialCase: json['anySpecialCase'] as bool? ?? false,
      horoscopeMatchRequired:
          json['horoscopeMatchRequired'] as bool? ?? false,
      verifiedProfilesOnly: json['verifiedProfilesOnly'] as bool? ?? false,
      hasProfilePhoto: json['hasProfilePhoto'] as bool? ?? false,
      hasHoroscope: json['hasHoroscope'] as bool? ?? false,
      aadhaarVerified: json['aadhaarVerified'] as bool? ?? false,
      phoneVerified: json['phoneVerified'] as bool? ?? false,
      requirements: rawRequirements is Map
          ? rawRequirements.map((key, value) => MapEntry(
                key as String,
                PreferenceRequirement.fromName(value as String?),
              ))
          : const {},
    );
  }

  Map<String, dynamic> toJson() => {
        if (ethnicity.isNotEmpty) 'ethnicity': ethnicity,
        if (subCaste.isNotEmpty) 'subCaste': subCaste,
        if (mangalikStatus.isNotEmpty) 'mangalikStatus': mangalikStatus,
        if (minEducation.isNotEmpty) 'minEducation': minEducation,
        if (preferredEducationLevels.isNotEmpty)
          'preferredEducationLevels': preferredEducationLevels,
        if (preferredColleges.isNotEmpty)
          'preferredColleges': preferredColleges,
        if (fieldOfStudy.isNotEmpty) 'fieldOfStudy': fieldOfStudy,
        if (industry.isNotEmpty) 'industry': industry,
        if (employmentType.isNotEmpty) 'employmentType': employmentType,
        if (familyStatusPref.isNotEmpty) 'familyStatusPref': familyStatusPref,
        if (familyTypePref.isNotEmpty) 'familyTypePref': familyTypePref,
        if (familyValuesPref.isNotEmpty) 'familyValuesPref': familyValuesPref,
        if (profileManagedBy.isNotEmpty) 'profileManagedBy': profileManagedBy,
        if (diet.isNotEmpty) 'diet': diet,
        if (drinking.isNotEmpty) 'drinking': drinking,
        if (smoking.isNotEmpty) 'smoking': smoking,
        if (country.isNotEmpty) 'country': country,
        if (state.isNotEmpty) 'state': state,
        if (city.isNotEmpty) 'city': city,
        'willingToRelocate': willingToRelocate,
        'nriAccepted': nriAccepted,
        if (divorcedAccepted != AcceptancePreference.doesntMatter)
          'divorcedAccepted': divorcedAccepted.name,
        if (widowedAccepted != AcceptancePreference.doesntMatter)
          'widowedAccepted': widowedAccepted.name,
        if (awaitingDivorceAccepted != AcceptancePreference.doesntMatter)
          'awaitingDivorceAccepted': awaitingDivorceAccepted.name,
        if (physicallyChallengedAccepted != AcceptancePreference.doesntMatter)
          'physicallyChallengedAccepted': physicallyChallengedAccepted.name,
        'anySpecialCase': anySpecialCase,
        'horoscopeMatchRequired': horoscopeMatchRequired,
        'verifiedProfilesOnly': verifiedProfilesOnly,
        'hasProfilePhoto': hasProfilePhoto,
        'hasHoroscope': hasHoroscope,
        'aadhaarVerified': aadhaarVerified,
        'phoneVerified': phoneVerified,
        // Normalized on the way out — new data only ever persists
        // Required/Optional, even if a legacy `doesntMatter` value is still
        // sitting unmodified in `requirements` from before the importance
        // selector was simplified.
        if (requirements.isNotEmpty)
          'requirements': requirements.map(
            (key, value) => MapEntry(key, value.normalized.name),
          ),
      };

  bool get isEmpty =>
      ethnicity.isEmpty &&
      subCaste.isEmpty &&
      mangalikStatus.isEmpty &&
      minEducation.isEmpty &&
      preferredEducationLevels.isEmpty &&
      preferredColleges.isEmpty &&
      fieldOfStudy.isEmpty &&
      industry.isEmpty &&
      employmentType.isEmpty &&
      familyStatusPref.isEmpty &&
      familyTypePref.isEmpty &&
      familyValuesPref.isEmpty &&
      profileManagedBy.isEmpty &&
      diet.isEmpty &&
      drinking.isEmpty &&
      smoking.isEmpty &&
      country.isEmpty &&
      state.isEmpty &&
      city.isEmpty &&
      !willingToRelocate &&
      !nriAccepted &&
      divorcedAccepted == AcceptancePreference.doesntMatter &&
      widowedAccepted == AcceptancePreference.doesntMatter &&
      awaitingDivorceAccepted == AcceptancePreference.doesntMatter &&
      physicallyChallengedAccepted == AcceptancePreference.doesntMatter &&
      !anySpecialCase &&
      !horoscopeMatchRequired &&
      !verifiedProfilesOnly &&
      !hasProfilePhoto &&
      !hasHoroscope &&
      !aadhaarVerified &&
      !phoneVerified &&
      requirements.isEmpty;
}
