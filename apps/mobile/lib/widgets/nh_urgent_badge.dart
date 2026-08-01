import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/need.dart';

/// Small "⚡ 3h left" pill for an urgent need — the one thing about Urgency
/// Mode a viewer is meant to see. The AI's internal confidence and rescue
/// stage never reach the client at all, so there is nothing else to show.
///
/// Renders nothing for a non-urgent need or one whose countdown has already
/// lapsed (that reads as EXPIRED instead — see need.isExpiredUrgent).
class NhUrgentBadge extends StatelessWidget {
  final Need need;
  final bool compact;

  const NhUrgentBadge({super.key, required this.need, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final countdown = need.urgencyCountdown;
    if (!need.isUrgent || countdown == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10, vertical: compact ? 3 : 4),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: compact ? 11 : 12, color: Colors.red.shade600),
          const SizedBox(width: 3),
          Text(
            countdown,
            style: GoogleFonts.hankenGrotesk(
              fontSize: compact ? 10.5 : 11,
              fontWeight: FontWeight.w700,
              color: Colors.red.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
