import 'package:flutter/material.dart';

import '../network/backend_connectivity_checker.dart';

/// Dev-only banner shown when [BackendConnectivityChecker] reports the
/// backend is unreachable or unhealthy. Never constructed in production —
/// see the call site in main.dart.
class BackendDiagnosticBanner extends StatelessWidget {
  const BackendDiagnosticBanner({
    super.key,
    required this.result,
    required this.onRetry,
    required this.onDismiss,
  });

  final BackendConnectivityResult result;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final (String title, String message) = switch (result) {
      BackendUnreachable() => (
          'Backend unreachable',
          'Cannot reach the backend over http://127.0.0.1:3000. This means '
              'one of the following — they look identical from the app:\n'
              '• Backend isn\'t running (pnpm start:dev in backend/)\n'
              '• adb reverse tcp:3000 tcp:3000 hasn\'t been run since the '
              'phone was last plugged in\n'
              '• Phone is disconnected from USB\n\n'
              'Run scripts/dev/start_dev.ps1 (or the "Start Development" '
              'VS Code task) to fix all three at once.',
        ),
      BackendUnhealthy(:final statusCode) => (
          'Backend unhealthy',
          'The backend responded but /health returned '
              '${statusCode ?? 'no status'}. The process is up (this is '
              'not a USB/adb issue) — check the backend logs.',
        ),
      BackendHealthy() => ('', ''),
    };

    if (title.isEmpty) return const SizedBox.shrink();

    return Material(
      color: Colors.red.shade800,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: const TextStyle(color: Colors.white, fontSize: 11.5),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
