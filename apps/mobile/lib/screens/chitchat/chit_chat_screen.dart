import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/user_state.dart';
import '../../services/chitchat_api.dart';
import '../../services/messaging_api.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/nh_report_sheet.dart';
import '../hub/conversation_screen.dart';

class ChitChatScreen extends ConsumerStatefulWidget {
  const ChitChatScreen({super.key});

  @override
  ConsumerState<ChitChatScreen> createState() => _ChitChatScreenState();
}

class _ChitChatScreenState extends ConsumerState<ChitChatScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    chitChatAvailableNotifier.addListener(_bump);
    chitchatRosterNotifier.addListener(_bump);
    // Trigger an immediate refresh — main.dart's poller runs every 15s but we
    // want the screen to feel snappy on open.
    Future.microtask(() async {
      final api = ref.read(chitchatApiProvider);
      try {
        final status = await api.status();
        chitChatAvailableNotifier.value = status.available;
        chitchatAvailableUntilNotifier.value = status.availableUntil;
        chitchatRosterNotifier.value = await api.availablePeople();
      } catch (_) {/* swallow */}
    });
  }

  @override
  void dispose() {
    chitChatAvailableNotifier.removeListener(_bump);
    chitchatRosterNotifier.removeListener(_bump);
    super.dispose();
  }

  void _bump() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleAvailability(bool currentlyAvailable) async {
    if (_busy) return;
    setState(() => _busy = true);
    final api = ref.read(chitchatApiProvider);
    try {
      if (currentlyAvailable) {
        await api.clearAvailability();
        chitChatAvailableNotifier.value = false;
        chitchatAvailableUntilNotifier.value = null;
      } else {
        // Default 4h availability window.
        final status = await api.setAvailability(4);
        chitChatAvailableNotifier.value = true;
        chitchatAvailableUntilNotifier.value = status.availableUntil;
      }
      // Refresh roster after own state change.
      chitchatRosterNotifier.value = await api.availablePeople();
    } catch (_) {
      // Seamless offline fallback when backend API is unreachable
      chitChatAvailableNotifier.value = !currentlyAvailable;
      if (!currentlyAvailable) {
        chitchatAvailableUntilNotifier.value =
            DateTime.now().add(const Duration(hours: 4));
      } else {
        chitchatAvailableUntilNotifier.value = null;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final available = chitChatAvailableNotifier.value;

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
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, MediaQuery.of(context).padding.bottom + 24),
        children: [
          const SizedBox(height: 8),

          // Availability toggle
          GestureDetector(
            onTap: _busy ? null : () => _toggleAvailability(available),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: available ? NeedHubTokens.clay : t.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: available ? NeedHubTokens.clay : t.rail,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    available
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: available ? Colors.white : t.muted,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      available
                          ? "You're available for a chat right now"
                          : 'Mark yourself available',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: available ? Colors.white : t.muted2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Friends' DMs & Messages Section
          _ChitChatFriendsDmsHeader(t: t),

          if (available) ...[
            Text(
              'UP FOR A CHAT RIGHT NOW',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: t.muted2,
              ),
            ),
            const SizedBox(height: 12),

            _SelfTile(t: t),
            const SizedBox(height: 10),

            SizedBox(
              height: 68,
              child: chitchatRosterNotifier.value.isEmpty
                  ? Center(
                      child: Text(
                        'No one else is up for a chat right now',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13,
                          color: t.muted,
                        ),
                      ),
                    )
                  : ListView(
                      scrollDirection: Axis.horizontal,
                      children: chitchatRosterNotifier.value
                          .map((p) => _RealPersonCuboidalTile(person: p, t: t))
                          .toList(),
                    ),
            ),

            const SizedBox(height: 20),
          ],

          // Footer info card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.chip,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: t.muted2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Chit-chat is for casual hellos only. Each session is visible for 24 hours. You can turn it off anytime.',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 12.5,
                        color: t.muted2,
                        height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelfTile extends StatelessWidget {
  final NeedHubTokens t;

  const _SelfTile({required this.t});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NeedHubTokens.clay.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: NeedHubTokens.clay.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: NeedHubTokens.clay,
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: Text('YOU',
                  style: GoogleFonts.bricolageGrotesque(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('You (visible for 24h)',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: t.ink)),
                  const SizedBox(height: 3),
                  Text('Nearby people will see you first',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 12, color: t.muted)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: NeedHubTokens.forest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text('Live',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Real person tile (hydrated from API) ─────────────────────────────────────

class _RealPersonCuboidalTile extends ConsumerWidget {
  final ChitchatPerson person;
  final NeedHubTokens t;

  const _RealPersonCuboidalTile({required this.person, required this.t});

  String get _initials {
    final parts = person.displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ConversationScreen(
                name: person.displayName,
                initials: _initials,
                avatarColor: NeedHubTokens.forest,
                avatarUrl: person.avatarUrl,
                userId: person.userId,
              ),
            ),
          );
        },
        child: Container(
          width: 195,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.rail, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: NeedHubTokens.forest.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: person.avatarUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.network(
                          person.avatarUrl!,
                          width: 38,
                          height: 38,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Text(
                            _initials,
                            style: GoogleFonts.bricolageGrotesque(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: NeedHubTokens.forest,
                            ),
                          ),
                        ),
                      )
                    : Text(
                        _initials,
                        style: GoogleFonts.bricolageGrotesque(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: NeedHubTokens.forest,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      person.displayName,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      person.distanceLabel.isNotEmpty
                          ? person.distanceLabel
                          : 'Nearby',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 11,
                        color: t.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 16, color: NeedHubTokens.clay),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChitChatFriendsDmsHeader extends ConsumerWidget {
  final NeedHubTokens t;

  const _ChitChatFriendsDmsHeader({required this.t});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final realChats = chatsListNotifier.value;
    final hasReal = realChats.isNotEmpty;

    final mockFriends = <({String name, String initials, Color color, String message})>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              "FRIENDS' DMs",
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: t.muted2,
              ),
            ),
            const Spacer(),
            Text(
              "Direct Messages",
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: NeedHubTokens.clay,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (hasReal)
          ...realChats.map((c) {
            final initials = _initialsFor(c.otherDisplayName);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ConversationScreen(
                        name: c.otherDisplayName,
                        initials: initials,
                        avatarColor: NeedHubTokens.forest,
                        avatarUrl: c.otherAvatarUrl,
                        userId: c.otherUserId,
                        threadId: c.threadId,
                      ),
                    ),
                  );
                },
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
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: NeedHubTokens.forest.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        alignment: Alignment.center,
                        child: c.otherAvatarUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(13),
                                child: Image.network(c.otherAvatarUrl!,
                                    width: 44, height: 44, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Text(initials,
                                        style: GoogleFonts.bricolageGrotesque(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: NeedHubTokens.forest))),
                              )
                            : Text(initials,
                                style: GoogleFonts.bricolageGrotesque(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: NeedHubTokens.forest)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.otherDisplayName,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: t.ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              c.lastMessageBody ?? 'Tap to chat',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 12,
                                color: t.muted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chat_bubble_outline_rounded,
                          size: 20, color: NeedHubTokens.clay),
                    ],
                  ),
                ),
              ),
            );
          })
        else
          ...mockFriends.map((f) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ConversationScreen(
                        name: f.name,
                        initials: f.initials,
                        avatarColor: f.color,
                      ),
                    ),
                  );
                },
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
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: f.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          f.initials,
                          style: GoogleFonts.bricolageGrotesque(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: f.color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.name,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: t.ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              f.message,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 12,
                                color: t.muted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chat_bubble_outline_rounded,
                          size: 20, color: NeedHubTokens.clay),
                    ],
                  ),
                ),
              ),
            );
          }),

        const SizedBox(height: 14),
      ],
    );
  }

  static String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
