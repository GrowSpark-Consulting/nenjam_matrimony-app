import 'dart:async';

/// Debounces this client's outgoing typing signal so a `typing_start` is sent
/// at most once per typing burst (not per keystroke) and a `typing_stop` follows
/// automatically once the user goes idle, clears the field, or sends.
///
/// - First keystroke arms a [startDelay] timer; when it fires, `onTyping(true)`
///   is emitted once. Continued typing does NOT re-arm it (so start fires ~half
///   a second into a burst, then stays quiet).
/// - Every keystroke re-arms an [idleTimeout]; when it elapses with no input,
///   `onTyping(false)` is emitted.
/// - [stop] emits `onTyping(false)` immediately (call it on send / field empty /
///   dispose) and is idempotent.
///
/// Purely a timer coordinator — it never touches the socket directly; the caller
/// passes an `onTyping` sink (the repository's `setTyping`).
class TypingController {
  TypingController({
    required this.onTyping,
    this.startDelay = const Duration(milliseconds: 500),
    this.idleTimeout = const Duration(seconds: 1),
  });

  final void Function(bool isTyping) onTyping;
  final Duration startDelay;
  final Duration idleTimeout;

  Timer? _startTimer;
  Timer? _idleTimer;
  bool _startSent = false;

  /// Feed the field's current content on every change.
  void onChanged(String text) {
    if (text.trim().isEmpty) {
      stop();
      return;
    }
    // Re-arm the idle→stop timer on every keystroke.
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, stop);
    // Emit `typing_start` once, a short debounce into the burst.
    if (_startSent) return;
    _startTimer ??= Timer(startDelay, () {
      _startTimer = null;
      _startSent = true;
      onTyping(true);
    });
  }

  /// Called when the socket reconnects after a drop — discards the
  /// "already told the peer I'm typing" assumption WITHOUT emitting a stop,
  /// since a `true` sent while disconnected never reached them in the first
  /// place (there's nothing to "undo" on their end). If the user is still
  /// actively typing, the next debounce cycle naturally re-sends `true`
  /// (the very next keystroke re-arms [_startTimer] since [_startSent] is
  /// now false); if they've gone idle, nothing fires, which is correct.
  void resetForReconnect() {
    _startTimer?.cancel();
    _startTimer = null;
    _startSent = false;
  }

  /// Emit `typing_stop` now (send / cleared field / leaving the screen).
  void stop() {
    _startTimer?.cancel();
    _startTimer = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_startSent) {
      _startSent = false;
      onTyping(false);
    }
  }

  void dispose() {
    _startTimer?.cancel();
    _idleTimer?.cancel();
    // Best-effort stop so the peer never sees us stuck "typing" after we leave.
    if (_startSent) {
      _startSent = false;
      onTyping(false);
    }
  }
}
