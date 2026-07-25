import '../../domain/entities/notification_entity.dart';

/// Wire model for [NotificationEntity]. `fromJson`/`toJson` are the seam a
/// real `GET /notifications` response plugs into — nothing else in the
/// feature needs to change when the mock datasource is swapped for Dio (see
/// `data/repositories/notification_api_repository_impl.dart`).
class NotificationModel extends NotificationEntity {
  const NotificationModel({
    required super.id,
    required super.type,
    required super.title,
    required super.message,
    required super.createdAt,
    super.isRead,
    super.actor,
    super.referenceId,
    super.metadata,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final actorJson = json['actor'] as Map<String, dynamic>?;
    return NotificationModel(
      id: json['id'] as String,
      type: NotificationType.fromBackendValue(json['type'] as String?),
      title: json['title'] as String? ?? '',
      // Accepts both `message` (the proposed API contract) and `body`
      // (Prisma's `Notification.body` column name) so this keeps working
      // whichever the eventual DTO ends up serializing as.
      message: (json['message'] ?? json['body']) as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      isRead: json['isRead'] as bool? ?? false,
      actor: actorJson == null
          ? null
          : NotificationActor(
              id: actorJson['id'] as String? ?? '',
              name: actorJson['name'] as String? ?? '',
              photoUrl: actorJson['photoUrl'] as String?,
            ),
      referenceId: json['referenceId'] as String?,
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'message': message,
        'createdAt': createdAt.toIso8601String(),
        'isRead': isRead,
        if (actor != null)
          'actor': {
            'id': actor!.id,
            'name': actor!.name,
            'photoUrl': actor!.photoUrl,
          },
        'referenceId': referenceId,
        'metadata': metadata,
      };
}
