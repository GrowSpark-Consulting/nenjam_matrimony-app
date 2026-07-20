import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../registration/domain/models/profile_draft.dart';
import '../../domain/repositories/verification_repository.dart';

/// Real backend implementation — dormant, not wired to any provider.
///
/// TODO(backend): the `verification` controller is currently an empty
/// stub — zero routes, despite `ApiEndpoints.verifyId`/`.verifyPhoto`/
/// `.verificationStatus` all being defined. Like [PhotoRepositoryImpl],
/// `submitIdVerification`/`submitPhotoVerification` assume the client
/// already has a `documentUrl`/`photoUrl` from somewhere else — no
/// upload-transport endpoint exists for verification documents either.
class VerificationRepositoryImpl implements VerificationRepository {
  VerificationRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<VerificationStatus> getStatus() async {
    final response = await _apiClient
        .get<Map<String, dynamic>>(ApiEndpoints.verificationStatus);
    final data = unwrapOrThrow(response.statusCode, response.data);
    return VerificationStatus.fromJson(data ?? {});
  }

  @override
  Future<void> submitIdVerification({required String documentUrl}) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.verifyId,
      data: {'documentUrl': documentUrl},
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  @override
  Future<void> submitPhotoVerification({required String photoUrl}) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.verifyPhoto,
      data: {'photoUrl': photoUrl},
    );
    unwrapOrThrow(response.statusCode, response.data);
  }
}
