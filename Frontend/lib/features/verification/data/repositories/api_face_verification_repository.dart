import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/models/face_verification.dart';
import '../../domain/repositories/face_verification_repository.dart';

/// Real backend implementation over `ApiClient` — see
/// docs/development/selfie-verification-frontend-handoff.md §4 for the
/// exact contract this mirrors.
class ApiFaceVerificationRepository implements FaceVerificationRepository {
  ApiFaceVerificationRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<FaceVerificationState> getState() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.faceVerification,
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    return FaceVerificationState.fromJson(data);
  }

  @override
  Future<LivenessSessionTicket> startSession({required bool consent}) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.faceVerificationSessions,
      data: {'consent': consent},
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    return LivenessSessionTicket.fromJson(data);
  }

  @override
  Future<FaceVerificationResult> complete({
    required String attemptId,
    ClientLivenessOutcome? clientOutcome,
    String? clientErrorCode,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.faceVerificationComplete,
      data: {
        'attemptId': attemptId,
        if (clientOutcome != null) 'clientOutcome': clientOutcome.toJson(),
        if (clientErrorCode != null) 'clientErrorCode': clientErrorCode,
      },
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    return FaceVerificationResult.fromJson(data);
  }
}
