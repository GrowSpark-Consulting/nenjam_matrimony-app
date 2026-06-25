import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/profile_draft.dart';

/// Step 11 — Photo Upload (Local only, no backend)
class StepPhotos extends StatefulWidget {
  final PhotoGallery gallery;
  final void Function(PhotoGallery) onChanged;

  const StepPhotos({super.key, required this.gallery, required this.onChanged});

  @override
  State<StepPhotos> createState() => _StepPhotosState();
}

class _StepPhotosState extends State<StepPhotos> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Photos', style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Add photos to get 10x more responses', style: AppTypography.bodyMedium.copyWith(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
          const SizedBox(height: 24),

          // Primary photo placeholder
          Center(
            child: GestureDetector(
              onTap: _showPhotoOptions,
              child: Container(
                width: 160,
                height: 200,
                decoration: AppDecorations.card(isDark: isDark).copyWith(
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 2, strokeAlign: BorderSide.strokeAlignInside),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_rounded, size: 48, color: AppColors.primary.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    Text('Primary Photo', style: AppTypography.labelMedium.copyWith(color: AppColors.primary)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          Text('Gallery Photos', style: AppTypography.labelLarge),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: 6,
            itemBuilder: (context, index) => GestureDetector(
              onTap: _showPhotoOptions,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                ),
                child: Icon(Icons.add_rounded, color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.info, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Photos will be uploaded when backend integration is complete. Currently stored locally.',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.info),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showPhotoOptions() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.dividerLight, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text('Add Photo', style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(width: 48, height: 48, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary)),
                title: Text('Camera', style: AppTypography.bodyLarge),
                subtitle: Text('Take a new photo', style: AppTypography.bodySmall),
                onTap: () => Navigator.pop(ctx),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(width: 48, height: 48, decoration: BoxDecoration(color: AppColors.accentGold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.photo_library_rounded, color: AppColors.accentGold)),
                title: Text('Gallery', style: AppTypography.bodyLarge),
                subtitle: Text('Choose from gallery', style: AppTypography.bodySmall),
                onTap: () => Navigator.pop(ctx),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
