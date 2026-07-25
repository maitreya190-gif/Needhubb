import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/auth_provider.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  /// When null: viewing own history (full detail). When provided: viewing
  /// another user's history (reviewer names are hidden for privacy).
  final String? userId;

  const HistoryScreen({super.key, this.userId});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  bool _loading = true;
  double _avg = 0;
  int _count = 0;
  List<Map<String, dynamic>> _reviews = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final auth = ref.read(authProvider);
      final targetId = widget.userId ?? auth.userId ?? '';
      if (targetId.isEmpty) {
        if (mounted) setState(() { _loading = false; });
        return;
      }
      final api = ref.read(reviewsApiProvider);
      final result = await api.forUser(targetId);
      if (mounted) {
        setState(() {
          _avg = result.avg;
          _count = result.count;
          _reviews = result.reviews;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load history.'; _loading = false; });
    }
  }

  bool get _isOwnProfile {
    final myId = ref.read(authProvider).userId;
    return widget.userId == null || widget.userId == myId;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isOwn = _isOwnProfile;

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
          isOwn ? 'People you\'ve helped' : 'Reviews',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: t.ink,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, color: t.muted, size: 40),
                      const SizedBox(height: 12),
                      Text(_error!, style: GoogleFonts.hankenGrotesk(color: t.muted)),
                      const SizedBox(height: 12),
                      TextButton(onPressed: () { setState(() { _loading = true; _error = null; }); _load(); }, child: const Text('Retry')),
                    ],
                  ),
                )
              : ListView(
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
                                isOwn
                                    ? 'You\'ve helped $_count ${_count == 1 ? 'person' : 'people'}'
                                    : '$_count ${_count == 1 ? 'review' : 'reviews'}',
                                style: GoogleFonts.bricolageGrotesque(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: t.ink,
                                ),
                              ),
                              if (_count > 0)
                                Text(
                                  'Average rating: ${_avg.toStringAsFixed(1)} ★',
                                  style: GoogleFonts.hankenGrotesk(
                                      fontSize: 13, color: t.muted),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_reviews.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Column(
                            children: [
                              Icon(Icons.history_rounded, size: 48, color: t.muted),
                              const SizedBox(height: 12),
                              Text(
                                isOwn ? 'No completed collaborations yet.' : 'No reviews yet.',
                                style: GoogleFonts.hankenGrotesk(color: t.muted, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._reviews.map((r) => _ReviewTile(review: r, isOwn: isOwn, t: t)),
                  ],
                ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final Map<String, dynamic> review;
  final bool isOwn;
  final NeedHubTokens t;

  const _ReviewTile({required this.review, required this.isOwn, required this.t});

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as int?) ?? 0;
    final comment = review['comment'] as String?;
    final need = review['need'] as Map<String, dynamic>? ?? const {};
    final reviewer = review['reviewer'] as Map<String, dynamic>? ?? const {};
    final reviewerProfile = reviewer['profile'] as Map<String, dynamic>?;
    final avatarUrl = reviewerProfile?['avatarUrl'] as String?;
    final reviewerName = isOwn
        ? (reviewer['displayName'] as String? ?? 'Someone')
        : 'Anonymous';
    final needTitle = need['title'] as String? ?? 'Collaboration';
    final createdAt = review['createdAt'] as String?;

    String dateLabel = '';
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt).toLocal();
        final diff = DateTime.now().difference(dt);
        if (diff.inDays == 0) {
          dateLabel = 'Today';
        } else if (diff.inDays == 1) {
          dateLabel = 'Yesterday';
        } else if (diff.inDays < 7) {
          dateLabel = '${diff.inDays}d ago';
        } else if (diff.inDays < 30) {
          dateLabel = '${(diff.inDays / 7).round()}w ago';
        } else {
          dateLabel = '${(diff.inDays / 30).round()}mo ago';
        }
      } catch (_) {}
    }

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar or initials
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: NeedHubTokens.ochre.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: avatarUrl != null && isOwn
                  ? Image.network(avatarUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _Initials(name: reviewerName))
                  : _Initials(name: isOwn ? reviewerName : '?'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reviewerName,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isOwn ? t.ink : t.muted2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    needTitle,
                    style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 13,
                        color: NeedHubTokens.ochre,
                      ),
                    ),
                  ),
                  if (comment != null && comment.isNotEmpty && isOwn) ...[
                    const SizedBox(height: 6),
                    Text(
                      '"$comment"',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 12, color: t.muted, fontStyle: FontStyle.italic),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (dateLabel.isNotEmpty)
              Text(
                dateLabel,
                style: GoogleFonts.hankenGrotesk(fontSize: 11, color: t.muted),
              ),
          ],
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String name;
  const _Initials({required this.name});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : (name.isNotEmpty ? name[0].toUpperCase() : '?');
    return Center(
      child: Text(
        initials,
        style: GoogleFonts.bricolageGrotesque(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: NeedHubTokens.ochre,
        ),
      ),
    );
  }
}
