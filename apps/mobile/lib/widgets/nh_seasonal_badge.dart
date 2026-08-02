import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/league_api.dart';
import '../theme/tokens.dart';

/// Rank 1-5 permanent Impact League badges. Unlike the regular earned-badge
/// row (`nh_badge_row.dart`), these never re-evaluate or expire — a badge
/// here means a real season actually ended with this user in that exact
/// spot, recorded once and never touched again (see SeasonRankSnapshot in
/// lib/impact-league.ts).
class NhSeasonalBadgeRow extends StatelessWidget {
  final List<SeasonalBadge> badges;
  final NeedHubTokens t;

  const NhSeasonalBadgeRow({super.key, required this.badges, required this.t});

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) {
      return Text(
        'No seasonal badges yet — finish in the top 5 of an Impact League season to earn one.',
        style: GoogleFonts.hankenGrotesk(fontSize: 12.5, fontWeight: FontWeight.w500, color: t.muted),
      );
    }
    final sorted = [...badges]..sort((a, b) {
        final byYear = b.year.compareTo(a.year);
        return byYear != 0 ? byYear : b.seasonNumber.compareTo(a.seasonNumber);
      });
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sorted.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => NhSeasonalBadgeSeal(badge: sorted[i], t: t),
      ),
    );
  }
}

class _MedalStyle {
  final Color color;
  final IconData icon;
  const _MedalStyle(this.color, this.icon);
}

_MedalStyle _medalStyleForRank(int rank) {
  switch (rank) {
    case 1:
      return const _MedalStyle(Color(0xFFC9971A), Icons.emoji_events_rounded);
    case 2:
      return const _MedalStyle(Color(0xFF8A94A6), Icons.emoji_events_rounded);
    case 3:
      return const _MedalStyle(Color(0xFFAD6A3A), Icons.emoji_events_rounded);
    default:
      return const _MedalStyle(Color(0xFF6B3FA0), Icons.military_tech_rounded);
  }
}

class NhSeasonalBadgeSeal extends StatelessWidget {
  final SeasonalBadge badge;
  final NeedHubTokens t;

  const NhSeasonalBadgeSeal({super.key, required this.badge, required this.t});

  @override
  Widget build(BuildContext context) {
    final medal = _medalStyleForRank(badge.rank);
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('${badge.label} — Season ${badge.seasonNumber}, ${badge.year} · Rank #${badge.rank}'),
        )),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: medal.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: medal.color.withValues(alpha: 0.35), width: 1.5),
            ),
            child: Icon(medal.icon, color: medal.color, size: 26),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 62,
            child: Text(
              'S${badge.seasonNumber} · ${badge.year}',
              style: GoogleFonts.hankenGrotesk(fontSize: 10.5, fontWeight: FontWeight.w600, color: t.ink),
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
