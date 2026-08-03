import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/tokens.dart';

/// Small "PLUS" pill shown next to a name wherever a poster/user holds an
/// active NeedHub Plus subscription — see profile.plus in the API responses
/// (GET /profile/me, /profile/:userId, feed poster.profile, ChitChat roster
/// rows). Purely cosmetic — it never affects ranking itself, only labels
/// what the (separately, moderately, capped) ranking bonus already did.
class NhPlusBadge extends StatelessWidget {
  final bool compact;

  const NhPlusBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        width: 16,
        height: 16,
        decoration: const BoxDecoration(color: NeedHubTokens.ochre, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const Icon(Icons.star_rounded, size: 10, color: Colors.white),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: NeedHubTokens.ochre,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            'PLUS',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
