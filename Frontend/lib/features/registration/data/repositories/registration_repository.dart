import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/story_perf.dart';
import '../../domain/models/profile_draft.dart';

/// Kept as the name the wizard UI already catches (`on
/// RegistrationApiException catch (e)` in profile_section_edit_page.dart
/// and registration_completing_page.dart) — same
/// shape as the shared [ApiException], just aliased so those call sites
/// didn't need to change when this repository moved onto the shared helper.
typedef RegistrationApiException = ApiException;

/// Talks to backend/apps/api/src/modules/profiles — one PATCH per wizard
/// step (1-10), matching [ApiEndpoints]'s profileDraft* constants, plus
/// finalize(). ApiClient is configured with `validateStatus: status < 500`,
/// so 4xx responses land here as normal Response objects rather than
/// exceptions — [unwrapOrThrow] is what turns those into a thrown exception.
class RegistrationRepository {
  RegistrationRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> getDraft() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.profileDraft,
    );
    return unwrapOrThrow(response.statusCode, response.data) ?? {};
  }

  Future<void> updateBasicDetails(
    BasicDetails details, {
    bool skipMaterialize = false,
  }) =>
      _patchSection(ApiEndpoints.profileDraftBasicDetails, details.toJson(),
          skipMaterialize: skipMaterialize);

  Future<void> updateReligionDetails(
    ReligionDetails details, {
    bool skipMaterialize = false,
  }) =>
      _patchSection(ApiEndpoints.profileDraftReligionDetails, details.toJson(),
          skipMaterialize: skipMaterialize);

  Future<void> updateLanguageDetails(
    LanguageDetails details, {
    bool skipMaterialize = false,
  }) =>
      _patchSection(ApiEndpoints.profileDraftLanguageDetails, details.toJson(),
          skipMaterialize: skipMaterialize);

  Future<void> updateLocationDetails(
    LocationDetails details, {
    bool skipMaterialize = false,
  }) =>
      _patchSection(ApiEndpoints.profileDraftLocationDetails, details.toJson(),
          skipMaterialize: skipMaterialize);

  Future<void> updateEducationDetails(
    EducationDetails details, {
    bool skipMaterialize = false,
  }) =>
      _patchSection(
          ApiEndpoints.profileDraftEducationDetails, details.toJson(),
          skipMaterialize: skipMaterialize);

  Future<void> updatePhysicalDetails(
    PhysicalDetails details, {
    bool skipMaterialize = false,
  }) =>
      _patchSection(ApiEndpoints.profileDraftPhysicalDetails, details.toJson(),
          skipMaterialize: skipMaterialize);

  Future<void> updateLifestyleDetails(
    LifestyleDetails details, {
    bool skipMaterialize = false,
  }) =>
      _patchSection(
          ApiEndpoints.profileDraftLifestyleDetails, details.toJson(),
          skipMaterialize: skipMaterialize);

  Future<void> updateFamilyDetails(
    FamilyDetails details, {
    bool skipMaterialize = false,
  }) =>
      _patchSection(ApiEndpoints.profileDraftFamilyDetails, details.toJson(),
          skipMaterialize: skipMaterialize);

  Future<void> updateHoroscopeDetails(
    HoroscopeDetails details, {
    bool skipMaterialize = false,
  }) =>
      _patchSection(
          ApiEndpoints.profileDraftHoroscopeDetails, details.toJson(),
          skipMaterialize: skipMaterialize);

  Future<void> updatePartnerPreference(
    PartnerPreference details, {
    bool skipMaterialize = false,
  }) =>
      _patchSection(
          ApiEndpoints.profileDraftPartnerPreference, details.toJson(),
          skipMaterialize: skipMaterialize);

  /// Maps the draft (accumulated via the PATCH calls above) into the
  /// finalized profile. Idempotent on the backend — safe to call again if
  /// the user edits and resubmits.
  Future<Map<String, dynamic>> finalizeProfile() async {
    StoryPerf.mark('Dio request started (finalize)');
    final response =
        await _apiClient.post<Map<String, dynamic>>(ApiEndpoints.profileFinalize);
    StoryPerf.mark('Dio response received (finalize)');
    return unwrapOrThrow(response.statusCode, response.data) ?? {};
  }

  Future<void> _patchSection(
    String path,
    Map<String, dynamic> data, {
    bool skipMaterialize = false,
  }) async {
    if (data.isEmpty) return; // nothing filled in on this step yet
    StoryPerf.mark('Dio request started ($path)');
    final response = await _apiClient.patch<Map<String, dynamic>>(
      path,
      data: data,
      queryParameters:
          skipMaterialize ? const {'skipMaterialize': 'true'} : null,
    );
    StoryPerf.mark('Dio response received ($path)');
    unwrapOrThrow(response.statusCode, response.data);
  }
}
