import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NHFullScreenImageViewer extends StatefulWidget {
  final String? imageUrl;
  final String? imagePath;
  final String? heroTag;
  final String? title;
  final String? subtitle;

  const NHFullScreenImageViewer({
    super.key,
    this.imageUrl,
    this.imagePath,
    this.heroTag,
    this.title,
    this.subtitle,
  });

  static Future<void> open(
    BuildContext context, {
    String? imageUrl,
    String? imagePath,
    String? heroTag,
    String? title,
    String? subtitle,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: NHFullScreenImageViewer(
              imageUrl: imageUrl,
              imagePath: imagePath,
              heroTag: heroTag,
              title: title,
              subtitle: subtitle,
            ),
          );
        },
      ),
    );
  }

  @override
  State<NHFullScreenImageViewer> createState() => _NHFullScreenImageViewerState();
}

class _NHFullScreenImageViewerState extends State<NHFullScreenImageViewer> {
  final TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  String? get _resolvedImageUrl {
    final url = widget.imageUrl;
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://localhost:3000') ||
        url.startsWith('http://127.0.0.1:3000')) {
      return url.replaceAll(
          RegExp(r'http://(localhost|127\.0\.0\.1):3000'), 'http://10.0.2.2:3000');
    }
    if (url.startsWith('/')) {
      return 'http://10.0.2.2:3000$url';
    }
    return url;
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    if (_transformationController.value.getMaxScaleOnAxis() > 1.05) {
      _transformationController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      const double scale = 2.5;
      final double x = -position.dx * (scale - 1);
      final double y = -position.dy * (scale - 1);
      _transformationController.value = Matrix4.identity()
        // ignore: deprecated_member_use
        ..translate(x, y)
        // ignore: deprecated_member_use
        ..scale(scale);
    }
  }

  Widget _buildImage() {
    final url = _resolvedImageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
              color: Colors.white,
            ),
          );
        },
        errorBuilder: (_, __, ___) => const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_outlined, color: Colors.white70, size: 64),
            SizedBox(height: 12),
            Text(
              'Failed to load image',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    } else if (widget.imagePath != null && widget.imagePath!.isNotEmpty) {
      return Image.file(
        File(widget.imagePath!),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_outlined, color: Colors.white70, size: 64),
            SizedBox(height: 12),
            Text(
              'Image file not found',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 64);
  }

  @override
  Widget build(BuildContext context) {
    Widget imageWidget = _buildImage();

    if (widget.heroTag != null) {
      imageWidget = Hero(
        tag: widget.heroTag!,
        child: imageWidget,
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Dismiss background tap
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(color: Colors.transparent),
          ),

          // Interactive viewer for zooming/panning
          Center(
            child: GestureDetector(
              onDoubleTapDown: _handleDoubleTapDown,
              onDoubleTap: _handleDoubleTap,
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.8,
                maxScale: 5.0,
                child: SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: imageWidget,
                ),
              ),
            ),
          ),

          // Top Header Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 28),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.title != null)
                              Text(
                                widget.title!,
                                style: GoogleFonts.bricolageGrotesque(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            if (widget.subtitle != null)
                              Text(
                                widget.subtitle!,
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
