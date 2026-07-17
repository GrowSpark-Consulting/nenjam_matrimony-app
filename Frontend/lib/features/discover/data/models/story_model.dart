import '../../domain/entities/discovery_profile_entity.dart';
import '../../domain/entities/story_entity.dart';
import 'discovery_profile_model.dart';

class StoryModel extends StoryEntity {
  const StoryModel({
    required super.id,
    required super.name,
    required super.imageUrl,
    super.hasNewStory,
    super.gender,
    super.profile,
  });

  factory StoryModel.fromJson(Map<String, dynamic> json) => StoryModel(
    id: json['id'] as String,
    name: json['name'] as String,
    imageUrl: json['imageUrl'] as String,
    hasNewStory: json['hasNewStory'] as bool? ?? false,
    gender: json['gender'] as String? ?? '',
    profile: json['profile'] != null
        ? DiscoveryProfileModel.fromJson(
            json['profile'] as Map<String, dynamic>,
          )
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'imageUrl': imageUrl,
    'hasNewStory': hasNewStory,
    'gender': gender,
    'profile': switch (profile) {
      final DiscoveryProfileModel p => p.toJson(),
      final DiscoveryProfileEntity _ => null,
      null => null,
    },
  };
}
