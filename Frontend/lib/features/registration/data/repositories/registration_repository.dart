import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/models/profile_draft.dart';

/// Kept as the name the wizard UI already catches (`on
/// RegistrationApiException catch (e)` in profile_wizard_page.dart,
/// profile_review_page.dart, registration_completing_page.dart) — same
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
    return unwrapOrThrow(response.statusCode, response.data) ?? {};
  }

  Future<void> _patchSection(String path, Map<String, dynamic> data) async {
    if (data.isEmpty) return; // nothing filled in on this step yet
    final response = await _apiClient.patch<Map<String, dynamic>>(
      path,
      data: data,
    );
    unwrapOrThrow(response.statusCode, response.data);
  }
}
