import 'package:flutter/foundation.dart';

/// TEMPORARY — diagnosing the registration wizard "Continue" button delay.
/// Remove this file and all StoryPerf.* call sites once done.
///
/// Uses debugPrint (not dart:developer's log()) deliberately — log() only
/// surfaces when a Dart VM Service/Observatory client is attached; debugPrint
/// always reaches stdout/logcat, so this works whether or not `flutter run`
/// is currently attached to the device.
class StoryPerf {
  static Stopwatch? _sw;

  static void start(String label) {
    if (!kDebugMode) return;
    _sw = Stopwatch()..start();
    debugPrint('[STORY-PERF] $label: 0ms');
  }

  static void mark(String label) {
    if (!kDebugMode) return;
    final ms = _sw?.elapsedMilliseconds ?? -1;
    debugPrint('[STORY-PERF] $label: ${ms}ms');
  }
}
