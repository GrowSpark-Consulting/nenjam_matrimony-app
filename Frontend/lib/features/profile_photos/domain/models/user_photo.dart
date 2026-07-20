/// A single profile photo as returned by the backend PhotoController.
///
/// [cdnUrl] is a short-lived **presigned** GET URL (the bucket is private),
/// so it must not be persisted or cached long-term — always re-fetch the list
/// to get fresh URLs. [id] is the stable handle used for replace/delete/
/// primary/reorder operations.
class UserPhoto {
  final String id;
  final String cdnUrl;
  final bool isPrimary;
  final int order;
  final bool isApproved;

  const UserPhoto({
    required this.id,
    required this.cdnUrl,
    required this.isPrimary,
    required this.order,
    required this.isApproved,
  });

  factory UserPhoto.fromJson(Map<String, dynamic> json) => UserPhoto(
        id: json['id'] as String,
        cdnUrl: json['cdnUrl'] as String? ?? '',
        isPrimary: json['isPrimary'] as bool? ?? false,
        order: (json['order'] as num?)?.toInt() ?? 0,
        isApproved: json['isApproved'] as bool? ?? false,
      );
}
