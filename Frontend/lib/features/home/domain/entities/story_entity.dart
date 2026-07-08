/// A "New Today" story avatar shown at the top of the Home Feed.
class StoryEntity {
  final String id;
  final String name;
  final String imageUrl;
  final bool hasNewStory;

  const StoryEntity({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.hasNewStory = false,
  });
}
