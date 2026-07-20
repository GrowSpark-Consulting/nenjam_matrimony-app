import 'package:flutter/material.dart';

import '../../../discover/domain/entities/discovery_profile_entity.dart';

const _defaultAgeRange = RangeValues(18, 60);

/// All criteria selectable in the Search advanced-filter sheet.
///
/// Fields that have no corresponding property on [DiscoveryProfileEntity]
/// yet (gender, country, state, annual income, smoking, drinking, rashi,
/// star, income-verified) are still captured here so the sheet's UI and
/// "Apply/Reset" behaviour work end-to-end — see [matches] for exactly
/// which criteria are applied today versus pending a backend/entity field.
@immutable
class SearchFilters {
  final RangeValues ageRange;
  final String? heightMin;
  final String? heightMax;
  final String? gender;
  final String? religion;
  final String? caste;
  final String? community;
  final String? country;
  final String? state;
  final String? city;
  final String? education;
  final String? occupation;
  final String? annualIncome;
  final String? diet;
  final String? smoking;
  final String? drinking;
  final String? rashi;
  final String? star;
  final bool horoscopeAvailable;
  final bool aadhaarVerified;
  final bool incomeVerified;
  final bool nriVerified;
  final bool premiumOnly;
  final bool withPhoto;
  final bool completedProfile;

  const SearchFilters({
    this.ageRange = _defaultAgeRange,
    this.heightMin,
    this.heightMax,
    this.gender,
    this.religion,
    this.caste,
    this.community,
    this.country,
    this.state,
    this.city,
    this.education,
    this.occupation,
    this.annualIncome,
    this.diet,
    this.smoking,
    this.drinking,
    this.rashi,
    this.star,
    this.horoscopeAvailable = false,
    this.aadhaarVerified = false,
    this.incomeVerified = false,
    this.nriVerified = false,
    this.premiumOnly = false,
    this.withPhoto = false,
    this.completedProfile = false,
  });

  const SearchFilters.empty() : this();

  bool get isEmpty => this == const SearchFilters.empty();

  /// Count of active criteria — drives the filter button's badge.
  int get activeCount {
    var count = 0;
    if (ageRange != _defaultAgeRange) count++;
    if (heightMin != null) count++;
    if (heightMax != null) count++;
    if (gender != null) count++;
    if (religion != null) count++;
    if (caste != null) count++;
    if (community != null) count++;
    if (country != null) count++;
    if (state != null) count++;
    if (city != null) count++;
    if (education != null) count++;
    if (occupation != null) count++;
    if (annualIncome != null) count++;
    if (diet != null) count++;
    if (smoking != null) count++;
    if (drinking != null) count++;
    if (rashi != null) count++;
    if (star != null) count++;
    if (horoscopeAvailable) count++;
    if (aadhaarVerified) count++;
    if (incomeVerified) count++;
    if (nriVerified) count++;
    if (premiumOnly) count++;
    if (withPhoto) count++;
    if (completedProfile) count++;
    return count;
  }

  SearchFilters copyWith({
    RangeValues? ageRange,
    String? heightMin,
    bool clearHeightMin = false,
    String? heightMax,
    bool clearHeightMax = false,
    String? gender,
    bool clearGender = false,
    String? religion,
    bool clearReligion = false,
    String? caste,
    bool clearCaste = false,
    String? community,
    bool clearCommunity = false,
    String? country,
    bool clearCountry = false,
    String? state,
    bool clearState = false,
    String? city,
    bool clearCity = false,
    String? education,
    bool clearEducation = false,
    String? occupation,
    bool clearOccupation = false,
    String? annualIncome,
    bool clearAnnualIncome = false,
    String? diet,
    bool clearDiet = false,
    String? smoking,
    bool clearSmoking = false,
    String? drinking,
    bool clearDrinking = false,
    String? rashi,
    bool clearRashi = false,
    String? star,
    bool clearStar = false,
    bool? horoscopeAvailable,
    bool? aadhaarVerified,
    bool? incomeVerified,
    bool? nriVerified,
    bool? premiumOnly,
    bool? withPhoto,
    bool? completedProfile,
  }) {
    return SearchFilters(
      ageRange: ageRange ?? this.ageRange,
      heightMin: clearHeightMin ? null : (heightMin ?? this.heightMin),
      heightMax: clearHeightMax ? null : (heightMax ?? this.heightMax),
      gender: clearGender ? null : (gender ?? this.gender),
      religion: clearReligion ? null : (religion ?? this.religion),
      caste: clearCaste ? null : (caste ?? this.caste),
      community: clearCommunity ? null : (community ?? this.community),
      country: clearCountry ? null : (country ?? this.country),
      state: clearState ? null : (state ?? this.state),
      city: clearCity ? null : (city ?? this.city),
      education: clearEducation ? null : (education ?? this.education),
      occupation: clearOccupation ? null : (occupation ?? this.occupation),
      annualIncome: clearAnnualIncome ? null : (annualIncome ?? this.annualIncome),
      diet: clearDiet ? null : (diet ?? this.diet),
      smoking: clearSmoking ? null : (smoking ?? this.smoking),
      drinking: clearDrinking ? null : (drinking ?? this.drinking),
      rashi: clearRashi ? null : (rashi ?? this.rashi),
      star: clearStar ? null : (star ?? this.star),
      horoscopeAvailable: horoscopeAvailable ?? this.horoscopeAvailable,
      aadhaarVerified: aadhaarVerified ?? this.aadhaarVerified,
      incomeVerified: incomeVerified ?? this.incomeVerified,
      nriVerified: nriVerified ?? this.nriVerified,
      premiumOnly: premiumOnly ?? this.premiumOnly,
      withPhoto: withPhoto ?? this.withPhoto,
      completedProfile: completedProfile ?? this.completedProfile,
    );
  }

  /// Extracts the centimetre figure embedded in height strings shaped like
  /// `'5 ft 8 in (172 cm)'` (the format shared by [NmHeightSelector] and
  /// [DiscoveryProfileEntity.height]).
  static int? _heightCm(String value) {
    final match = RegExp(r'(\d+)\s*cm').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// Whether [profile] satisfies every criterion this instance can actually
  /// evaluate against [DiscoveryProfileEntity]'s fields.
  ///
  /// TODO(backend): gender, country, state, annualIncome, smoking, drinking,
  /// rashi, star and incomeVerified have no corresponding field on the
  /// entity yet, so they're captured in state (and shown in [activeCount])
  /// but intentionally not applied below until a real field/API exists.
  bool matches(DiscoveryProfileEntity profile) {
    if (profile.age < ageRange.start || profile.age > ageRange.end) return false;

    final profileHeightCm = _heightCm(profile.height);
    if (profileHeightCm != null) {
      if (heightMin != null) {
        final min = _heightCm(heightMin!);
        if (min != null && profileHeightCm < min) return false;
      }
      if (heightMax != null) {
        final max = _heightCm(heightMax!);
        if (max != null && profileHeightCm > max) return false;
      }
    }

    if (religion != null && profile.religion != religion) return false;
    if (caste != null && profile.caste != caste) return false;
    if (community != null && profile.community != community) return false;
    if (city != null && !profile.location.toLowerCase().contains(city!.toLowerCase())) {
      return false;
    }
    if (education != null && profile.education != education) return false;
    if (occupation != null && profile.profession != occupation) return false;
    if (diet != null && profile.diet != diet) return false;
    if (horoscopeAvailable && !profile.horoscopeAvailable) return false;
    if (aadhaarVerified && !profile.isVerified) return false;
    if (nriVerified && !profile.tags.contains('NRI')) return false;
    if (premiumOnly && !profile.isPremium) return false;
    if (withPhoto && profile.photoUrls.isEmpty) return false;
    if (completedProfile && !profile.isPsychologyCompleted) return false;

    return true;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SearchFilters &&
        other.ageRange == ageRange &&
        other.heightMin == heightMin &&
        other.heightMax == heightMax &&
        other.gender == gender &&
        other.religion == religion &&
        other.caste == caste &&
        other.community == community &&
        other.country == country &&
        other.state == state &&
        other.city == city &&
        other.education == education &&
        other.occupation == occupation &&
        other.annualIncome == annualIncome &&
        other.diet == diet &&
        other.smoking == smoking &&
        other.drinking == drinking &&
        other.rashi == rashi &&
        other.star == star &&
        other.horoscopeAvailable == horoscopeAvailable &&
        other.aadhaarVerified == aadhaarVerified &&
        other.incomeVerified == incomeVerified &&
        other.nriVerified == nriVerified &&
        other.premiumOnly == premiumOnly &&
        other.withPhoto == withPhoto &&
        other.completedProfile == completedProfile;
  }

  @override
  int get hashCode => Object.hashAll([
        ageRange,
        heightMin,
        heightMax,
        gender,
        religion,
        caste,
        community,
        country,
        state,
        city,
        education,
        occupation,
        annualIncome,
        diet,
        smoking,
        drinking,
        rashi,
        star,
        horoscopeAvailable,
        aadhaarVerified,
        incomeVerified,
        nriVerified,
        premiumOnly,
        withPhoto,
        completedProfile,
      ]);
}
