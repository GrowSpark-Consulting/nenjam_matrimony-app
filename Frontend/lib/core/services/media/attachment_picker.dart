import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../l10n/app_localizations.dart';
import '../../permissions/app_permission_service.dart';
import '../../permissions/nm_permission.dart';
import '../../widgets/permissions/permission_dialogs.dart';

/// Shared camera/gallery pick flow for every attachment call site (profile
/// photos, verification documents, chat attachments) — the single place
/// that decides whether a permission is needed before opening the picker,
/// so no widget has to duplicate that logic.
///
/// Camera goes through [AppPermissionService] with a Nenjam-styled
/// explanation dialog before the OS prompt, and an "Open Settings" dialog
/// if permanently denied. Gallery is NOT gated by any runtime permission
/// request — the system photo picker on both platforms needs none — this
/// only reacts to the rare `PlatformException` iOS raises when photo
/// library access is restricted/denied outside the app's control.
class AttachmentPicker {
  AttachmentPicker({ImagePicker? picker, AppPermissionService? permissions})
    : _picker = picker ?? ImagePicker(),
      _permissions = permissions ?? const AppPermissionServiceImpl();

  final ImagePicker _picker;
  final AppPermissionService _permissions;

  /// Returns the picked file, or `null` if the user cancelled, denied a
  /// required permission, or the picker failed — in every `null` case any
  /// necessary explanation has already been shown to the user.
  Future<File?> pick(
    BuildContext context,
    ImageSource source, {
    double? maxWidth,
    int? imageQuality,
  }) async {
    if (source == ImageSource.camera) {
      final granted = await _ensureCameraPermission(context);
      if (!granted) return null;
    }
    if (!context.mounted) return null;

    try {
      final xfile = await _picker.pickImage(
        source: source,
        maxWidth: maxWidth,
        imageQuality: imageQuality,
      );
      return xfile == null ? null : File(xfile.path);
    } on PlatformException catch (e) {
      if (source == ImageSource.gallery && _isPhotoAccessDenied(e)) {
        if (context.mounted) {
          await showOpenSettingsDialog(
            context,
            title: AppLocalizations.of(context).permissionPhotoDisabledTitle,
            message: AppLocalizations.of(
              context,
            ).permissionPhotoDisabledMessage,
            onOpenSettings: _permissions.openSettings,
          );
        }
        return null;
      }
      if (context.mounted) {
        _snack(
          context,
          AppLocalizations.of(context).permissionImagePickerError,
        );
      }
      return null;
    }
  }

  bool _isPhotoAccessDenied(PlatformException e) =>
      e.code == 'photo_access_denied' || e.code == 'PERMISSION_DENIED';

  Future<bool> _ensureCameraPermission(BuildContext context) async {
    final status = await _permissions.statusOf(NmPermission.camera);
    if (status == NmPermissionStatus.granted) return true;

    if (status == NmPermissionStatus.permanentlyDenied ||
        status == NmPermissionStatus.restricted) {
      if (!context.mounted) return false;
      await showOpenSettingsDialog(
        context,
        title: AppLocalizations.of(context).permissionCameraDisabledTitle,
        message: AppLocalizations.of(context).permissionCameraDisabledMessage,
        onOpenSettings: _permissions.openSettings,
      );
      return false;
    }

    if (!context.mounted) return false;
    final proceed = await showPermissionPrimerDialog(
      context,
      icon: Icons.camera_alt_rounded,
      title: AppLocalizations.of(context).permissionCameraTitle,
      message: AppLocalizations.of(context).permissionCameraMessage,
      proceedLabel: AppLocalizations.of(context).commonContinue,
      cancelLabel: AppLocalizations.of(context).commonCancel,
    );
    if (!proceed) return false;

    final result = await _permissions.request(NmPermission.camera);
    if (result == NmPermissionStatus.granted) return true;

    if (!context.mounted) return false;
    if (result == NmPermissionStatus.permanentlyDenied) {
      await showOpenSettingsDialog(
        context,
        title: AppLocalizations.of(context).permissionCameraDisabledTitle,
        message: AppLocalizations.of(context).permissionCameraDisabledMessage,
        onOpenSettings: _permissions.openSettings,
      );
    } else {
      _snack(context, AppLocalizations.of(context).permissionCameraNeeded);
    }
    return false;
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
