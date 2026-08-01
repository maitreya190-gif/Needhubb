import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../theme/tokens.dart';
import '../person/person_screen.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController controller = MobileScannerController();
  bool _processed = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Scan QR Code',
          style: GoogleFonts.bricolageGrotesque(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.videocam_off_rounded,
                        size: 72,
                        color: Colors.white38,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Camera unavailable',
                        style: GoogleFonts.bricolageGrotesque(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Please ensure camera permissions are enabled in your device settings to scan friend codes.',
                        style: GoogleFonts.hankenGrotesk(
                          color: Colors.white70,
                          fontSize: 14.5,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
            onDetect: (capture) {
              if (_processed) return;
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final String? rawValue = barcode.rawValue;
                if (rawValue != null && rawValue.startsWith('needhub:profile:')) {
                  _processed = true;
                  final userId = rawValue.replaceFirst('needhub:profile:', '');
                  
                  // Pop scanner first
                  Navigator.of(context).pop();
                  
                  // Push Profile
                  Navigator.of(context).push(
                    PersonScreen.route(
                      name: 'Loading...',
                      initials: '..',
                      avatarColor: NeedHubTokens.forest,
                      userId: userId,
                    ),
                  );
                  return;
                }
              }
            },
          ),
          
          // Scanning Target Frame Overlay
          Positioned.fill(
            child: _ScannerOverlay(),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        final double size = width * 0.72;

        return Stack(
          children: [
            // Darkened vignette background surrounding scanner box
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.65),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Scanner target outline box corners
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  children: [
                    _CornerBorder(
                      alignment: Alignment.topLeft,
                      dx: true,
                      dy: true,
                    ),
                    _CornerBorder(
                      alignment: Alignment.topRight,
                      dx: false,
                      dy: true,
                    ),
                    _CornerBorder(
                      alignment: Alignment.bottomLeft,
                      dx: true,
                      dy: false,
                    ),
                    _CornerBorder(
                      alignment: Alignment.bottomRight,
                      dx: false,
                      dy: false,
                    ),
                  ],
                ),
              ),
            ),
            
            // Instructions text overlay
            Positioned(
              top: height / 2 + size / 2 + 36,
              left: 30,
              right: 30,
              child: Column(
                children: [
                  Text(
                    'Position QR code inside the frame',
                    style: GoogleFonts.hankenGrotesk(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ensure lighting is bright enough to scan clearly',
                    style: GoogleFonts.hankenGrotesk(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CornerBorder extends StatelessWidget {
  final Alignment alignment;
  final bool dx;
  final bool dy;

  const _CornerBorder({
    required this.alignment,
    required this.dx,
    required this.dy,
  });

  @override
  Widget build(BuildContext context) {
    const double length = 24.0;
    const double thickness = 4.0;
    const Color color = Colors.white;

    return Align(
      alignment: alignment,
      child: SizedBox(
        width: length,
        height: length,
        child: Stack(
          children: [
            Positioned(
              left: dx ? 0 : null,
              right: !dx ? 0 : null,
              top: dy ? 0 : null,
              bottom: !dy ? 0 : null,
              child: Container(
                width: length,
                height: thickness,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Positioned(
              left: dx ? 0 : null,
              right: !dx ? 0 : null,
              top: dy ? 0 : null,
              bottom: !dy ? 0 : null,
              child: Container(
                width: thickness,
                height: length,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
