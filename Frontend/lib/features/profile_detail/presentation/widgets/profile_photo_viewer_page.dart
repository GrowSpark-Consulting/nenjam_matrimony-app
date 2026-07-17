import 'package:flutter/material.dart';

/// Full-screen photo viewer opened from the photo gallery — swipe between
/// photos, pinch/double-tap to zoom. Built entirely from stock Flutter
/// widgets ([PageView] + [InteractiveViewer]); the project has no
/// `photo_view`/`carousel_slider` dependency to reach for instead.
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
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${_index + 1} / ${widget.photoUrls.length}'),
      ),
      body: PageView.builder(
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
    );
  }
}
