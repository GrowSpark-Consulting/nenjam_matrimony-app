import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/inbox_providers.dart';

/// Renders a chat image that's either a hosted `http(s)` URL (a short-lived
/// presigned S3 link — see `MessagesService.presignMedia`) or a local file
/// path (an attachment still uploading, which never expires since no
/// presigned URL is involved).
///
/// Detects an expired presigned URL — S3 responds 403, surfaced by
/// [Image.network] as a [NetworkImageLoadException] with that status code —
/// and requests a fresh one exactly once per URL value via
/// [MessagesNotifier.refreshMediaUrl], which updates the message's
/// `attachmentUrl` in the shared provider state. Every widget currently
/// showing this message (a bubble, and the fullscreen viewer if it's open
/// on the same message) then picks up the fix through its own normal
/// Riverpod rebuild — this widget never retries on its own, it just renders
/// whatever `url` its parent hands it next. Used by both
/// `message_bubble.dart`'s `_MessageImage` and `ChatImageViewerPage` so the
/// detect/refresh logic lives in exactly one place.
class ChatMediaImage extends ConsumerStatefulWidget {
  final String conversationId;
  final String messageId;
  final String url;
  final BoxFit fit;

  /// Shown the moment an expired URL is detected and a fresh one is being
  /// requested — a different moment from [loadingBuilder]'s normal
  /// "still downloading" state, so callers can style them differently (or
  /// identically) as they choose.
  final WidgetBuilder buildRefreshing;

  /// The real broken-image fallback — shown for any non-expiry failure, or
  /// once a refresh attempt itself has failed (offline, or the backend
  /// couldn't presign) rather than retrying forever.
  final WidgetBuilder buildError;

  /// Optional pass-through to [Image.network]'s own `loadingBuilder` (byte
  /// progress while genuinely still downloading, for the first time). Null
  /// keeps whatever [Image.network]'s default is.
  final ImageLoadingBuilder? loadingBuilder;

  const ChatMediaImage({
    super.key,
    required this.conversationId,
    required this.messageId,
    required this.url,
    required this.fit,
    required this.buildRefreshing,
    required this.buildError,
    this.loadingBuilder,
  });

  @override
  ConsumerState<ChatMediaImage> createState() => _ChatMediaImageState();
}

class _ChatMediaImageState extends ConsumerState<ChatMediaImage> {
  // A pathological-misconfiguration guard (e.g. clock skew making every
  // freshly-issued URL immediately invalid too) — bounds the total number of
  // refresh attempts across this widget's whole lifetime, not per URL value,
  // so a persistent underlying problem can't retry forever.
  static const _maxAttempts = 3;
  int _attempts = 0;

  // The specific URL value a refresh attempt already failed for — once set,
  // further errorBuilder firings for that SAME url go straight to
  // buildError instead of requesting another refresh.
  String? _failedUrl;
  bool _refreshing = false;

  @override
  void didUpdateWidget(covariant ChatMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      // A new URL (the fix just landed, or a different message entirely
      // reused this element) gets its own fresh attempt.
      _failedUrl = null;
      _refreshing = false;
    }
  }

  void _handleExpired(String url) {
    if (_refreshing || _failedUrl == url || _attempts >= _maxAttempts) return;
    _refreshing = true;
    _attempts++;
    // Deferred: this fires from Image's own error-reporting rebuild, and
    // mutating a provider (or calling setState) synchronously from there
    // would trip Flutter's "setState during build" guard.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final ok = await ref
          .read(messagesProvider(widget.conversationId).notifier)
          .refreshMediaUrl(widget.messageId);
      if (!mounted) return;
      _refreshing = false;
      if (!ok) {
        // Refresh failed — stop retrying this URL and fall back to the
        // real error state instead of showing a spinner forever. On
        // success, `messagesProvider`'s state now holds a new
        // `attachmentUrl`; the parent (which watches that provider)
        // rebuilds and hands this widget a fresh `url` on its own, so no
        // local setState is needed for that path.
        setState(() => _failedUrl = url);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    if (!url.startsWith('http')) {
      return Image.file(
        File(url),
        fit: widget.fit,
        errorBuilder: (_, __, ___) => widget.buildError(context),
      );
    }

    return Image.network(
      url,
      fit: widget.fit,
      loadingBuilder: widget.loadingBuilder,
      errorBuilder: (context, error, stackTrace) {
        final expired = error is NetworkImageLoadException && error.statusCode == 403;
        final canRetry = expired && _failedUrl != url && _attempts < _maxAttempts;
        if (canRetry) {
          _handleExpired(url);
          return widget.buildRefreshing(context);
        }
        return widget.buildError(context);
      },
    );
  }
}
