/// Nenjam Matrimony — Photo Repository Contract
///
/// Pure abstract Dart interface. Concrete implementations live in `data/`.
/// Mirrors backend/apps/api/src/modules/profiles/entities/photo.entity.ts —
/// `PhotoController` only registers metadata for a photo already uploaded
/// elsewhere (no presigned-URL/upload-transport endpoint exists yet), so
/// this contract has no method for sending raw file bytes.
library;

/// Mirrors `PhotoEntity` on the backend.
class PhotoRecord {
  const PhotoRecord({
    required this.id,
    required this.s3Key,
    required this.cdnUrl,
    required this.isPrimary,
    required this.order,
    required this.isApproved,
  });

  final String id;
  final String s3Key;
  final String cdnUrl;
  final bool isPrimary;
  final int order;
  final bool isApproved;

  factory PhotoRecord.fromJson(Map<String, dynamic> json) => PhotoRecord(
        id: json['id'] as String,
        s3Key: json['s3Key'] as String,
        cdnUrl: json['cdnUrl'] as String,
        isPrimary: json['isPrimary'] as bool? ?? false,
        order: (json['order'] as num?)?.toInt() ?? 0,
        isApproved: json['isApproved'] as bool? ?? false,
      );
}

abstract interface class PhotoRepository {
  /// `GET /profiles/me/photos`.
  Future<List<PhotoRecord>> getPhotos();

  /// `POST /profiles/me/photos` — registers a photo the client has already
  /// uploaded to S3 by some other means. Mirrors `PhotoUploadDto` on the
  /// backend; there is deliberately no way to pass raw file bytes here.
  Future<PhotoRecord> registerPhoto({
    required String s3Key,
    required String cdnUrl,
    bool? isPrimary,
  });
}
