import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/friend_request.dart';
import '../../../models/user_state.dart';
import '../../../services/api_client.dart';
import '../../../services/friends_api.dart';
import '../../../services/messaging_api.dart';
import '../../../services/social_providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/nh_avatar.dart';
import '../../../widgets/nh_skeleton.dart';
import '../../../widgets/nh_empty_state.dart';
import '../../person/person_screen.dart';
import '../conversation_screen.dart';

class _ChatPreview {
  final String name;
  final String initials;
  final String lastMessage;
  final String time;
  final int unread;
  final Color avatarColor;

  const _ChatPreview({
    required this.name,
    required this.initials,
    required this.lastMessage,
    required this.time,
    required this.unread,
    required this.avatarColor,
  });
}

final _mockChats = [
  const _ChatPreview(
    name: 'Priya Sharma',
    initials: 'PS',
    lastMessage: 'Hi! I can help with the calculus sessions.',
    time: '2m',
    unread: 2,
    avatarColor: NeedHubTokens.forest,
  ),
  const _ChatPreview(
    name: 'Rohan Mehta',
    initials: 'RM',
    lastMessage: 'Sounds good, can you share a portfolio?',
    time: '1h',
    unread: 0,
    avatarColor: NeedHubTokens.ochre,
  ),
  const _ChatPreview(
    name: 'Dev Pillai',
    initials: 'DP',
    lastMessage: "I'm available this Sunday.",
    time: '3h',
    unread: 1,
    avatarColor: NeedHubTokens.clay,
  ),
  const _ChatPreview(
    name: 'Sneha Rao',
    initials: 'SR',
    lastMessage: "We can start next week if you're free.",
    time: '1d',
    unread: 0,
    avatarColor: NeedHubTokens.forest,
  ),
  const _ChatPreview(
    name: 'Ananya Iyer',
    initials: 'AI',
    lastMessage: 'Library opens at 10am on Saturday.',
    time: '2d',
    unread: 0,
    avatarColor: NeedHubTokens.clay,
  ),
];

class ChatsTab extends ConsumerStatefulWidget {
  const ChatsTab({super.key});

  @override
  ConsumerState<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends ConsumerState<ChatsTab> {
  final List<_ChatPreview> _acceptedChats = [];
  bool _loading = true;
  Timer? _poller;

  List<FriendRequest> get _pendingRequests =>
      mockIncomingRequests.where((r) => !r.declined && !r.accepted).toList();

  Future<void> _refreshChats() async {
    try {
      final api = ref.read(messagingApiProvider);
      final rows = await api.chats();
      chatsListNotifier.value = rows;
      if (mounted) setState(() {});
    } catch (_) {/* keep last-known list */}
  }

  Future<void> _handleAcceptReal(FriendRequestDto req) async {
    final api = ref.read(friendsApiProvider);
    try {
      await acceptFriendRequest(req.id, api);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConversationScreen(
            name: req.otherDisplayName ?? 'Friend',
            initials: _initialsFor(req.otherDisplayName ?? '?'),
            avatarColor: NeedHubTokens.forest,
            userId: req.fromUserId,
          ),
        ),
      );
      _refreshChats();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to accept: $e')));
      }
    }
  }

  Future<void> _handleDeclineReal(FriendRequestDto req) async {
    final api = ref.read(friendsApiProvider);
    try {
      await declineFriendRequest(req.id, api);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to decline: $e')));
      }
    }
  }

  static String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    chatsListNotifier.addListener(_bump);
    Future.microtask(() async {
      await _refreshChats();
      if (mounted) setState(() => _loading = false);
    });
    // Refresh chat list every 15s while tab is mounted.
    _poller = Timer.periodic(const Duration(seconds: 15), (_) => _refreshChats());
  }

  @override
  void dispose() {
    _poller?.cancel();
    chatsListNotifier.removeListener(_bump);
    super.dispose();
  }

  void _bump() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final realChats = chatsListNotifier.value;
    // Show real chats when we have them; fall back to mocks only if the
    // real list is empty AND friend-accept animations added local previews.
    final allChats = realChats.isNotEmpty
        ? const <_ChatPreview>[]
        : [..._acceptedChats, ..._mockChats];

    return Scaffold(
      backgroundColor: t.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Text(
                    'Chats',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: t.ink,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const _SearchUserSheet(),
                    ),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: t.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: t.rail, width: 1.5),
                      ),
                      child: Icon(Icons.person_search_rounded, size: 18, color: t.muted2),
                    ),
                  ),
                ],
              ),
            ),

            // List
            Expanded(
              child: _loading
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
                      children: const [
                        NhChatRowSkeleton(),
                        Divider(height: 1, indent: 76),
                        NhChatRowSkeleton(),
                        Divider(height: 1, indent: 76),
                        NhChatRowSkeleton(),
                        Divider(height: 1, indent: 76),
                        NhChatRowSkeleton(),
                      ],
                    )
                  : allChats.isEmpty && _pendingRequests.isEmpty
                      ? const Center(
                          child: NhEmptyState(
                            icon: Icons.chat_bubble_outline_rounded,
                            title: 'No conversations yet',
                            subtitle:
                                'Accept a friend request or connect with someone to start chatting',
                          ),
                        )
                      : ListView(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
                children: [
                  // Friend requests section — real ones (hydrated from API) first
                  ValueListenableBuilder<List<FriendRequestDto>>(
                    valueListenable: friendRequestsInboxNotifier,
                    builder: (context, realRequests, _) {
                      final hasReal = realRequests.isNotEmpty;
                      final hasMock = _pendingRequests.isNotEmpty;
                      if (!hasReal && !hasMock) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                            child: Text(
                              'FRIEND REQUESTS',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.7,
                                color: t.muted2,
                              ),
                            ),
                          ),
                          ...realRequests.map((req) => _RealFriendRequestCard(
                                request: req,
                                t: t,
                                onAccept: () => _handleAcceptReal(req),
                                onDecline: () => _handleDeclineReal(req),
                              )),
                          ..._pendingRequests.map((req) => _FriendRequestCard(
                                request: req,
                                t: t,
                                onAccept: () {
                                  setState(() {
                                    req.accepted = true;
                                    _acceptedChats.insert(
                                      0,
                                      _ChatPreview(
                                        name: req.fromName,
                                        initials: req.fromInitials,
                                        lastMessage: 'Friend request accepted',
                                        time: 'now',
                                        unread: 0,
                                        avatarColor: req.fromColor,
                                      ),
                                    );
                                  });
                                },
                                onDecline: () {
                                  setState(() {
                                    req.declined = true;
                                  });
                                },
                              )),
                        ],
                      );
                    },
                  ),

                  // MESSAGES header (shown when there are chats to list)
                  if (realChats.isNotEmpty || allChats.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Text(
                        'MESSAGES',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                          color: t.muted2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],

                  // Real chats from the API (preferred)
                  ...realChats.asMap().entries.map((e) {
                    final i = e.key;
                    final chat = e.value;
                    return Column(
                      children: [
                        _RealChatRow(
                          chat: chat,
                          t: t,
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ConversationScreen(
                                  name: chat.otherDisplayName,
                                  initials: _initialsFor(chat.otherDisplayName),
                                  avatarColor: NeedHubTokens.forest,
                                  avatarUrl: chat.otherAvatarUrl,
                                  userId: chat.otherUserId,
                                  threadId: chat.threadId,
                                ),
                              ),
                            );
                            _refreshChats();
                          },
                        ),
                        if (i < realChats.length - 1)
                          Divider(color: t.rail, height: 1, indent: 76),
                      ],
                    );
                  }),

                  // Mock fallback chats (only when no real chats exist)
                  ...allChats.asMap().entries.map((e) {
                    final i = e.key;
                    final chat = e.value;
                    return Column(
                      children: [
                        _ChatRow(
                          chat: chat,
                          t: t,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ConversationScreen(
                                name: chat.name,
                                initials: chat.initials,
                                avatarColor: chat.avatarColor,
                              ),
                            ),
                          ),
                        ),
                        if (i < allChats.length - 1)
                          Divider(color: t.rail, height: 1, indent: 76),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _FriendRequestCard extends StatelessWidget {
  final FriendRequest request;
  final NeedHubTokens t;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _FriendRequestCard({
    required this.request,
    required this.t,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.rail, width: 1),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: request.fromColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                request.fromInitials,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: request.fromColor,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.fromName,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'wants to connect',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 12,
                      color: t.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Accept button
            GestureDetector(
              onTap: onAccept,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: NeedHubTokens.forest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Accept',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Decline button
            GestureDetector(
              onTap: onDecline,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.rail, width: 1.5),
                ),
                child: Text(
                  'Decline',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.muted2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Real friend request card (hydrated from API) ─────────────────────────────

class _RealFriendRequestCard extends StatelessWidget {
  final FriendRequestDto request;
  final NeedHubTokens t;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _RealFriendRequestCard({
    required this.request,
    required this.t,
    required this.onAccept,
    required this.onDecline,
  });

  String get _initials {
    final name = request.otherDisplayName ?? '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.rail, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: NeedHubTokens.forest.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: request.otherAvatarUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        request.otherAvatarUrl!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Text(
                          _initials,
                          style: GoogleFonts.bricolageGrotesque(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: NeedHubTokens.forest,
                          ),
                        ),
                      ),
                    )
                  : Text(
                      _initials,
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: NeedHubTokens.forest,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.otherDisplayName ?? 'Someone',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'wants to connect',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 12,
                      color: t.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onAccept,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: NeedHubTokens.forest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Accept',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    )),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onDecline,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.rail, width: 1.5),
                ),
                child: Text('Decline',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: t.muted2,
                    )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Username search sheet ─────────────────────────────────────────────────────

const _mockUsers = [
  (name: 'Aarav Kumar', username: 'aaravk', initials: 'AK', color: NeedHubTokens.forest),
  (name: 'Meera Kulkarni', username: 'meerak', initials: 'MK', color: NeedHubTokens.clay),
  (name: 'Rohan Verma', username: 'rohanv', initials: 'RV', color: NeedHubTokens.ochre),
  (name: 'Priya Nair', username: 'priyan', initials: 'PN', color: NeedHubTokens.forest),
  (name: 'Karthik Reddy', username: 'karthikr', initials: 'KR', color: NeedHubTokens.clay),
  (name: 'Sneha Rao', username: 'snehar', initials: 'SR', color: NeedHubTokens.ochre),
];

class _SearchUserSheet extends ConsumerStatefulWidget {
  const _SearchUserSheet();

  @override
  ConsumerState<_SearchUserSheet> createState() => _SearchUserSheetState();
}

class _RemoteUser {
  final String id;
  final String name;
  final String? username;
  final String? avatarUrl;
  _RemoteUser({required this.id, required this.name, this.username, this.avatarUrl});
}

class _SearchUserSheetState extends ConsumerState<_SearchUserSheet> {
  final _controller = TextEditingController();
  final Set<String> _sentRequests = {};
  String _query = '';
  List<_RemoteUser> _remoteResults = const [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (v.trim().isEmpty) {
        setState(() => _remoteResults = const []);
        return;
      }
      setState(() => _searching = true);
      try {
        final api = ref.read(apiClientProvider);
        final rows = await api.getList('/profile/search', query: {'q': v.trim()});
        setState(() {
          _remoteResults = rows.map((j) {
            final profile = j['profile'] as Map<String, dynamic>?;
            return _RemoteUser(
              id: j['id'] as String,
              name: j['displayName'] as String? ?? '',
              username: j['username'] as String?,
              avatarUrl: profile?['avatarUrl'] as String?,
            );
          }).toList();
        });
      } catch (_) {
        setState(() => _remoteResults = const []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _sendReal(_RemoteUser u) async {
    setState(() => _sentRequests.add(u.id));
    outgoingRequestUserIdsNotifier.value = {
      ...outgoingRequestUserIdsNotifier.value,
      u.id,
    };
    try {
      final api = ref.read(friendsApiProvider);
      await api.sendRequest(u.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Friend request sent to ${u.name}')),
        );
      }
    } catch (e) {
      setState(() => _sentRequests.remove(u.id));
      outgoingRequestUserIdsNotifier.value = {...outgoingRequestUserIdsNotifier.value}
        ..remove(u.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final results = _query.isEmpty
        ? <({String name, String username, String initials, Color color})>[]
        : _mockUsers
            .where((u) =>
                u.username.contains(_query.toLowerCase()) ||
                u.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Padding(
      // Slide the sheet up by the keyboard height so it's never obscured.
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Container(
        margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 60),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle + header (fixed, never scrolls)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: t.rail, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Find by username',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Search field
                  Container(
                    decoration: BoxDecoration(
                      color: t.paper,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: t.rail, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('@',
                              style: GoogleFonts.hankenGrotesk(
                                  fontSize: 15,
                                  color: NeedHubTokens.clay,
                                  fontWeight: FontWeight.w700)),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            autofocus: true,
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 15, color: t.ink),
                            decoration: InputDecoration(
                              hintText: 'username',
                              hintStyle: GoogleFonts.hankenGrotesk(
                                  fontSize: 15, color: t.muted),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onChanged: _onQueryChanged,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),

            // Results — scrollable, shrinks when keyboard is open
            if (_query.trim().isEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad + 20),
                child: Text(
                  'Type a name to search',
                  style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
                ),
              )
            else if (_searching)
              Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad + 20),
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_remoteResults.isEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad + 20),
                child: Text(
                  'No users found',
                  style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad + 20),
                  itemCount: _remoteResults.length,
                  itemBuilder: (_, i) {
                    final u = _remoteResults[i];
                    final sent = _sentRequests.contains(u.id) ||
                        outgoingRequestUserIdsNotifier.value.contains(u.id);
                    final alreadyFriend =
                        friendUserIdsNotifier.value.contains(u.id);
                    final parts = u.name.trim().split(RegExp(r'\s+'));
                    final initials = parts.isEmpty || parts[0].isEmpty
                        ? '?'
                        : (parts.length == 1
                            ? parts[0]
                                .substring(0, parts[0].length.clamp(1, 2))
                                .toUpperCase()
                            : '${parts[0][0]}${parts[1][0]}'.toUpperCase());
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: t.paper,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: t.rail, width: 1),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: NeedHubTokens.forest.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: u.avatarUrl != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(u.avatarUrl!,
                                          width: 44, height: 44, fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Text(
                                                initials,
                                                style: GoogleFonts.bricolageGrotesque(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w700,
                                                    color: NeedHubTokens.forest),
                                              )),
                                    )
                                  : Text(
                                      initials,
                                      style: GoogleFonts.bricolageGrotesque(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: NeedHubTokens.forest),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '@${u.username ?? u.name}',
                                    style: GoogleFonts.hankenGrotesk(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: t.ink),
                                  ),
                                  if (u.username != null)
                                    Text(
                                      u.name,
                                      style: GoogleFonts.hankenGrotesk(
                                          fontSize: 12, color: t.muted),
                                    ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: alreadyFriend
                                  ? () {
                                      Navigator.pop(context);
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ConversationScreen(
                                            name: u.name,
                                            initials: initials,
                                            avatarColor: NeedHubTokens.forest,
                                            userId: u.id,
                                          ),
                                        ),
                                      );
                                    }
                                  : sent
                                      ? null
                                      : () => _sendReal(u),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: alreadyFriend
                                      ? NeedHubTokens.forest
                                      : (sent ? t.chip : NeedHubTokens.clay),
                                  borderRadius: BorderRadius.circular(10),
                                  border: sent
                                      ? Border.all(color: t.rail, width: 1)
                                      : null,
                                ),
                                child: Text(
                                  alreadyFriend
                                      ? 'Message'
                                      : (sent ? 'Pending' : 'Add'),
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: sent ? t.muted : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _RealChatRow extends StatelessWidget {
  final ChatSummary chat;
  final NeedHubTokens t;
  final VoidCallback onTap;

  const _RealChatRow({
    required this.chat, required this.t, required this.onTap,
  });

  String get _initials {
    final parts = chat.otherDisplayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final preview = chat.lastMessageBody != null && chat.lastMessageBody!.isNotEmpty
        ? chat.lastMessageBody!
        : (chat.lastMessageImageUrl != null ? '📷 Image' : 'No messages yet');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                PersonScreen.route(
                  name: chat.otherDisplayName,
                  initials: _initials,
                  avatarColor: NeedHubTokens.forest,
                  avatarUrl: chat.otherAvatarUrl,
                  userId: chat.otherUserId,
                ),
              ),
              child: NhAvatar(
                avatarUrl: chat.otherAvatarUrl,
                initials: _initials,
                size: 44,
                borderRadius: 14,
                backgroundColor: NeedHubTokens.forest.withValues(alpha: 0.15),
                textColor: NeedHubTokens.forest,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(chat.otherDisplayName,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 14,
                                fontWeight: chat.unreadCount > 0
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                                color: t.ink)),
                      ),
                      const SizedBox(width: 8),
                      Text(chat.timeLabel,
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 11, color: t.muted)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 13,
                          color: chat.unreadCount > 0 ? t.ink : t.muted2,
                          height: 1.35)),
                ],
              ),
            ),
            if (chat.unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                constraints:
                    const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: NeedHubTokens.clay,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  final _ChatPreview chat;
  final NeedHubTokens t;
  final VoidCallback onTap;

  const _ChatRow({required this.chat, required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            // Avatar → tap to open profile
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                PersonScreen.route(
                  name: chat.name,
                  initials: chat.initials,
                  avatarColor: chat.avatarColor,
                ),
              ),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: chat.avatarColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  chat.initials,
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: chat.avatarColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name + last message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.name,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 15,
                      fontWeight: chat.unread > 0 ? FontWeight.w700 : FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    chat.lastMessage,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 13,
                      color: chat.unread > 0 ? t.ink : t.muted,
                      fontWeight: chat.unread > 0 ? FontWeight.w500 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Time + unread badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  chat.time,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 12,
                    color: chat.unread > 0 ? NeedHubTokens.clay : t.muted,
                    fontWeight: chat.unread > 0 ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (chat.unread > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: NeedHubTokens.clay,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${chat.unread}',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
