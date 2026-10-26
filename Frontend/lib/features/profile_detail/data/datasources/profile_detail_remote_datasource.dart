import 'package:flutter/material.dart';

import '../../../../core/l10n/app_l10n.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../discover/data/models/discovery_profile_model.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../domain/entities/family_info_entity.dart';
import '../../domain/entities/horoscope_info_entity.dart';
import '../../domain/entities/lifestyle_info_entity.dart';
import '../../domain/entities/partner_preferences_entity.dart';
import '../../domain/entities/profile_detail_entity.dart';
import '../../domain/entities/verification_checklist_entity.dart';

/// Reads another member's full profile from `GET /discover/profiles/:userId`.
///
/// Every value shown on the detail screen is what that member saved. A field
/// they never filled in stays empty, and the section widgets already omit
/// empty rows. Nothing is derived, defaulted or invented to make a profile
/// look more complete than it is.
class ProfileDetailRemoteDataSource {
  const ProfileDetailRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  /// Throws [ApiException] on any failure, including the backend's 404 for a
  /// profile that is no longer visible to this member (blocked, deactivated,
  /// declined, ...). The page renders that as its error state with a retry,
  /// never as a blank profile.
  Future<ProfileDetailEntity> fetchProfileDetail(
    DiscoveryProfileEntity base,
  ) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.discoverProfile(base.id),
    );
    final data = unwrapOrThrow(response.statusCode, response.data);
    if (data == null) {
      throw ApiException(response.statusCode, 'Profile not available.');
    }
    return parseProfileDetail(base, data);
  }
}

/// Maps the endpoint's JSON onto [ProfileDetailEntity]. Public for tests.
///
/// [base] — the card the member tapped — stays the entity's `base`: it holds
/// the compatibility scores the feed computed, which the by-id endpoint does
/// not recompute. Every detail field is read from the fresh response, so
/// the screen shows the member's latest saved values.
ProfileDetailEntity parseProfileDetail(
  DiscoveryProfileEntity base,
  Map<String, dynamic> json,
) {
  final fresh = DiscoveryProfileModel.fromJson(json);
  final detail = _map(json['detail']);
  final family = _map(detail['family']);
  final horoscope = _map(detail['horoscope']);
  final prefJson = detail['partnerPreference'];

  return ProfileDetailEntity(
    base: base,
    maritalStatus: fresh.maritalStatus,
    motherTongue: fresh.motherTongue,
    interests: fresh.hobbies,
    // No profile field collects "core values" — left empty, so the About
    // section hides that list rather than showing invented ones.
    coreValues: const [],
    bio: fresh.bio.trim().isEmpty ? null : fresh.bio.trim(),
    family: FamilyInfoEntity(
      fatherName: _str(family['fatherName']),
      fatherOccupation: _str(family['fatherOccupation']),
      motherName: _str(family['motherName']),
      motherOccupation: _str(family['motherOccupation']),
      familyType: _str(family['familyType']),
      familyValues: _str(family['familyValues']),
      familyStatus: _str(family['familyStatus']),
      brothers: _int(family['brothers']) ?? 0,
      sisters: _int(family['sisters']) ?? 0,
    ),
    lifestyle: LifestyleInfoEntity(
      eatingHabit: fresh.diet,
      smoking: fresh.smoking,
      drinking: fresh.drinking,
      fitness: _str(detail['fitness']),
      physicalStatus: fresh.physicalStatus,
      hobbies: fresh.hobbies,
    ),
    horoscope: HoroscopeInfoEntity(
      rasi: _str(horoscope['rasi']),
      nakshatra: _str(horoscope['nakshatra']),
      dosham: _str(horoscope['dosham']),
      matchingEnabled: horoscope['horoscopeAvailable'] == true,
    ),
    partnerPreferences: prefJson is Map<String, dynamic>
        ? _partnerPreferences(prefJson)
        : const PartnerPreferencesEntity(),
    verification: VerificationChecklistEntity(
      // Only checks the backend actually reports. Email and government-ID
      // checks have no source on this endpoint (the KYC module is not wired
      // in), so they are not shown rather than shown with a guessed status.
      items: [
        VerificationItemEntity(
          icon: Icons.phone_iphone_rounded,
          label: AppL10n.current.fieldPhone,
          status: fresh.phoneVerified
              ? VerificationItemStatus.verified
              : VerificationItemStatus.incomplete,
        ),
        VerificationItemEntity(
          icon: Icons.face_rounded,
          label: AppL10n.current.fieldFaceMatch,
          status: fresh.isVerified
              ? VerificationItemStatus.verified
              : VerificationItemStatus.incomplete,
        ),
      ],
    ),
  );
}

PartnerPreferencesEntity _partnerPreferences(Map<String, dynamic> json) {
  final minIncome = (json['minIncomeLakhs'] as num?)?.toDouble();
  return PartnerPreferencesEntity(
    preferredAgeRange: _range(_int(json['minAge']), _int(json['maxAge'])),
    preferredHeightRange: _range(
      _int(json['minHeightCm']),
      _int(json['maxHeightCm']),
      format: _feetInches,
    ),
    religionPref: _list(json['religions']),
    castePref: _list(json['castes']),
    educationPref: _list(json['education']),
    occupationPref: _list(json['occupations']),
    incomePref: minIncome != null && minIncome > 0
        ? '${_trimZeros(minIncome)}+ LPA'
        : '',
    locationPref: _list([
      ...?(json['cities'] as List?),
      ...?(json['states'] as List?),
    ]),
    motherTonguePref: _list(json['motherTongues']),
    maritalStatusPref: _list(json['maritalStatuses']),
  );
}

/// "25-30", "25+", "Up to 30", or "" when neither bound was saved.
String _range(int? min, int? max, {String Function(int)? format}) {
  final f = format ?? (int v) => '$v';
  if (min != null && max != null) return '${f(min)}-${f(max)}';
  if (min != null) return '${f(min)}+';
  if (max != null) return 'Up to ${f(max)}';
  return '';
}

String _feetInches(int cm) {
  final totalInches = (cm / 2.54).round();
  return "${totalInches ~/ 12}'${totalInches % 12}\"";
}

String _trimZeros(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

Map<String, dynamic> _map(Object? v) =>
    v is Map<String, dynamic> ? v : const <String, dynamic>{};

String _str(Object? v) => v is String ? v.trim() : '';

int? _int(Object? v) => v is num ? v.toInt() : null;

String _list(Object? v) => v is List
    ? v.whereType<String>().where((s) => s.trim().isNotEmpty).join(', ')
    : '';
