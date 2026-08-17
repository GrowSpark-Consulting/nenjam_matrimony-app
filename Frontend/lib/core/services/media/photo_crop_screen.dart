import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/buttons/primary_button.dart';
import 'image_compressor.dart';

/// Which overlay/export shape the crop screen presents.
///
/// Both shapes export a **square** image — [circle] only changes the visual
/// guide (a circular window, so the user sees what an avatar crop will look
/// like); the underlying capture is always the full square behind it.
enum CropShape { circle, square }

/// Full-screen "Crop & Adjust" step shown after picking a photo and before
/// upload — drag to pan, pinch to zoom, an optional 90°-step rotate, all
/// framed against a fixed 1:1 viewport.
///
/// Returns the finished, compressed image as an [XFile] via [Navigator.pop]
/// on confirm, or `null` if the user cancels. Reusable for any 1:1 photo
/// (profile avatar or gallery slot) — pass [CropShape.circle] only when this
/// photo is about to become the primary/display photo.
///
/// [XFile] rather than `dart:io`'s `File` so the whole crop-and-upload chain
/// works in the browser as well as on Android and iOS: it carries bytes on
/// web and a path on mobile, and `readAsBytes()` works on both.
class PhotoCropScreen extends StatefulWidget {
  const PhotoCropScreen({
    super.key,
    required this.imageFile,
    required this.shape,
    this.outputSize = 1080,
    this.jpegQuality = 88,
  });

  final XFile imageFile;
  final CropShape shape;
  final int outputSize;
  final int jpegQuality;

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen>
    with SingleTickerProviderStateMixin {
  final _boundaryKey = GlobalKey();

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  VoidCallback? _animListener;

  ui.Image? _image;
  bool _isLoadingSource = true;
  bool _loadError = false;
  bool _isProcessing = false;

  late double _viewportSize;

  double _scale = 1;
  double _minScale = 1;
  double _maxScale = 8;
  Offset _offset = Offset.zero;
  double _rotationRadians = 0;
  int _quarterTurns = 0;

  double _gestureBaseScale = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    _viewportSize = math
        .min(size.width - 48, size.height * 0.55)
        .clamp(200.0, 480.0);
  }

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    _anim.dispose();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    setState(() {
      _isLoadingSource = true;
      _loadError = false;
    });
    try {
      final bytes = await widget.imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      final image = frame.image;
      final minScale = _viewportSize / math.min(image.width, image.height);
      _image?.dispose();
      setState(() {
        _image = image;
        _minScale = minScale;
        // Raised from 4x so users can zoom in close enough to precisely
        // frame their face — initial view (_scale = minScale, below) still
        // shows the full image untouched.
        _maxScale = minScale * 8;
        _scale = minScale;
        _offset = Offset.zero;
        _rotationRadians = 0;
        _quarterTurns = 0;
        _isLoadingSource = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingSource = false;
        _loadError = true;
      });
    }
  }

  // ── Animation helper — smoothly tweens whichever of scale/offset/rotation
  // are passed, leaving the rest untouched. Reused for post-gesture snap
  // back, double-tap zoom, rotate, and reset.
  void _animateTo({double? scale, Offset? offset, double? rotation}) {
    final curved = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    final scaleTween = Tween<double>(begin: _scale, end: scale ?? _scale);
    final offsetTween = Tween<Offset>(begin: _offset, end: offset ?? _offset);
    final rotationTween = Tween<double>(
      begin: _rotationRadians,
      end: rotation ?? _rotationRadians,
    );

    if (_animListener != null) _anim.removeListener(_animListener!);
    _animListener = () {
      setState(() {
        _scale = scaleTween.transform(curved.value);
        _offset = offsetTween.transform(curved.value);
        _rotationRadians = rotationTween.transform(curved.value);
      });
    };
    _anim
      ..addListener(_animListener!)
      ..forward(from: 0);
  }

  // ── Gestures ──────────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails details) {
    _anim.stop();
    _gestureBaseScale = _scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _scale = (_gestureBaseScale * details.scale).clamp(_minScale, _maxScale);
      _offset += details.focalPointDelta;
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final clampedScale = _scale.clamp(_minScale, _maxScale);
    final clampedOffset = _clampOffset(_offset, clampedScale);
    if (clampedScale != _scale || clampedOffset != _offset) {
      _animateTo(scale: clampedScale, offset: clampedOffset);
    }
  }

  void _onDoubleTap() {
    final zoomedIn = _scale > _minScale + 0.01;
    _animateTo(
      scale: zoomedIn ? _minScale : _minScale * 2.2,
      offset: Offset.zero,
    );
  }

  Offset _clampOffset(Offset offset, double scale) {
    final image = _image;
    if (image == null) return Offset.zero;
    final w = image.width * scale;
    final h = image.height * scale;
    final rotated = _quarterTurns.isOdd;
    final effW = rotated ? h : w;
    final effH = rotated ? w : h;
    final maxDx = math.max(0.0, (effW - _viewportSize) / 2);
    final maxDy = math.max(0.0, (effH - _viewportSize) / 2);
    return Offset(
      offset.dx.clamp(-maxDx, maxDx),
      offset.dy.clamp(-maxDy, maxDy),
    );
  }

  void _onRotate() {
    if (_image == null) return;
    final newQuarterTurns = (_quarterTurns + 1) % 4;
    final newRotation = _rotationRadians + math.pi / 2;
    setState(() => _quarterTurns = newQuarterTurns);
    _animateTo(rotation: newRotation, scale: _minScale, offset: Offset.zero);
  }

  void _onReset() {
    setState(() {
      _quarterTurns = 0;
      _rotationRadians = 0;
    });
    _animateTo(scale: _minScale, offset: Offset.zero);
  }

  void _onCancel() {
    if (_isProcessing) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmCrop() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final renderObject = _boundaryKey.currentContext?.findRenderObject();
      final boundary = renderObject as RenderRepaintBoundary;
      final pixelRatio = widget.outputSize / _viewportSize;
      final captured = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await captured.toByteData(
        format: ui.ImageByteFormat.png,
      );
      captured.dispose();
      if (byteData == null) {
        throw StateError('Failed to capture cropped image');
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final jpegBytes = await ImageCompressor.compressToJpeg(
        pngBytes,
        quality: widget.jpegQuality,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        XFile.fromData(
          jpegBytes,
          name: 'crop.jpg',
          mimeType: 'image/jpeg',
          // Dio reads the bytes it was handed; length is set so multipart
          // can report Content-Length without re-reading.
          length: jpegBytes.lengthInBytes,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).photoCropProcessError),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isProcessing,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _buildAppBar(),
        body: _buildBody(),
        bottomNavigationBar: _isLoadingSource || _loadError
            ? null
            : _buildBottomBar(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: _isProcessing ? null : _onCancel,
        tooltip: AppLocalizations.of(context).commonCancel,
      ),
      title: Text(
        widget.shape == CropShape.circle
            ? AppLocalizations.of(context).photoCropAdjustProfileTitle
            : AppLocalizations.of(context).photoCropAdjustTitle,
        style: AppTypography.titleSmall.copyWith(color: Colors.white),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.rotate_90_degrees_cw_rounded),
          onPressed: (_isLoadingSource || _loadError || _isProcessing)
              ? null
              : _onRotate,
          tooltip: AppLocalizations.of(context).commonRotate,
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loadError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(context).photoCropLoadError,
                style: AppTypography.bodyMedium.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _loadImage,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                child: Text(AppLocalizations.of(context).commonRetry),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoadingSource || _image == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Center(child: _buildCropCanvas()),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _CropOverlayPainter(
                viewportSize: _viewportSize,
                shape: widget.shape,
              ),
            ),
          ),
        ),
        if (_isProcessing)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xAA000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: AppColors.accentGold,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppLocalizations.of(context).commonProcessing,
                      style: AppTypography.bodyMedium.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCropCanvas() {
    final image = _image!;
    return SizedBox(
      width: _viewportSize,
      height: _viewportSize,
      child: RepaintBoundary(
        key: _boundaryKey,
        child: ClipRect(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            onDoubleTap: _onDoubleTap,
            child: ColoredBox(
              color: Colors.black,
              child: Transform.translate(
                offset: _offset,
                child: Transform.rotate(
                  angle: _rotationRadians,
                  child: Transform.scale(
                    scale: _scale,
                    child: Center(
                      child: SizedBox(
                        width: image.width.toDouble(),
                        height: image.height.toDouble(),
                        child: RawImage(image: image, fit: BoxFit.fill),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Row(
        children: [
          TextButton(
            onPressed: _isProcessing ? null : _onReset,
            child: Text(
              AppLocalizations.of(context).commonReset,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 168,
            child: NmPrimaryButton(
              label: AppLocalizations.of(context).photoCropUsePhoto,
              isLoading: _isProcessing,
              onPressed: _isProcessing ? null : _confirmCrop,
            ),
          ),
        ],
      ),
    );
  }
}

/// Darkens everything outside the fixed crop viewport and draws a guide
/// border — a circle for profile photos (so the user sees what the avatar
/// mask will keep) or a square with rule-of-thirds lines for gallery photos.
/// Painted as a sibling of the capture [RepaintBoundary], never inside it, so
/// none of this chrome ends up in the exported image.
class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({required this.viewportSize, required this.shape});

  final double viewportSize;
  final CropShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final holeRect = Rect.fromCenter(
      center: center,
      width: viewportSize,
      height: viewportSize,
    );
    final outerPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final holePath = shape == CropShape.circle
        ? (Path()..addOval(holeRect))
        : (Path()..addRect(holeRect));
    final scrimPath = Path.combine(
      PathOperation.difference,
      outerPath,
      holePath,
    );
    canvas.drawPath(scrimPath, Paint()..color = const Color(0xCC000000));

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (shape == CropShape.circle) {
      canvas.drawOval(holeRect, borderPaint);
    } else {
      canvas.drawRect(holeRect, borderPaint);
      final guidePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      for (final f in [1 / 3, 2 / 3]) {
        canvas.drawLine(
          Offset(holeRect.left + holeRect.width * f, holeRect.top),
          Offset(holeRect.left + holeRect.width * f, holeRect.bottom),
          guidePaint,
        );
        canvas.drawLine(
          Offset(holeRect.left, holeRect.top + holeRect.height * f),
          Offset(holeRect.right, holeRect.top + holeRect.height * f),
          guidePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      oldDelegate.viewportSize != viewportSize || oldDelegate.shape != shape;
}
