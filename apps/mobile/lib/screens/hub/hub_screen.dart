import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/need.dart';
import '../../theme/tokens.dart';
import 'tabs/hub_home_tab.dart';
import 'tabs/feed_tab.dart';
import 'tabs/chats_tab.dart';
import 'tabs/alerts_tab.dart';
import 'post_need_sheet.dart';
import '../you/you_screen.dart';
import '../needs/need_detail_screen.dart';
import '../../services/socket_service.dart';

class HubScreen extends ConsumerStatefulWidget {
  const HubScreen({super.key});

  @override
  ConsumerState<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends ConsumerState<HubScreen> {
  int _index = 0;

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

          // DEBUG socket status banner — remove after fixing sockets
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: ValueListenableBuilder<String>(
                valueListenable: socketDebugStatus,
                builder: (context, status, _) => ValueListenableBuilder<int>(
                  valueListenable: socketEventCount,
                  builder: (context, count, _) => Container(
                    color: status.startsWith('✅')
                        ? Colors.green.withOpacity(0.85)
                        : Colors.red.withOpacity(0.85),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      'SOCKET: $status  |  events: $count',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Custom blurred bottom nav
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _NavBar(
              currentIndex: _index,
              onTap: (i) {
                if (i == 2) {
                  _showPostSheet();
                } else {
                  setState(() => _index = i);
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

  const _NavBar({required this.currentIndex, required this.onTap});

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
                label: 'Home',
                active: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Chats',
                active: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              // FAB
              GestureDetector(
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
                icon: Icons.notifications_outlined,
                label: 'Alerts',
                active: currentIndex == 3,
                onTap: () => onTap(3),
              ),
              _NavItem(
                icon: Icons.person_outline_rounded,
                label: 'You',
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

