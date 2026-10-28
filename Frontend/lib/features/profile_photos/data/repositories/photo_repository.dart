import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/photo_trace.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../domain/models/user_photo.dart';

/// Thrown when the backend rejects a photo request (too many photos, bad file
/// type, not found, etc.) — carries the backend's own message so the UI can
/// show something actionable. Mirrors RegistrationApiException.
///
/// An [ApiException], so a membership refusal on upload (the photo cap under
/// enforcement) keeps its `code`, `limit` and `upgradeTo`.
class PhotoApiException extends ApiException {
  PhotoApiException(
    super.statusCode,
    super.message, {
    super.code,
    super.feature,
    super.limit,
    super.resetsAt,
    super.upgradeTo,
  });

  PhotoApiException._from(ApiException e)
    : super(
        e.statusCode,
        e.message,
        code: e.code,
        retryAfterSeconds: e.retryAfterSeconds,
        feature: e.feature,
        limit: e.limit,
        resetsAt: e.resetsAt,
        upgradeTo: e.upgradeTo,
      );

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
    PhotoTrace.step('GET ${ApiEndpoints.profilePhotos} →');
    try {
      // Deliberately `dynamic`, not `List<dynamic>`. PhotoController.list
      // returns a raw array, but ApiClient uses `validateStatus: status < 500`
      // — so a 401/403/404 arrives here as a NORMAL response carrying Nest's
      // error object. Asking Dio for a `List` made that object fail an
      // internal cast before any of our code ran, and the caller saw an
      // opaque `DioException [unknown]` with a null status instead of the 401
      // it actually was. Observed as: type '_Map<String, dynamic>' is not a
      // subtype of type 'List<dynamic>?'. Taking the body untyped lets
      // [_unwrapList] classify it properly.
      final response = await _apiClient.get<dynamic>(
        ApiEndpoints.profilePhotos,
      );
      PhotoTrace.step('GET ${ApiEndpoints.profilePhotos} ←', {
        'status': response.statusCode,
        'bodyType': response.data.runtimeType.toString(),
      });
      final photos = _unwrapList(response);
      for (final p in photos) {
        PhotoTrace.step('  photo', {
          'id': p.id,
          'isPrimary': p.isPrimary,
          'order': p.order,
          // Presigned URLs carry a signature — log only the object path.
          'url': p.cdnUrl.split('?').first,
        });
      }
      return photos;
    } on DioException catch (e) {
      PhotoTrace.fail('GET ${ApiEndpoints.profilePhotos}', e);
      PhotoTrace.step('  dio', {
        'type': e.type,
        'status': e.response?.statusCode,
        'body': e.response?.data,
      });
      rethrow;
    }
  }

  /// Uploads [file] as multipart/form-data (field name `file`, matching the
  /// backend's FileInterceptor('file')). Returns the newly created photo.
  Future<UserPhoto> upload(XFile file, {bool? isPrimary}) async {
    final part = await _multipart(file);
    PhotoTrace.step('POST ${ApiEndpoints.profilePhotos} →', {
      'field': 'file',
      'filename': part.filename,
      'contentType': part.contentType,
      'bytes': part.length,
      'isPrimary': isPrimary,
    });
    final form = FormData.fromMap({
      'file': part,
      if (isPrimary != null) 'isPrimary': isPrimary.toString(),
    });
    try {
      final response = await _apiClient.upload<Map<String, dynamic>>(
        ApiEndpoints.profilePhotos,
        data: form,
      );
      PhotoTrace.step('POST ${ApiEndpoints.profilePhotos} ←', {
        'status': response.statusCode,
        'keys': (response.data ?? const {}).keys.toList(),
        'id': response.data?['id'],
        's3Key': response.data?['s3Key'],
      });
      return _unwrapOne(response);
    } on DioException catch (e) {
      PhotoTrace.fail('POST ${ApiEndpoints.profilePhotos}', e);
      PhotoTrace.step('  dio', {
        'type': e.type,
        'status': e.response?.statusCode,
        'body': e.response?.data,
      });
      rethrow;
    }
  }

  /// Replaces the binary of an existing photo (PUT). Returns the updated photo.
  Future<UserPhoto> replace(String id, XFile file) async {
    final part = await _multipart(file);
    PhotoTrace.step('PUT ${ApiEndpoints.profilePhoto(id)} →', {
      'field': 'file',
      'filename': part.filename,
      'contentType': part.contentType,
      'bytes': part.length,
    });
    final form = FormData.fromMap({'file': part});
    // ApiClient.upload posts; replace needs PUT, so go through put() with the
    // FormData body directly (Dio serializes FormData for any method).
    final response = await _apiClient.put<Map<String, dynamic>>(
      ApiEndpoints.profilePhoto(id),
      data: form,
    );
    PhotoTrace.step('PUT ${ApiEndpoints.profilePhoto(id)} ←', {
      'status': response.statusCode,
      'id': response.data?['id'],
    });
    return _unwrapOne(response);
  }

  /// Deletes a photo. Backend returns the remaining list.
  Future<List<UserPhoto>> delete(String id) async {
    PhotoTrace.step('DELETE ${ApiEndpoints.profilePhoto(id)} →');
    final response = await _apiClient.delete<List<dynamic>>(
      ApiEndpoints.profilePhoto(id),
    );
    PhotoTrace.step('DELETE ${ApiEndpoints.profilePhoto(id)} ←', {
      'status': response.statusCode,
      'remaining': (response.data ?? const []).length,
    });
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

  /// Builds the multipart part from **bytes** rather than a filesystem path.
  ///
  /// `MultipartFile.fromFile` needs `dart:io` and throws in a browser;
  /// `fromBytes` works on every platform, and `XFile.readAsBytes()` supplies
  /// them whether they came from a browser file input or a device path. The
  /// `file` field name still matches the backend's `FileInterceptor('file')`.
  Future<MultipartFile> _multipart(XFile file) async {
    final filename = file.name.isNotEmpty ? file.name : 'photo.jpg';
    final dot = filename.lastIndexOf('.');
    final ext = dot >= 0 ? filename.substring(dot).toLowerCase() : '';
    final subtype = switch (ext) {
      '.png' => 'png',
      '.webp' => 'webp',
      _ => 'jpeg',
    };
    return MultipartFile.fromBytes(
      await file.readAsBytes(),
      filename: filename,
      contentType: DioMediaType('image', subtype),
    );
  }

  /// Reads the photo array out of a response body, whatever shape it took.
  ///
  /// The endpoint returns a bare JSON array today. This also accepts a
  /// wrapped object (`{"photos": [...]}` / `data` / `items`) so a later
  /// envelope would not silently parse as "no photos", and routes anything
  /// else through [_throwIfError] — which is what turns a 4xx body into a
  /// [PhotoApiException] carrying the backend's own message, rather than a
  /// type-cast failure surfacing as an unknown DioException.
  List<UserPhoto> _unwrapList(Response<dynamic> response) {
    _throwIfError(response.statusCode, response.data);

    final data = response.data;
    final List<dynamic>? raw;
    if (data == null) {
      raw = const [];
    } else if (data is List) {
      raw = data;
    } else if (data is Map) {
      final wrapped = data['photos'] ?? data['data'] ?? data['items'];
      raw = wrapped is List ? wrapped : null;
    } else {
      raw = null;
    }

    if (raw == null) {
      // A 2xx body that is neither an array nor a recognised wrapper: report
      // it instead of quietly returning an empty gallery, which would read to
      // the member as "your photos are gone".
      PhotoTrace.step('unexpected list body', {
        'type': data.runtimeType.toString(),
      });
      throw PhotoApiException(
        response.statusCode,
        'Unexpected photo response from the server.',
      );
    }

    final photos = raw
        .whereType<Map<String, dynamic>>()
        .map(UserPhoto.fromJson)
        .toList();
    PhotoTrace.step('parsed photo list', {'count': photos.length});
    return photos;
  }

  UserPhoto _unwrapOne(Response<Map<String, dynamic>> response) {
    _throwIfError(response.statusCode, response.data);
    return UserPhoto.fromJson(response.data ?? const {});
  }

  void _throwIfError(int? statusCode, Object? data) {
    if (statusCode != null && statusCode >= 400) {
      PhotoTrace.step('backend rejected', {'status': statusCode, 'body': data});
      // Same message rules as every other repository, plus the membership
      // refusal details.
      try {
        unwrapOrThrow<Object>(statusCode, data);
      } on ApiException catch (e) {
        throw PhotoApiException._from(e);
      }
    }
  }
}
