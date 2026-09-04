import 'package:flutter/foundation.dart';

/// TEMPORARY — diagnosing "profile photo is never stored".
/// Remove this file and all PhotoTrace.* call sites once the flow is
/// confirmed working end to end.
///
/// Uses debugPrint (not dart:developer's log()) for the same reason
/// [StoryPerf] does: log() only surfaces with a Dart VM Service client
/// attached, while debugPrint always reaches logcat — which is where these
/// traces are being read from.
///
/// Every line is prefixed `[PHOTO]` so the whole flow can be isolated with
/// `adb logcat | grep PHOTO`. Compiled out of release builds.
///
/// Deliberately never logs the bearer token itself — only whether one was
/// obtained, matching LoggingInterceptor's rule that a credential must never
/// reach a log line.
abstract final class PhotoTrace {
  static final Stopwatch _sw = Stopwatch();

  /// Opens a new traced operation (a pick, an upload, a delete) and resets
  /// the elapsed clock, so every following [step] is measured from here.
  ///
  /// This is the difference from [StoryPerf], whose single stopwatch is
  /// started once per "story" — reading one of its marks as the duration of
  /// the call it names overstates it by however long the story had already
  /// been running.
  static void begin(String label) {
    if (!kDebugMode) return;
    _sw
      ..reset()
      ..start();
    debugPrint('[PHOTO] ┌── $label');
  }

  /// A step within the current operation, stamped with the elapsed time
  /// since [begin] — a real per-step duration.
  static void step(String label, [Map<String, Object?>? fields]) {
    if (!kDebugMode) return;
    final detail = fields == null || fields.isEmpty
        ? ''
        : ' ${fields.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    debugPrint('[PHOTO] │   +${_sw.elapsedMilliseconds}ms $label$detail');
  }

  /// A failure within the current operation. Separate from [step] so an
  /// error can never be mistaken for a normal line when scanning a log.
  static void fail(String label, Object error, [StackTrace? stackTrace]) {
    if (!kDebugMode) return;
    debugPrint(
      '[PHOTO] │   +${_sw.elapsedMilliseconds}ms ✕ $label '
      '(${error.runtimeType}) $error',
    );
    if (stackTrace != null) {
      debugPrint('[PHOTO] │   $stackTrace');
    }
  }

  static void end(String label) {
    if (!kDebugMode) return;
    debugPrint('[PHOTO] └── $label (+${_sw.elapsedMilliseconds}ms)');
  }
}
