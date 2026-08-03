import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/inbox_providers.dart';
import 'chat_media_image.dart';

/// Fullscreen chat image viewer — opened by tapping an image message bubble.
/// Mirrors `ProfilePhotoViewerPage`'s stock-widget approach ([InteractiveViewer]
/// for pinch-zoom + pan; the project has no `photo_view` dependency to reach
/// for instead), simplified to a single image since a chat bubble views
/// exactly one photo at a time — no swipe-between-photos gallery here, unlike
/// the profile viewer's [PageView].
///
/// [heroTag] must be the exact same tag the originating bubble's own [Hero]
/// used, so the two animate as one flight rather than two independent pages.
///
/// Takes [conversationId]/[messageId] rather than a raw URL and watches
/// `messagesProvider` for the message's current `attachmentUrl` — so if its
/// presigned URL expires while this page is open and gets refreshed (see
/// [ChatMediaImage]), the fresh URL flows in through the normal provider
/// rebuild with no special-casing here, and the zoom/pan transform (held in
/// [_transformationController], untouched by that rebuild) is preserved.
class ChatImageViewerPage extends ConsumerStatefulWidget {
  final String conversationId;
  final String messageId;
  final String heroTag;

  const ChatImageViewerPage({
    super.key,
    required this.conversationId,
    required this.messageId,
    required this.heroTag,
  });

  @override
  ConsumerState<ChatImageViewerPage> createState() => _ChatImageViewerPageState();
}

class _ChatImageViewerPageState extends ConsumerState<ChatImageViewerPage>
    with SingleTickerProviderStateMixin {
  final _transformationController = TransformationController();
  late final AnimationController _zoomController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..addListener(() {
      if (_zoomAnimation != null) {
        _transformationController.value = _zoomAnimation!.value;
      }
    });
  Animation<Matrix4>? _zoomAnimation;
  Offset? _doubleTapLocalPosition;

  @override
  void dispose() {
    _zoomController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapLocalPosition = details.localPosition;
  }

  /// Toggles between fit-to-screen and a 3x zoom centered on the tap point —
  /// animated the same way pinch-zoom feels, rather than snapping instantly.
  void _handleDoubleTap() {
    final position = _doubleTapLocalPosition ?? Offset.zero;
    final isZoomedIn = _transformationController.value != Matrix4.identity();
    final endMatrix = isZoomedIn
        ? Matrix4.identity()
        : (Matrix4.identity()
          ..translateByDouble(-position.dx * 2, -position.dy * 2, 0, 1)
          ..scaleByDouble(3.0, 3.0, 3.0, 1.0));

    _zoomAnimation = Matrix4Tween(
      begin: _transformationController.value,
      end: endMatrix,
    ).animate(CurveTween(curve: Curves.easeOut).animate(_zoomController));
    _zoomController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.conversationId)).valueOrNull;
    String? url;
    if (messages != null) {
      for (final m in messages) {
        if (m.id == widget.messageId) {
          url = m.attachmentUrl;
          break;
        }
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: url == null
          // Shouldn't normally happen — this page is only ever pushed from a
          // currently-rendered image bubble, so the message and its
          // attachment are already loaded. Guards against the narrow window
          // where the message somehow no longer has one (e.g. deleted).
          ? const _ViewerImageError()
          : GestureDetector(
              onDoubleTapDown: _handleDoubleTapDown,
              onDoubleTap: _handleDoubleTap,
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Hero(
                    tag: widget.heroTag,
                    child: ChatMediaImage(
                      conversationId: widget.conversationId,
                      messageId: widget.messageId,
                      url: url,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        final total = progress.expectedTotalBytes;
                        return Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            value: total != null ? progress.cumulativeBytesLoaded / total : null,
                          ),
                        );
                      },
                      buildRefreshing: (_) =>
                          const Center(child: CircularProgressIndicator(color: Colors.white)),
                      buildError: (_) => const _ViewerImageError(),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ViewerImageError extends StatelessWidget {
  const _ViewerImageError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 64),
    );
  }
}
