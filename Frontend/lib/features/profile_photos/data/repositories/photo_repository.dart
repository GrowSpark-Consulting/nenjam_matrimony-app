import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../domain/models/user_photo.dart';

/// Thrown when the backend rejects a photo request (too many photos, bad file
/// type, not found, etc.) — carries the backend's own message so the UI can
/// show something actionable. Mirrors RegistrationApiException.
class PhotoApiException implements Exception {
  PhotoApiException(this.statusCode, this.message);
  final int? statusCode;
  final String message;

  @override
  String toString() => 'PhotoApiException($statusCode): $message';
}

/// Talks to backend/apps/api/src/modules/profiles' PhotoController. Every call
/// goes through the shared authenticated [ApiClient], so the Firebase ID token
/// is attached automatically (see AuthInterceptor) and a 401 is transparently
/// recovered/refreshed. ApiClient uses `validateStatus: status < 500`, so 4xx
/// arrive as normal responses — [_unwrapList]/[_unwrapOne] turn those into a
/// thrown [PhotoApiException].
class PhotoRepository {
  PhotoRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<UserPhoto>> fetchPhotos() async {
    final response =
        await _apiClient.get<List<dynamic>>(ApiEndpoints.profilePhotos);
    return _unwrapList(response);
  }

  /// Uploads [file] as multipart/form-data (field name `file`, matching the
  /// backend's FileInterceptor('file')). Returns the newly created photo.
  Future<UserPhoto> upload(File file, {bool? isPrimary}) async {
    final form = FormData.fromMap({
      'file': await _multipart(file),
      if (isPrimary != null) 'isPrimary': isPrimary.toString(),
    });
    final response = await _apiClient.upload<Map<String, dynamic>>(
      ApiEndpoints.profilePhotos,
      data: form,
    );
    return _unwrapOne(response);
  }

  /// Replaces the binary of an existing photo (PUT). Returns the updated photo.
  Future<UserPhoto> replace(String id, File file) async {
    final form = FormData.fromMap({'file': await _multipart(file)});
    // ApiClient.upload posts; replace needs PUT, so go through put() with the
    // FormData body directly (Dio serializes FormData for any method).
    final response = await _apiClient.put<Map<String, dynamic>>(
      ApiEndpoints.profilePhoto(id),
      data: form,
    );
    return _unwrapOne(response);
  }

  /// Deletes a photo. Backend returns the remaining list.
  Future<List<UserPhoto>> delete(String id) async {
    final response = await _apiClient.delete<List<dynamic>>(
      ApiEndpoints.profilePhoto(id),
    );
    return _unwrapList(response);
  }

  /// Reorders photos to match [orderedIds] exactly. Returns the new list.
  Future<List<UserPhoto>> reorder(List<String> orderedIds) async {
    final response = await _apiClient.patch<List<dynamic>>(
      ApiEndpoints.profilePhotosReorder,
      data: {'photoIds': orderedIds},
    );
    return _unwrapList(response);
  }

  /// Sets the primary/display photo. Returns the new list.
  Future<List<UserPhoto>> setPrimary(String id) async {
    final response = await _apiClient.patch<List<dynamic>>(
      ApiEndpoints.profilePhotoPrimary(id),
    );
    return _unwrapList(response);
  }

  Future<MultipartFile> _multipart(File file) async {
    final filename = file.path.split(RegExp(r'[/\\]')).last;
    final dot = filename.lastIndexOf('.');
    final ext = dot >= 0 ? filename.substring(dot).toLowerCase() : '';
    final subtype = switch (ext) {
      '.png' => 'png',
      '.webp' => 'webp',
      _ => 'jpeg',
    };
    return MultipartFile.fromFile(
      file.path,
      filename: filename,
      contentType: DioMediaType('image', subtype),
    );
  }

  List<UserPhoto> _unwrapList(Response<List<dynamic>> response) {
    _throwIfError(response.statusCode, response.data);
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(UserPhoto.fromJson)
        .toList();
  }

  UserPhoto _unwrapOne(Response<Map<String, dynamic>> response) {
    _throwIfError(response.statusCode, response.data);
    return UserPhoto.fromJson(response.data ?? const {});
  }

  void _throwIfError(int? statusCode, Object? data) {
    if (statusCode != null && statusCode >= 400) {
      final message = data is Map ? data['message'] : null;
      throw PhotoApiException(
        statusCode,
        message is String
            ? message
            : message is List && message.isNotEmpty
                ? message.join(', ')
                : 'Request failed ($statusCode).',
      );
    }
  }
}
