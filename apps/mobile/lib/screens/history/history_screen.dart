import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/user_state.dart';
import '../../services/reviews_api.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';
import '../rating/rating_screen.dart';

class HistoryReviewItem {
  final String id;
  final String name;
  final String initials;
  final String task;
  final String date;
  final int rating;
  final String? comment;
  final Color color;

  const HistoryReviewItem({
    required this.id,
    required this.name,
    required this.initials,
    required this.task,
    required this.date,
    required this.rating,
    this.comment,
    required this.color,
  });
}

class HistoryScreen extends ConsumerStatefulWidget {
  final bool isOwnProfile;
  final String? personName;
  final String? userId;

  const HistoryScreen({
    super.key,
    this.isOwnProfile = true,
    this.personName,
    this.userId,
  });

  static const List<HistoryReviewItem> defaultReviews = [];

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<HistoryReviewItem> _reviews = HistoryScreen.defaultReviews;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.userId != null) {
      _fetchRealReviews();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refetch on every re-focus so newly-received ratings appear without
    // needing to logout/login.
    if (widget.userId != null) {
      _fetchRealReviews();
    }
  }

  Future<void> _fetchRealReviews() async {
    if (widget.userId == null) return;
    setState(() => _loading = true);
    try {
      final res = await ref.read(reviewsApiProvider).forUser(widget.userId!);
      if (res.reviews.isNotEmpty && mounted) {
        final List<HistoryReviewItem> parsed = [];
        for (int i = 0; i < res.reviews.length; i++) {
          final r = res.reviews[i];
          final reviewer = r['reviewer'] as Map<String, dynamic>? ?? {};
          final reviewerName = reviewer['displayName'] as String? ?? 'Someone';
          final need = r['need'] as Map<String, dynamic>? ?? {};
          final title = need['title'] as String? ?? 'Task completed';
          final rating = (r['rating'] as int?) ?? 5;
          final comment = r['comment'] as String?;
          final dateStr = r['createdAt'] as String?;

          parsed.add(HistoryReviewItem(
            id: r['id'] as String? ?? 'rev_$i',
            name: reviewerName,
            initials: _initials(reviewerName),
            task: title,
            date: dateStr != null ? _formatDate(dateStr) : 'Recently',
            rating: rating,
            comment: comment,
            color: i % 2 == 0 ? NeedHubTokens.ochre : NeedHubTokens.clay,
          ));
        }
        setState(() {
          _reviews = parsed;
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  static String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 30) return '${diff.inDays} days ago';
      return '${(diff.inDays / 30).floor()} month ago';
    } catch (_) {
      return 'Recently';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final titleText = widget.isOwnProfile
        ? 'People you\'ve helped'
        : '${widget.personName ?? "Past Work"} — Ratings';

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
          titleText,
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
          // Summary Banner
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isOwnProfile
                            ? 'You\'ve helped ${_reviews.length} people'
                            : 'Completed ${_reviews.length} tasks',
                        style: GoogleFonts.bricolageGrotesque(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: t.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.isOwnProfile
                            ? 'Average rating: 4.8 ★ • Tap review to see feedback'
                            : 'Average rating: 4.8 ★ • Feedback is private',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 12.5, color: t.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else
            ValueListenableBuilder<Map<String, int>>(
              valueListenable: ratingsGivenNotifier,
              builder: (_, given, __) => Column(
                children: _reviews.map((item) {
                  final effectiveRating = given[item.name] ?? item.rating;
                  final finalItem = HistoryReviewItem(
                    id: item.id,
                    name: item.name,
                    initials: item.initials,
                    task: item.task,
                    date: item.date,
                    rating: effectiveRating,
                    comment: item.comment,
                    color: item.color,
                  );
                  return _HistoryTile(
                    item: finalItem,
                    isOwnProfile: widget.isOwnProfile,
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

class _HistoryTile extends StatefulWidget {
  final HistoryReviewItem item;
  final bool isOwnProfile;
  final NeedHubTokens t;

  const _HistoryTile({
    required this.item,
    required this.isOwnProfile,
    required this.t,
  });

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final item = widget.item;
    final rated = item.rating > 0;
    final hasComment = item.comment != null && item.comment!.trim().isNotEmpty;
    final canExpand = widget.isOwnProfile && hasComment;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isExpanded ? NeedHubTokens.clay : t.rail,
            width: _isExpanded ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: canExpand
              ? () => setState(() => _isExpanded = !_isExpanded)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(13),
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
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 13, color: t.muted),
                          ),
                          const SizedBox(height: 6),
                          if (rated)
                            Row(
                              children: [
                                Row(
                                  children: List.generate(
                                    5,
                                    (i) => Icon(
                                      i < item.rating
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      size: 14,
                                      color: NeedHubTokens.ochre,
                                    ),
                                  ),
                                ),
                                if (canExpand) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    _isExpanded ? 'Hide feedback' : 'Tap to see feedback',
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: NeedHubTokens.clay,
                                    ),
                                  ),
                                ],
                              ],
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          item.date,
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 11, color: t.muted),
                        ),
                        if (canExpand) ...[
                          const SizedBox(height: 8),
                          Icon(
                            _isExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: NeedHubTokens.clay,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),

                // Expanded feedback container (visible ONLY for profile owner when expanded)
                if (widget.isOwnProfile && hasComment && _isExpanded) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.chip,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: NeedHubTokens.clay.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.rate_review_outlined,
                                size: 14, color: NeedHubTokens.clay),
                            const SizedBox(width: 6),
                            Text(
                              'FEEDBACK GIVEN TO YOU',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: NeedHubTokens.clay,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.comment!,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 13.5,
                            color: t.ink,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
