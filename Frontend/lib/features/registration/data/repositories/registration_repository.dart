import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../domain/models/profile_draft.dart';

/// Thrown when the backend rejects a registration-wizard request (validation
/// error, unauthenticated, etc.) — carries the backend's own message when
/// available so the UI can show something more useful than "something went
/// wrong".
class RegistrationApiException implements Exception {
  RegistrationApiException(this.statusCode, this.message);
  final int? statusCode;
  final String message;

  @override
  String toString() => 'RegistrationApiException($statusCode): $message';
}

/// Talks to backend/apps/api/src/modules/profiles — one PATCH per wizard
/// step (1-10), matching [ApiEndpoints]'s profileDraft* constants, plus
/// finalize(). ApiClient is configured with `validateStatus: status < 500`,
/// so 4xx responses land here as normal Response objects rather than
/// exceptions — [_unwrap] is what turns those into a thrown exception.
class RegistrationRepository {
  RegistrationRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> getDraft() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.profileDraft,
    );
    return _unwrap(response.statusCode, response.data) ?? {};
  }

  Future<void> updateBasicDetails(BasicDetails details) =>
      _patchSection(ApiEndpoints.profileDraftBasicDetails, details.toJson());

  Future<void> updateReligionDetails(ReligionDetails details) => _patchSection(
      ApiEndpoints.profileDraftReligionDetails, details.toJson());

  Future<void> updateLanguageDetails(LanguageDetails details) => _patchSection(
      ApiEndpoints.profileDraftLanguageDetails, details.toJson());

  Future<void> updateLocationDetails(LocationDetails details) => _patchSection(
      ApiEndpoints.profileDraftLocationDetails, details.toJson());

  Future<void> updateEducationDetails(EducationDetails details) =>
      _patchSection(
          ApiEndpoints.profileDraftEducationDetails, details.toJson());

  Future<void> updatePhysicalDetails(PhysicalDetails details) => _patchSection(
      ApiEndpoints.profileDraftPhysicalDetails, details.toJson());

  Future<void> updateLifestyleDetails(LifestyleDetails details) =>
      _patchSection(
          ApiEndpoints.profileDraftLifestyleDetails, details.toJson());

  Future<void> updateFamilyDetails(FamilyDetails details) => _patchSection(
      ApiEndpoints.profileDraftFamilyDetails, details.toJson());

  Future<void> updateHoroscopeDetails(HoroscopeDetails details) =>
      _patchSection(
          ApiEndpoints.profileDraftHoroscopeDetails, details.toJson());

  Future<void> updatePartnerPreference(PartnerPreference details) =>
      _patchSection(
          ApiEndpoints.profileDraftPartnerPreference, details.toJson());

  /// Maps the draft (accumulated via the PATCH calls above) into the
  /// finalized profile. Idempotent on the backend — safe to call again if
  /// the user edits and resubmits.
  Future<Map<String, dynamic>> finalizeProfile() async {
    final response =
        await _apiClient.post<Map<String, dynamic>>(ApiEndpoints.profileFinalize);
    return _unwrap(response.statusCode, response.data) ?? {};
  }

  Future<void> _patchSection(String path, Map<String, dynamic> data) async {
    if (data.isEmpty) return; // nothing filled in on this step yet
    final response = await _apiClient.patch<Map<String, dynamic>>(
      path,
      data: data,
    );
    _unwrap(response.statusCode, response.data);
  }

  Map<String, dynamic>? _unwrap(int? statusCode, Map<String, dynamic>? data) {
    if (statusCode != null && statusCode >= 400) {
      final message = data?['message'];
      throw RegistrationApiException(
        statusCode,
        message is String
            ? message
            : message is List && message.isNotEmpty
                ? message.join(', ')
                : 'Request failed ($statusCode).',
      );
    }
    return data;
  }
}
