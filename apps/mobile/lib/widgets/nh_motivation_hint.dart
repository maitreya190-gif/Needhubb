import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/league_api.dart';
import '../theme/tokens.dart';

/// The entire "motivation system" (requirement 8) — a small, subtle pill
/// shown only when a user is genuinely close to a notable rank threshold.
/// The server decides when this is worth showing at all (see
/// nearestMotivationMilestone in lib/impact-league.ts); this widget just
/// renders it or renders nothing. No polling, no notification — it is
/// whatever came back with the rank the screen already fetched.
class NhMotivationHint extends StatelessWidget {
  final MotivationHint? hint;
  final NeedHubTokens t;

  const NhMotivationHint({super.key, required this.hint, required this.t});

  @override
  Widget build(BuildContext context) {
    final h = hint;
    if (h == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: NeedHubTokens.forest.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        h.spotsAway == 1
            ? '1 spot from ${h.label}'
            : '${h.spotsAway} spots from ${h.label}',
        style: GoogleFonts.hankenGrotesk(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: NeedHubTokens.forest,
        ),
      ),
    );
  }
}
