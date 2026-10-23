import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/layout/mouse_drag_scroll.dart';
import '../../../../l10n/app_localizations.dart';

/// Full-screen photo viewer opened from the photo gallery — swipe between
/// photos, pinch/double-tap to zoom. Built entirely from stock Flutter
/// widgets ([PageView] + [InteractiveViewer]); the project has no
/// `photo_view`/`carousel_slider` dependency to reach for instead.
///
/// Swiping is a touch gesture, so a mouse or keyboard also gets previous /
/// next buttons and the arrow keys — in a browser those are the only way to
/// reach the second photo.
class ProfilePhotoViewerPage extends StatefulWidget {
  final List<String> photoUrls;
  final int initialIndex;

  const ProfilePhotoViewerPage({
    super.key,
    required this.photoUrls,
    this.initialIndex = 0,
  });

  @override
  State<ProfilePhotoViewerPage> createState() => _ProfilePhotoViewerPageState();
}

class _ProfilePhotoViewerPageState extends State<ProfilePhotoViewerPage> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int index) {
    if (index < 0 || index >= widget.photoUrls.length) return;
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasMany = widget.photoUrls.length > 1;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _go(_index - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _go(_index + 1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text('${_index + 1} / ${widget.photoUrls.length}'),
          ),
          body: Stack(
            children: [
              NmMouseDragScroll(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: widget.photoUrls.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) {
                    final url = widget.photoUrls[i];
                    return InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Center(
                        child: url.startsWith('assets/')
                            ? Image.asset(url, fit: BoxFit.contain)
                            : Image.network(
                                url,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white38,
                                  size: 64,
                                ),
                              ),
                      ),
                    );
                  },
                ),
              ),
              if (hasMany && _index > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: _PagerButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: l10n.photoViewerPrevious,
                    onPressed: () => _go(_index - 1),
                  ),
                ),
              if (hasMany && _index < widget.photoUrls.length - 1)
                Align(
                  alignment: Alignment.centerRight,
                  child: _PagerButton(
                    icon: Icons.chevron_right_rounded,
                    tooltip: l10n.photoViewerNext,
                    onPressed: () => _go(_index + 1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PagerButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _PagerButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: IconButton.filled(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: 32,
        style: IconButton.styleFrom(
          backgroundColor: Colors.black54,
          foregroundColor: Colors.white,
        ),
        icon: Icon(icon),
      ),
    );
  }
}
