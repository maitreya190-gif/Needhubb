import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/user_state.dart';
import '../../services/chitchat_api.dart';
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _people = [
    (
      initials: 'AK',
      name: 'Aarav Kumar',
      area: 'Koramangala · 0.4 km',
      interest: 'on Flutter',
      color: NeedHubTokens.forest,
    ),
    (
      initials: 'MK',
      name: 'Meera Kulkarni',
      area: 'HSR Layout · 1.1 km',
      interest: 'on Startups',
      color: NeedHubTokens.clay,
    ),
    (
      initials: 'RV',
      name: 'Rohan Verma',
      area: 'Indiranagar · 1.8 km',
      interest: 'on Coffee',
      color: NeedHubTokens.ochre,
    ),
    (
      initials: 'PN',
      name: 'Priya Nair',
      area: 'Whitefield · 2.3 km',
      interest: 'on DSA',
      color: NeedHubTokens.forest,
    ),
  ];

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
          // Eyebrow
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: NeedHubTokens.clay.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'CHIT-CHAT',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: NeedHubTokens.clay,
              ),
            ),
          ),
          const SizedBox(height: 12),

          Text(
            'A quick, low-stakes hello.',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: t.ink,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Toggle yourself available and see who nearby is up for a quick casual chat. Auto-expires after 24 hours.',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 14, color: t.muted, height: 1.4),
          ),
          const SizedBox(height: 20),

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
          const SizedBox(height: 28),

          // Section header
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

          if (available) _SelfTile(t: t),

          // Real roster (hydrated by main.dart poller — refreshed every 15s).
          ...chitchatRosterNotifier.value.map(
            (p) => _RealPersonTile(person: p, t: t),
          ),

          // Fallback mock list — only when no real roster available.
          if (chitchatRosterNotifier.value.isEmpty)
            ..._people.map((p) => _PersonTile(person: p, t: t)),

          const SizedBox(height: 20),

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

class _PersonTile extends StatelessWidget {
  final ({
    String initials,
    String name,
    String area,
    String interest,
    Color color,
  }) person;
  final NeedHubTokens t;

  const _PersonTile({required this.person, required this.t});

  @override
  Widget build(BuildContext context) {
    final p = person;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _PersonProfileSheet(person: p, t: t),
        ),
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
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: p.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Text(p.initials,
                    style: GoogleFonts.bricolageGrotesque(
                        fontSize: 16, fontWeight: FontWeight.w700, color: p.color)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 14, fontWeight: FontWeight.w600, color: t.ink)),
                    const SizedBox(height: 3),
                    Text(p.area,
                        style: GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 20, color: t.muted2),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonProfileSheet extends StatefulWidget {
  final ({String initials, String name, String area, String interest, Color color}) person;
  final NeedHubTokens t;

  const _PersonProfileSheet({required this.person, required this.t});

  @override
  State<_PersonProfileSheet> createState() => _PersonProfileSheetState();
}

class _PersonProfileSheetState extends State<_PersonProfileSheet> {
  bool _friendRequested = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final p = widget.person;

    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 60),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).padding.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 24),

          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: p.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Text(p.initials,
                style: GoogleFonts.bricolageGrotesque(
                    fontSize: 28, fontWeight: FontWeight.w700, color: p.color)),
          ),
          const SizedBox(height: 12),

          Text(p.name,
              style: GoogleFonts.bricolageGrotesque(
                  fontSize: 22, fontWeight: FontWeight.w800, color: t.ink)),
          const SizedBox(height: 4),
          Text(p.area,
              style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted)),
          const SizedBox(height: 28),

          GestureDetector(
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(MaterialPageRoute(
                builder: (_) => ConversationScreen(
                  name: p.name,
                  initials: p.initials,
                  avatarColor: p.color,
                ),
              ));
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                  color: NeedHubTokens.clay, borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: Text('Start a Chat',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 10),

          GestureDetector(
            onTap: _friendRequested ? null : () => setState(() => _friendRequested = true),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: _friendRequested ? t.chip : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _friendRequested ? t.rail : t.ink.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                _friendRequested ? 'Friend Request Sent' : 'Add Friend',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _friendRequested ? t.muted : t.ink,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              NhReportSheet.open(context, targetName: p.name);
            },
            icon: Icon(Icons.flag_outlined,
                size: 16, color: Colors.red.shade400),
            label: Text(
              'Report',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade400,
              ),
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

class _RealPersonTile extends ConsumerWidget {
  final ChitchatPerson person;
  final NeedHubTokens t;

  const _RealPersonTile({required this.person, required this.t});

  String get _initials {
    final parts = person.displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Future<void> _message(BuildContext context) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          name: person.displayName,
          initials: _initials,
          avatarColor: NeedHubTokens.forest,
          userId: person.userId,
        ),
      ),
    );
  }

  Future<void> _sendFriend(BuildContext context, WidgetRef ref) async {
    final api = ref.read(friendsApiProvider);
    try {
      await api.sendRequest(person.userId);
      outgoingRequestUserIdsNotifier.value = {
        ...outgoingRequestUserIdsNotifier.value,
        person.userId,
      };
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Friend request sent to ${person.displayName}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFriend = friendUserIdsNotifier.value.contains(person.userId);
    final requestSent =
        outgoingRequestUserIdsNotifier.value.contains(person.userId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        // Tap anywhere on the ChitChat card → open the chat directly.
        onTap: () => _message(context),
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
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: NeedHubTokens.forest.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: person.avatarUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Image.network(person.avatarUrl!,
                          width: 46, height: 46, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Text(_initials,
                              style: GoogleFonts.bricolageGrotesque(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: NeedHubTokens.forest))),
                    )
                  : Text(_initials,
                      style: GoogleFonts.bricolageGrotesque(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: NeedHubTokens.forest)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(person.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.bricolageGrotesque(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: t.ink)),
                      ),
                      if (person.distanceLabel.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.place_rounded,
                            size: 11, color: NeedHubTokens.clay),
                        const SizedBox(width: 2),
                        Text(person.distanceLabel,
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: NeedHubTokens.clay)),
                      ],
                    ],
                  ),
                  if (person.bio?.isNotEmpty ?? false)
                    Text(person.bio!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 12, color: t.muted)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.chat_bubble_outline_rounded,
                  color: NeedHubTokens.clay, size: 20),
              onPressed: () => _message(context),
            ),
            if (!isFriend)
              GestureDetector(
                onTap: requestSent ? null : () => _sendFriend(context, ref),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: requestSent ? t.chip : NeedHubTokens.forest,
                    borderRadius: BorderRadius.circular(10),
                    border: requestSent
                        ? Border.all(color: t.rail, width: 1)
                        : null,
                  ),
                  child: Text(
                    requestSent ? 'Sent' : 'Add',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: requestSent ? t.muted : Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }
}
