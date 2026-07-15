import '../profile_completion_module.dart';

/// Done when at least one photo (primary or gallery) has been added.
class PhotosModule extends ProfileCompletionModule {
  const PhotosModule();

  @override
  String get id => 'photos';

  @override
  double get weight => 20;

  @override
  ModuleStatus evaluate(ProfileCompletionContext context) {
    final gallery = context.draft.photoGallery;
    final hasPhoto =
        gallery.primaryPhotoPath != null || gallery.galleryPaths.isNotEmpty;
    return ModuleStatus(
      isComplete: hasPhoto,
      progress: hasPhoto ? 1.0 : 0.0,
      wizardStep: 11,
    );
  }
}
