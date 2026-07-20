import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/repositories/photo_repository.dart';

/// Real backend implementation — dormant, not wired to any provider yet.
///
/// The two routes this calls are genuinely implemented on the backend
/// (unlike most other features' Api* repositories), but calling
/// [registerPhoto] today would require an `s3Key`/`cdnUrl` the client has
/// no way to obtain — no presigned-URL/upload-transport endpoint exists
/// (see backend/apps/api/src/modules/profiles/dto/photo-upload.dto.ts's own
/// comment). Nothing in the app calls this yet; wiring it in requires both
/// a UI decision (out of scope for this pass) and that upload-transport
/// endpoint to exist.
class PhotoRepositoryImpl implements PhotoRepository {
  PhotoRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<PhotoRecord>> getPhotos() async {
    final response =
        await _apiClient.get<List<dynamic>>(ApiEndpoints.profileMePhotos);
    final data = unwrapOrThrow(response.statusCode, response.data);
    return (data ?? [])
        .cast<Map<String, dynamic>>()
        .map(PhotoRecord.fromJson)
        .toList();
  }

  @override
  Future<PhotoRecord> registerPhoto({
    required String s3Key,
    required String cdnUrl,
    bool? isPrimary,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.profileMePhotos,
      data: {
        's3Key': s3Key,
        'cdnUrl': cdnUrl,
        if (isPrimary != null) 'isPrimary': isPrimary,
      },
    );
    return PhotoRecord.fromJson(
      unwrapOrThrow(response.statusCode, response.data) ?? {},
    );
  }
}
