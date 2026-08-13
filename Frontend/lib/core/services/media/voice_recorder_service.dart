import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../l10n/app_localizations.dart';
import '../../permissions/app_permission_service.dart';
import '../../permissions/nm_permission.dart';
import '../../widgets/permissions/permission_dialogs.dart';

/// Thin wrapper around [AudioRecorder] that gates recording behind
/// [AppPermissionService] — same explanation-dialog / Open-Settings pattern
/// as [AttachmentPicker]'s camera flow, so microphone access is asked for
/// exactly once, only when the user actually taps the mic, never at startup.
///
/// This only produces a local recording file — there is no chat
/// attachment-upload endpoint yet (see
/// docs/development/chat-backend-handoff.md), so nothing here pretends a
/// recording has been sent anywhere.
class VoiceRecorderService {
  VoiceRecorderService({
    AudioRecorder? recorder,
    AppPermissionService? permissions,
  }) : _recorder = recorder ?? AudioRecorder(),
       _permissions = permissions ?? const AppPermissionServiceImpl();

  final AudioRecorder _recorder;
  final AppPermissionService _permissions;

  /// Starts recording to a fresh temp file. Returns the destination path on
  /// success, or `null` if the user cancelled or denied the permission —
  /// any necessary explanation/Open-Settings dialog has already been shown.
  Future<String?> start(BuildContext context) async {
    final granted = await _ensureMicrophonePermission(context);
    if (!granted || !context.mounted) return null;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/nm_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    // AAC-LC in an MPEG-4 container (.m4a) — the `record` package's default
    // encoder, supported on every platform this app ships to.
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    return path;
  }

  /// Stops recording and returns the finished file's path.
  Future<String?> stop() => _recorder.stop();

  /// Stops and deletes the in-progress recording — used when the user
  /// cancels instead of sending.
  Future<void> cancel() => _recorder.cancel();

  Future<void> dispose() => _recorder.dispose();

  Future<bool> _ensureMicrophonePermission(BuildContext context) async {
    final status = await _permissions.statusOf(NmPermission.microphone);
    if (status == NmPermissionStatus.granted) return true;

    if (status == NmPermissionStatus.permanentlyDenied ||
        status == NmPermissionStatus.restricted) {
      if (!context.mounted) return false;
      await showOpenSettingsDialog(
        context,
        title: AppLocalizations.of(context).permissionMicDisabledTitle,
        message: AppLocalizations.of(context).permissionMicDisabledMessage,
        onOpenSettings: _permissions.openSettings,
      );
      return false;
    }

    if (!context.mounted) return false;
    final proceed = await showPermissionPrimerDialog(
      context,
      icon: Icons.mic_rounded,
      title: AppLocalizations.of(context).permissionMicTitle,
      message: AppLocalizations.of(context).permissionMicMessage,
      proceedLabel: AppLocalizations.of(context).commonContinue,
      cancelLabel: AppLocalizations.of(context).commonCancel,
    );
    if (!proceed) return false;

    final result = await _permissions.request(NmPermission.microphone);
    if (result == NmPermissionStatus.granted) return true;

    if (!context.mounted) return false;
    if (result == NmPermissionStatus.permanentlyDenied) {
      await showOpenSettingsDialog(
        context,
        title: AppLocalizations.of(context).permissionMicDisabledTitle,
        message: AppLocalizations.of(context).permissionMicDisabledMessage,
        onOpenSettings: _permissions.openSettings,
      );
    }
    return false;
  }
}
