import 'dart:io';

import 'package:flutter/material.dart';

import 'photo_crop_screen.dart';

/// Shared entry point for the crop & adjust step — pushes [PhotoCropScreen]
/// full-screen and hands back the finished, compressed local [File] ready
/// for upload, or `null` if the user cancelled anywhere along the way.
///
/// Mirrors [AttachmentPicker]'s role for picking: callers (e.g.
/// `PhotoManagerSection`) go through this instead of touching the crop
/// screen or compressor directly.
class CropService {
  const CropService();

  /// Pass [CropShape.circle] only when [sourceFile] is about to become the
  /// primary/display photo — every other 1:1 photo slot uses
  /// [CropShape.square] (no circular guide).
  Future<File?> pickAndCrop({
    required BuildContext context,
    required File sourceFile,
    required CropShape shape,
  }) {
    return Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => PhotoCropScreen(imageFile: sourceFile, shape: shape),
        fullscreenDialog: true,
      ),
    );
  }
}
