import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_strings.dart';
import '../../theme/tokens.dart';
import '../../widgets/nh_button.dart';

const String _kTutorialPendingKey = 'nh_tutorial_pending';

/// Called at the end of signup so the tour is queued for brand-new accounts
/// only. Users who were already signed in never get the flag, so they never
/// see the tour.
Future<void> markTutorialPending() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kTutorialPendingKey, true);
}

Future<void> maybeShowTutorial(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kTutorialPendingKey) != true) return;
  // Cleared before showing so a crash mid-tour can't trap the user in a loop.
  await prefs.remove(_kTutorialPendingKey);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const TutorialScreen(),
      fullscreenDialog: true,
    ),
  );
}

class _Slide {
  final IconData icon;
  final List<Color> gradient;
  final String title;
  final String body;
  final List<(IconData, String)> points;

  const _Slide({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.body,
    required this.points,
  });
}

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_Slide> _slides() {
    final s = S.current;
    return [
      _Slide(
        icon: Icons.waving_hand_rounded,
        gradient: const [Color(0xFFE1553B), Color(0xFFB53A24)],
        title: s.tutWelcomeTitle,
        body: s.tutWelcomeBody,
        points: [
          (Icons.add_circle_outline_rounded, s.tutWelcomePoint1),
          (Icons.volunteer_activism_rounded, s.tutWelcomePoint2),
          (Icons.how_to_reg_rounded, s.tutWelcomePoint3),
        ],
      ),
      _Slide(
        icon: Icons.add_rounded,
        gradient: const [Color(0xFFE0971C), Color(0xFFC46A1E)],
        title: s.tutPostTitle,
        body: s.tutPostBody,
        points: [
          (Icons.swap_horiz_rounded, s.tutPostPoint1),
          (Icons.auto_awesome_rounded, s.tutPostPoint2),
          (Icons.bolt_rounded, s.tutPostPoint3),
        ],
      ),
      _Slide(
        icon: Icons.search_rounded,
        gradient: const [Color(0xFF1E6B4E), Color(0xFF155239)],
        title: s.tutExploreTitle,
        body: s.tutExploreBody,
        points: [
          (Icons.tune_rounded, s.tutExplorePoint1),
          (Icons.map_outlined, s.tutExplorePoint2),
          (Icons.send_rounded, s.tutExplorePoint3),
        ],
      ),
      _Slide(
        icon: Icons.chat_bubble_outline_rounded,
        gradient: const [Color(0xFF2E6BA8), Color(0xFF1C4776)],
        title: s.tutChatTitle,
        body: s.tutChatBody,
        points: [
          (Icons.coffee_rounded, s.tutChatPoint1),
          (Icons.translate_rounded, s.tutChatPoint2),
          (Icons.shield_outlined, s.tutChatPoint3),
        ],
      ),
      _Slide(
        icon: Icons.verified_user_outlined,
        gradient: const [Color(0xFF7A3EA6), Color(0xFF4E2073)],
        title: s.tutTrustTitle,
        body: s.tutTrustBody,
        points: [
          (Icons.fingerprint_rounded, s.tutTrustPoint1),
          (Icons.star_outline_rounded, s.tutTrustPoint2),
          (Icons.workspace_premium_outlined, s.tutTrustPoint3),
        ],
      ),
      _Slide(
        icon: Icons.emoji_events_outlined,
        gradient: const [Color(0xFFD4A017), Color(0xFF9A6A0E)],
        title: s.tutRewardsTitle,
        body: s.tutRewardsBody,
        points: [
          (Icons.redeem_rounded, s.tutRewardsPoint1),
          (Icons.leaderboard_rounded, s.tutRewardsPoint2),
          (Icons.card_giftcard_rounded, s.tutRewardsPoint3),
        ],
      ),
    ];
  }

  void _next(int total) {
    if (_index >= total - 1) {
      Navigator.of(context).pop();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;
    final slides = _slides();
    final isLast = _index == slides.length - 1;

    return Scaffold(
      backgroundColor: t.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(
                children: [
                  Text(
                    'NeedHub',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: t.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      s.tutSkip,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _SlideView(
                  slide: slides[i],
                  footnote: i == slides.length - 1 ? s.tutMoreNote : null,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(slides.length, (i) {
                      final active = i == _index;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        height: 6,
                        width: active ? 20 : 6,
                        decoration: BoxDecoration(
                          color: active ? NeedHubTokens.clay : t.rail2,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 18),
                  NhPrimaryButton(
                    label: isLast ? '${s.startExploring} →' : s.next,
                    onPressed: () => _next(slides.length),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  final String? footnote;

  const _SlideView({required this.slide, this.footnote});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: const Alignment(-0.9, -0.4),
                end: const Alignment(0.9, 0.4),
                colors: slide.gradient,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: slide.gradient.first.withValues(alpha: 0.55),
                  offset: const Offset(0, 14),
                  blurRadius: 26,
                  spreadRadius: -12,
                ),
              ],
            ),
            child: Icon(slide.icon, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 26),
          Text(
            slide.title,
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              color: t.ink,
              letterSpacing: -0.6,
              height: 1.14,
            ),
          ),
          const SizedBox(height: 11),
          Text(
            slide.body,
            style: GoogleFonts.hankenGrotesk(
              fontSize: 15,
              height: 1.45,
              color: t.muted2,
            ),
          ),
          const SizedBox(height: 24),
          for (final (icon, label) in slide.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: slide.gradient.first.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, size: 18, color: slide.gradient.first),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        label,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 14.5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: t.ink2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (footnote != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.card,
                border: Border.all(color: t.rail, width: 1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                footnote!,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 13,
                  height: 1.45,
                  color: t.muted2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
