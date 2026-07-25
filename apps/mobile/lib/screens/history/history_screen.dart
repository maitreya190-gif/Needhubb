import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/user_state.dart';
import '../../theme/tokens.dart';
import '../rating/rating_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static const _items = [
    (
      name: 'Rohan Sharma',
      initials: 'RS',
      task: 'Calculus tutoring',
      date: '2 days ago',
      rating: 5,
      color: NeedHubTokens.ochre,
    ),
    (
      name: 'Priya Nair',
      initials: 'PN',
      task: 'Logo design',
      date: '1 week ago',
      rating: 4,
      color: NeedHubTokens.clay,
    ),
    (
      name: 'Dev Pillai',
      initials: 'DP',
      task: 'Photography gig',
      date: '2 weeks ago',
      rating: 0,
      color: NeedHubTokens.forest,
    ),
    (
      name: 'Kavya Rao',
      initials: 'KR',
      task: 'Moving help',
      date: '1 month ago',
      rating: 5,
      color: NeedHubTokens.ochre,
    ),
    (
      name: 'Arjun Das',
      initials: 'AD',
      task: 'Study group',
      date: '6 weeks ago',
      rating: 5,
      color: NeedHubTokens.clay,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        backgroundColor: t.paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'People you\'ve helped',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: t.ink,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          // Summary banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NeedHubTokens.forest.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: NeedHubTokens.forest.withValues(alpha: 0.20),
                  width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.favorite_outline_rounded,
                    color: NeedHubTokens.forest, size: 28),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You\'ve helped 7 people',
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                    Text(
                      'Average rating: 4.8 ★',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 13, color: t.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ValueListenableBuilder<Map<String, int>>(
            valueListenable: ratingsGivenNotifier,
            builder: (_, given, __) => Column(
              children: _items.map((item) {
                final effectiveRating = given[item.name] ?? item.rating;
                return _HistoryTile(
                  item: (
                    name: item.name,
                    initials: item.initials,
                    task: item.task,
                    date: item.date,
                    rating: effectiveRating,
                    color: item.color,
                  ),
                  t: t,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final ({
    String name,
    String initials,
    String task,
    String date,
    int rating,
    Color color
  }) item;
  final NeedHubTokens t;

  const _HistoryTile({required this.item, required this.t});

  @override
  Widget build(BuildContext context) {
    final rated = item.rating > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.rail, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                item.initials,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: item.color,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.task,
                    style:
                        GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted),
                  ),
                  const SizedBox(height: 6),
                  if (rated)
                    Row(
                      children: List.generate(
                        5,
                        (i) => Icon(
                          i < item.rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 13,
                          color: NeedHubTokens.ochre,
                        ),
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RatingScreen(
                            personName: item.name,
                            personInitials: item.initials,
                            taskLabel: item.task,
                          ),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: NeedHubTokens.clay,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Rate them',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Text(
              item.date,
              style: GoogleFonts.hankenGrotesk(fontSize: 11, color: t.muted),
            ),
          ],
        ),
      ),
    );
  }
}
