import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/models/verification_document.dart';
import '../../domain/repositories/verification_repository.dart';

/// Real backend implementation.
///
/// TODO(backend): `backend/apps/api/src/modules/verification` is scaffolded
/// (controller/service/DTO/entity files exist) but every class body is
/// still empty — no routes are registered yet. This repository is written
/// against the contract those files imply (`SubmitDocumentDto` for the
/// multipart submit, a status list keyed by document type) so the UI is
/// ready to connect the moment those routes ship, with no widget changes
/// required. Until then, calls here return real `ApiException`s (404s),
/// which the UI surfaces as a normal "upload failed" / retry state — never
/// a faked success.
class VerificationRepositoryImpl implements VerificationRepository {
  VerificationRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<Map<VerificationDocumentType, VerificationDocumentRecord>>
      getStatuses() async {
    final response =
        await _apiClient.get<List<dynamic>>(ApiEndpoints.verificationStatus);
    final data = unwrapOrThrow(response.statusCode, response.data) ?? const [];
    final records = data
        .cast<Map<String, dynamic>>()
        .map(VerificationDocumentRecord.fromJson);
    return {for (final r in records) r.type: r};
  }

  @override
  Future<VerificationDocumentRecord> submitDocument({
    required VerificationDocumentType type,
    required XFile file,
    void Function(int sent, int total)? onProgress,
  }) async {
    final form = FormData.fromMap({
      'type': type.wireValue,
      'file': await _multipart(file),
    });
    final response = await _apiClient.upload<Map<String, dynamic>>(
      ApiEndpoints.verificationDocuments,
      data: form,
      onSendProgress: onProgress,
    );
    final data = unwrapOrThrow(response.statusCode, response.data);
    return VerificationDocumentRecord.fromJson(data ?? {'type': type.wireValue});
  }

  /// Bytes, not a path — see `PhotoRepository._multipart` for why.
  Future<MultipartFile> _multipart(XFile file) async {
    final filename = file.name.isNotEmpty ? file.name : 'document.jpg';
    final dot = filename.lastIndexOf('.');
    final ext = dot >= 0 ? filename.substring(dot).toLowerCase() : '';
    final subtype = switch (ext) {
      '.png' => 'png',
      '.webp' => 'webp',
      '.pdf' => 'pdf',
      _ => 'jpeg',
    };
    final type = subtype == 'pdf' ? 'application' : 'image';
    return MultipartFile.fromBytes(
      await file.readAsBytes(),
      filename: filename,
      contentType: DioMediaType(type, subtype),
    );
  }
}
