import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/need.dart';
import '../theme/tokens.dart';

/// The visual Need card that actually gets shared to social apps.
///
/// Rendered off-screen to a PNG (see [renderShareCardPng]) so the same widget
/// is both the in-app preview and the shared image — there is no second,
/// drifting definition of what the card looks like.
///
/// Only public Need data is drawn here: title, short description, category,
/// budget, urgency, the poster's public name, and the *approximate* location
/// string. Coordinates are never used, matching the share-safe payload the
/// API builds in lib/share-card.ts.
class NhShareableNeedCard extends StatelessWidget {
  final Need need;

  /// Public URL the QR code points at — the same link that gets pasted.
  final String shareUrl;

  /// Fixed logical size keeps the exported image predictable across devices.
  static const double cardWidth = 360;

  const NhShareableNeedCard({
    super.key,
    required this.need,
    required this.shareUrl,
  });

  static const _ink = Color(0xFF2B1B16);
  static const _paper = Color(0xFFFBF3EF);
  static const _muted = Color(0xFF6C5750);

  String get _categoryLabel {
    switch (need.category.toLowerCase()) {
      case 'earn':
        return 'Earn';
      case 'connect':
        return 'Connect';
      case 'chitchat':
        return 'Chit-Chat';
      default:
        return need.category;
    }
  }

  String? get _budgetLabel {
    final min = need.budgetMin;
    final max = need.budgetMax;
    if (min == null && max == null) return null;
    if (min != null && max != null) {
      return min == max ? '₹$min' : '₹$min–₹$max';
    }
    return max != null ? 'Up to ₹$max' : 'From ₹$min';
  }

  @override
  Widget build(BuildContext context) {
    final budget = _budgetLabel;

    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand lockup
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  gradient: const LinearGradient(
                    colors: [NeedHubTokens.forest, NeedHubTokens.clay],
                    stops: [0.5, 0.5],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'NeedHub',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _CardChip(label: _categoryLabel, color: NeedHubTokens.forest),
              if (need.isUrgent)
                const _CardChip(label: 'Urgent', color: NeedHubTokens.clay),
              if (budget != null)
                _CardChip(label: budget, color: NeedHubTokens.ochre),
            ],
          ),
          const SizedBox(height: 12),

          Text(
            need.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 20,
              height: 1.25,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            need.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.hankenGrotesk(
              fontSize: 13.5,
              height: 1.45,
              color: _muted,
            ),
          ),
          const SizedBox(height: 18),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      need.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    if (need.location.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        need.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 12,
                          color: _muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Scan to open in NeedHub',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: QrImageView(
                  data: shareUrl,
                  version: QrVersions.auto,
                  size: 66,
                  gapless: true,
                  padding: EdgeInsets.zero,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardChip extends StatelessWidget {
  final String label;
  final Color color;

  const _CardChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.hankenGrotesk(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Rasterises whatever [boundaryKey] wraps into PNG bytes.
///
/// Returns null instead of throwing: sharing plain text still works if the
/// image cannot be produced, so a rendering failure must never take the whole
/// share flow down with it.
Future<Uint8List?> renderShareCardPng(
  GlobalKey boundaryKey, {
  double pixelRatio = 3.0,
}) async {
  try {
    final context = boundaryKey.currentContext;
    if (context == null) return null;
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    // A boundary that is still painting produces a blank or partial image;
    // waiting one frame is cheaper than shipping a broken card.
    if (boundary.debugNeedsPaint) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }

    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  } catch (e) {
    debugPrint('[share] failed to render need card image: $e');
    return null;
  }
}
