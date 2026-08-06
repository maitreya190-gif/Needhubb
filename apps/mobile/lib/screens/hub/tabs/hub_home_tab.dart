import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../l10n/app_strings.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/language_provider.dart';
import '../../../services/reviews_api.dart';
import '../../../services/social_providers.dart';
import '../../../theme/tokens.dart';
import '../../chitchat/chit_chat_screen.dart';
import '../../personality/personality_test_screen.dart';
import '../../rating/rating_screen.dart';
import '../../../services/profiles_api.dart';

class HubHomeTab extends ConsumerWidget {
  final VoidCallback onBrowseEarn;
  final VoidCallback onBrowseConnect;
  final VoidCallback onPost;
  final VoidCallback onOpenChats;

  /// Spotlight anchor for the first-run tour. Null outside the tour.
  final GlobalKey? exploreKey;

  const HubHomeTab({
    super.key,
    required this.onBrowseEarn,
    required this.onBrowseConnect,
    required this.onPost,
    required this.onOpenChats,
    this.exploreKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder<String>(
      valueListenable: uiLanguageNotifier,
      builder: (context, _, __) => _build(context, ref),
    );
  }

  Widget _build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final s = S.current;
    final auth = ref.watch(authProvider);
    final firstName = (auth.displayName ?? 'there').split(' ').first;

    return Scaffold(
      backgroundColor: t.paper,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: NeedHubTokens.clay,
          onRefresh: () async {
            try {
              pendingReviewsNotifier.value =
                  await ref.read(reviewsApiProvider).pending();
            } catch (_) {/* keep last-known list */}
          },
          child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: greeting + chat button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.welcomeBack,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: t.muted,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          s.hiGreeting(firstName),
                          style: GoogleFonts.bricolageGrotesque(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: t.ink,
                            letterSpacing: -0.52,
                            height: 1.12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ChitChatScreen(),
                        ),
                      );
                    },
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: t.card,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: t.ink.withValues(alpha: 0.09),
                          width: 1,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 22,
                              color: NeedHubTokens.clay,
                            ),
                          ),
                          Positioned(
                            top: 9,
                            right: 10,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: NeedHubTokens.clay,
                                shape: BoxShape.circle,
                                border: Border.all(color: t.card, width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // CTA buttons
              Column(
                children: [
                  // Add a need
                  GestureDetector(
                    onTap: onPost,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment(-0.9, -0.4),
                          end: Alignment(0.9, 0.4),
                          colors: [Color(0xFFE0971C), Color(0xFFC46A1E)],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFFE0971C).withValues(alpha: 0.7),
                            offset: const Offset(0, 14),
                            blurRadius: 26,
                            spreadRadius: -14,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.addANeed,
                                  style: GoogleFonts.bricolageGrotesque(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s.addANeedSubtitle,
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 13),

                  // Explore needs
                  GestureDetector(
                    key: exploreKey,
                    onTap: onBrowseEarn,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment(-0.9, -0.4),
                          end: Alignment(0.9, 0.4),
                          colors: [Color(0xFF1E6B4E), Color(0xFF155239)],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF1E6B4E).withValues(alpha: 0.7),
                            offset: const Offset(0, 14),
                            blurRadius: 26,
                            spreadRadius: -14,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: const Icon(
                              Icons.search_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.exploreNeeds,
                                  style: GoogleFonts.bricolageGrotesque(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s.helpEarnSubtitle,
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 13),

                  // Personality Test — powered by Lyzr
                  _PersonalityCta(t: t),
                ],
              ),
              const SizedBox(height: 26),

              // Pending ratings section
              _PendingRatingsSection(t: t),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _PendingRatingsSection extends StatefulWidget {
  final NeedHubTokens t;

  const _PendingRatingsSection({required this.t});

  @override
  State<_PendingRatingsSection> createState() => _PendingRatingsSectionState();
}

class _PendingRatingsSectionState extends State<_PendingRatingsSection> {
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    pendingReviewsNotifier.addListener(_bump);
  }

  @override
  void dispose() {
    pendingReviewsNotifier.removeListener(_bump);
    super.dispose();
  }

  void _bump() {
    if (mounted) setState(() {});
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final pending = pendingReviewsNotifier.value;

    // Real pending review card — take the newest one.
    if (pending.isNotEmpty) {
      final t = widget.t;
      final p = pending.first;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(S.current.rateACompletedNeed,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 13, fontWeight: FontWeight.w700, color: t.ink)),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 1, color: t.rail)),
              if (pending.length > 1) ...[
                const SizedBox(width: 8),
                Text('+${pending.length - 1} ${S.current.more}',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 11, color: t.muted2)),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              color: t.card,
              border:
                  Border.all(color: t.ink.withValues(alpha: 0.08), width: 1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: NeedHubTokens.clay,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: p.counterpartyAvatarUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(p.counterpartyAvatarUrl!,
                              width: 40, height: 40, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Text(
                                  _initials(p.counterpartyName),
                                  style: GoogleFonts.bricolageGrotesque(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white))),
                        )
                      : Text(_initials(p.counterpartyName),
                          style: GoogleFonts.bricolageGrotesque(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.counterpartyName,
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: t.ink)),
                      Text(p.needTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 12, color: t.muted)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RatingScreen(
                        personName: p.counterpartyName,
                        personInitials: _initials(p.counterpartyName),
                        taskLabel: p.needTitle,
                        needId: p.needId,
                        revieweeId: p.counterpartyId,
                      ),
                    ),
                  ),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    decoration: BoxDecoration(
                      color: NeedHubTokens.clay,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(S.current.feedback,
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_dismissed || pending.isEmpty) {
      final t = widget.t;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.rail, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                color: NeedHubTokens.forest, size: 22),
            const SizedBox(width: 10),
            Text(
              S.current.allCaughtUp,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.ink,
              ),
            ),
          ],
        ),
      );
    }

    final t = widget.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              S.current.rateACompletedNeed,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Container(height: 1, color: t.rail)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            color: t.card,
            border: Border.all(color: t.ink.withValues(alpha: 0.08), width: 1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: NeedHubTokens.clay,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  'DP',
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dev Pillai',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                    Text(
                      'Photography gig',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 12,
                        color: t.muted,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RatingScreen(
                      personName: 'Dev Pillai',
                      personInitials: 'DP',
                      taskLabel: 'Photography gig',
                    ),
                  ),
                ).then((_) {
                  if (mounted) setState(() => _dismissed = true);
                }),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    color: NeedHubTokens.clay,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    S.current.feedback,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Personality quiz CTA on the home surface. Shows a different subtitle
/// once the user has taken the test so they know they can re-view results.
class _PersonalityCta extends StatelessWidget {
  final NeedHubTokens t;
  const _PersonalityCta({required this.t});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileMe?>(
      valueListenable: myProfileNotifier,
      builder: (context, me, __) {
        final hasTaken = me?.hasPersonality ?? false;
        final subtitle = hasTaken
            ? S.current.personalityResultSubtitle(me?.personalityNickname ?? '')
            : S.current.personalityCtaSubtitle;
        return GestureDetector(
          onTap: () {
            // Once taken, the test is one-shot — send them straight to
            // their result screen instead of the quiz.
            final myProfile = me?.personalityProfile;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => myProfile != null
                    ? PersonalityResultScreen(profile: myProfile)
                    : const PersonalityTestScreen(),
              ),
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment(-0.9, -0.4),
                end: Alignment(0.9, 0.4),
                colors: [Color(0xFF7A3EA6), Color(0xFF4E2073)],
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7A3EA6).withValues(alpha: 0.55),
                  offset: const Offset(0, 14),
                  blurRadius: 26,
                  spreadRadius: -14,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.psychology_alt_rounded,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            S.current.personalityTest,
                            style: GoogleFonts.bricolageGrotesque(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'AI',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.white, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
