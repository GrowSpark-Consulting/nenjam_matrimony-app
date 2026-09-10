import 'package:flutter/foundation.dart';

/// A country, state/province or city from the backend's location master data.
///
/// All three share the same shape — a stable code to store and a label to
/// show — so one class serves all three rather than three near-identical
/// ones. [parentCode] is the country for a state, the state for a city, and
/// null for a country.
@immutable
class LocationOption {
  const LocationOption({
    required this.code,
    required this.label,
    this.parentCode,
    this.type,
  });

  /// The ISO 3166 code (`IN`, `IN-TN`) or, for a city, the deterministic
  /// `IN-TN-CHENNAI`. This is what gets stored on the profile — the label is
  /// display only, and may be translated or corrected later without
  /// invalidating anyone's saved answer.
  final String code;

  final String label;

  /// The country code for a state, the state code for a city.
  final String? parentCode;

  /// ISO's own wording for a subdivision — "State", "Union territory",
  /// "Province", "City-state". Null for countries and cities.
  final String? type;

  factory LocationOption.fromJson(Map<String, dynamic> json) {
    return LocationOption(
      code: json['code'] as String,
      label: json['label'] as String,
      // The API names the parent differently per level; accept whichever is
      // present rather than needing three model classes.
      parentCode: (json['stateCode'] ?? json['countryCode']) as String?,
      type: json['type'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'label': label,
        if (parentCode != null) 'parentCode': parentCode,
        if (type != null) 'type': type,
      };

  /// Round-trips a cached entry, which stores whatever [toJson] wrote.
  factory LocationOption.fromCacheJson(Map<String, dynamic> json) {
    return LocationOption(
      code: json['code'] as String,
      label: json['label'] as String,
      parentCode: json['parentCode'] as String?,
      type: json['type'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is LocationOption && other.code == code);

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'LocationOption($code, $label)';
}

/// A member's chosen location, as codes plus the labels to display.
///
/// Both halves are kept together deliberately: the code is what the profile
/// stores and what the server validates, while the label is what the member
/// sees — and a screen that has only codes would have to re-fetch the whole
/// dataset just to render "Chennai".
@immutable
class SelectedLocation {
  const SelectedLocation({
    this.country,
    this.state,
    this.city,
  });

  final LocationOption? country;
  final LocationOption? state;
  final LocationOption? city;

  bool get isComplete => country != null && state != null && city != null;

  /// Clearing a parent clears its children: a state means nothing without its
  /// country, and the server rejects that combination anyway.
  SelectedLocation withCountry(LocationOption? next) {
    if (next?.code == country?.code) return this;
    return SelectedLocation(country: next);
  }

  SelectedLocation withState(LocationOption? next) {
    if (next?.code == state?.code) return this;
    return SelectedLocation(country: country, state: next);
  }

  SelectedLocation withCity(LocationOption? next) =>
      SelectedLocation(country: country, state: state, city: next);
}
