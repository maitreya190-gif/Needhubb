import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_strings.dart';
import '../../models/need.dart';
import '../../providers/language_provider.dart';
import '../../theme/tokens.dart';
import '../onboarding/tutorial_screen.dart';
import 'tabs/hub_home_tab.dart';
import 'tabs/feed_tab.dart';
import 'tabs/chats_tab.dart';
import 'tabs/alerts_tab.dart';
import 'post_need_sheet.dart';
import '../you/you_screen.dart';
import '../needs/need_detail_screen.dart';

class HubScreen extends ConsumerStatefulWidget {
  const HubScreen({super.key});

  @override
  ConsumerState<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends ConsumerState<HubScreen> {
  int _index = 0;

  // Spotlight anchors for the first-run tour. Nothing else reads these.
  final _exploreKey = GlobalKey();
  final _fabKey = GlobalKey();
  final _chatsNavKey = GlobalKey();
  final _alertsNavKey = GlobalKey();
  final _youNavKey = GlobalKey();
  bool _tourActive = false;

  @override
  void initState() {
    super.initState();
    uiLanguageNotifier.addListener(_onLangChange);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (await consumeTutorialPending() && mounted) {
        setState(() => _tourActive = true);
      }
    });
  }

  List<TourStep> _tourSteps() {
    final s = S.current;
    return [
      TourStep(
        tab: 0,
        title: s.tutWelcomeTitle,
        body: s.tutWelcomeBody,
      ),
      TourStep(
        tab: 0,
        target: _fabKey,
        radius: 20,
        title: s.tutPostTitle,
        body: s.tutPostBody,
        chips: [s.tutPostChip1, s.tutPostChip2, s.tutPostChip3],
      ),
      TourStep(
        tab: 0,
        target: _exploreKey,
        radius: 22,
        title: s.tutExploreTitle,
        body: s.tutExploreBody,
        chips: [s.tutExploreChip1, s.tutExploreChip2, s.tutExploreChip3],
      ),
      TourStep(
        tab: 1,
        target: _chatsNavKey,
        radius: 14,
        title: s.tutChatsTitle,
        body: s.tutChatsBody,
        chips: [s.tutChatsChip1, s.tutChatsChip2, s.tutChatsChip3],
      ),
      TourStep(
        tab: 3,
        target: _alertsNavKey,
        radius: 14,
        title: s.tutAlertsTitle,
        body: s.tutAlertsBody,
        chips: [s.tutAlertsChip1, s.tutAlertsChip2],
      ),
      TourStep(
        tab: 4,
        target: _youNavKey,
        radius: 14,
        title: s.tutYouTitle,
        body: s.tutYouBody,
        chips: [
          s.tutYouChip1,
          s.tutYouChip2,
          s.tutYouChip3,
          s.tutYouChip4,
        ],
      ),
    ];
  }

  @override
  void dispose() {
    uiLanguageNotifier.removeListener(_onLangChange);
    super.dispose();
  }

  void _onLangChange() {
    if (mounted) setState(() {});
  }

  void _browseTo(BuildContext ctx, String surface) {
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => FeedTab(initialSurface: surface),
      ),
    );
  }

  Future<void> _showPostSheet() async {
    final need = await showModalBottomSheet<Need>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PostNeedSheet(),
    );
    if (need != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NeedDetailScreen(need: need)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final List<Widget> pages = [
      HubHomeTab(
        exploreKey: _exploreKey,
        onBrowseEarn: () => _browseTo(context, 'earn'),
        onBrowseConnect: () => _browseTo(context, 'connect'),
        onPost: () => _showPostSheet(),
        onOpenChats: () => setState(() => _index = 1),
      ),
      const ChatsTab(),
      const SizedBox.shrink(),
      const AlertsTab(),
      const YouScreen(),
    ];

    return Scaffold(
      backgroundColor: t.paper,
      body: Stack(
        children: [
          // Main content with bottom padding for the nav bar
          Positioned.fill(
            child: IndexedStack(
              index: _index,
              children: pages,
            ),
          ),

          // Custom blurred bottom nav
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _NavBar(
              currentIndex: _index,
              fabKey: _fabKey,
              chatsKey: _chatsNavKey,
              alertsKey: _alertsNavKey,
              youKey: _youNavKey,
              onTap: (i) {
                if (i == 2) {
                  _showPostSheet();
                } else {
                  setState(() => _index = i);
                }
              },
            ),
          ),

          // First-run guided tour — sits above the nav bar so it can spotlight it.
          if (_tourActive)
            Positioned.fill(
              child: TutorialOverlay(
                steps: _tourSteps(),
                onGoToTab: (i) {
                  if (_index != i) setState(() => _index = i);
                },
                onFinish: () {
                  if (mounted) {
                    setState(() {
                      _tourActive = false;
                      _index = 0;
                    });
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Nav bar ──────────────────────────────────────────────────────────────────

class _NavBar extends ConsumerWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final GlobalKey? fabKey;
  final GlobalKey? chatsKey;
  final GlobalKey? alertsKey;
  final GlobalKey? youKey;

  const _NavBar({
    required this.currentIndex,
    required this.onTap,
    this.fabKey,
    this.chatsKey,
    this.alertsKey,
    this.youKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          color: t.nav,
          padding: EdgeInsets.only(
            left: 8,
            right: 8,
            top: 10,
            bottom: bottomPad + 10,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: S.current.home,
                active: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                key: chatsKey,
                icon: Icons.chat_bubble_outline_rounded,
                label: S.current.chats,
                active: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              // FAB
              GestureDetector(
                key: fabKey,
                onTap: () => onTap(2),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: NeedHubTokens.clay,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: NeedHubTokens.clay.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              _NavItem(
                key: alertsKey,
                icon: Icons.notifications_outlined,
                label: S.current.alerts,
                active: currentIndex == 3,
                onTap: () => onTap(3),
              ),
              _NavItem(
                key: youKey,
                icon: Icons.person_outline_rounded,
                label: S.current.you,
                active: currentIndex == 4,
                onTap: () => onTap(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = active ? NeedHubTokens.clay : t.muted;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

