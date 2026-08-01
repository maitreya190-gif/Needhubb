import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/profiles_api.dart';
import '../theme/tokens.dart';

/// Horizontal row of earned badges, used on both your own profile and on
/// someone else's.
///
/// Every badge shown here was computed by the server from something that
/// actually happened — a verification, a completed need, a review. Nothing is
/// hardcoded on the client, which is the whole point: the version this replaced
/// showed every new user "First Help", "5-Star" and "Quick Reply" marked as
/// earned before they had done anything.
///
/// Locked badges render greyed rather than hidden, so the row doubles as a
/// list of what is still available to earn.
class NhBadgeRow extends StatelessWidget {
  final List<ProfileBadge> badges;
  final NeedHubTokens t;

  /// Own profile shows locked badges as goals; on someone else's profile they
  /// are noise, so only earned ones appear there.
  final bool showLocked;

  const NhBadgeRow({
    super.key,
    required this.badges,
    required this.t,
    this.showLocked = true,
  });

  static const _plum = Color(0xFF6B3FA0);

  static IconData iconFor(String badgeId) {
    switch (badgeId) {
      case 'email_verified':
        return Icons.alternate_email_rounded;
      case 'phone_verified':
        return Icons.phone_android_rounded;
      case 'face_verified':
        return Icons.face_retouching_natural_rounded;
      case 'fully_verified':
        return Icons.verified_user_rounded;
      case 'first_help':
        return Icons.handshake_outlined;
      case 'helping_hand':
        return Icons.volunteer_activism_outlined;
      case 'reliable':
        return Icons.shield_moon_outlined;
      case 'veteran':
        return Icons.military_tech_outlined;
      case 'follows_through':
        return Icons.task_alt_rounded;
      case 'five_star':
        return Icons.star_rounded;
      case 'well_reviewed':
        return Icons.reviews_outlined;
      case 'certified':
        return Icons.workspace_premium_outlined;
      case 'community_builder':
        return Icons.diversity_3_outlined;
      default:
        return Icons.emoji_events_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        showLocked ? badges : badges.where((b) => b.earned).toList();

    if (visible.isEmpty) {
      return Text(
        showLocked
            ? 'No badges yet — verify your account or complete a need to earn your first.'
            : 'No badges earned yet.',
        style: GoogleFonts.hankenGrotesk(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: t.muted,
        ),
      );
    }

    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _BadgeSeal(badge: visible[i], t: t),
      ),
    );
  }
}

class _BadgeSeal extends StatelessWidget {
  final ProfileBadge badge;
  final NeedHubTokens t;

  const _BadgeSeal({required this.badge, required this.t});

  @override
  Widget build(BuildContext context) {
    final color = badge.earned ? NhBadgeRow._plum : t.muted;
    return GestureDetector(
      // Tapping explains what the badge takes — important for locked ones,
      // which are otherwise just a grey square with a short label.
      onTap: () => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(badge.earned
              ? '${badge.label} — earned'
              : '${badge.label} — ${badge.description}'),
        )),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: badge.earned
                  ? NhBadgeRow._plum.withValues(alpha: 0.12)
                  : t.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: badge.earned
                    ? NhBadgeRow._plum.withValues(alpha: 0.30)
                    : t.rail,
                width: 1.5,
              ),
            ),
            child: Icon(NhBadgeRow.iconFor(badge.id), color: color, size: 24),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 62,
            child: Text(
              badge.label,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
