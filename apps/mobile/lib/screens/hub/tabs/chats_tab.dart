import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../l10n/app_strings.dart';
import '../../../models/friend_request.dart';
import '../../../models/user_state.dart';
import '../../../providers/language_provider.dart';
import '../../../services/api_client.dart';
import '../../../services/chitchat_api.dart';
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

final _mockChats = <_ChatPreview>[];

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
      if (rows.isNotEmpty) {
        chatsListNotifier.value = rows;
      }
      if (mounted) setState(() {});
    } catch (_) {/* keep last-known list */}
  }

  Future<void> _handleAcceptReal(FriendRequestDto req) async {
    final api = ref.read(friendsApiProvider);
    try {
      await acceptFriendRequest(req.id, api);
    } catch (_) {
      friendRequestsInboxNotifier.value = friendRequestsInboxNotifier.value
          .where((r) => r.id != req.id)
          .toList();
    }
    if (mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConversationScreen(
            name: req.otherDisplayName ?? S.current.friend,
            initials: _initialsFor(req.otherDisplayName ?? '?'),
            avatarColor: NeedHubTokens.forest,
            userId: req.fromUserId,
          ),
        ),
      );
      _refreshChats();
    }
  }

  Future<void> _handleDeclineReal(FriendRequestDto req) async {
    final api = ref.read(friendsApiProvider);
    try {
      await declineFriendRequest(req.id, api);
    } catch (_) {}
    friendRequestsInboxNotifier.value = friendRequestsInboxNotifier.value
        .where((r) => r.id != req.id)
        .toList();
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
    uiLanguageNotifier.addListener(_bump);
    chatsListNotifier.addListener(_bump);
    Future.microtask(() async {
      await Future.any([
        _refreshChats(),
        Future.delayed(const Duration(seconds: 4)),
      ]);
      if (mounted) setState(() => _loading = false);
    });
    // Refresh chat list every 8s while tab is mounted (faster than before).
    _poller = Timer.periodic(const Duration(seconds: 8), (_) => _refreshChats());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh whenever tab is re-focused.
    Future.microtask(_refreshChats);
  }

  @override
  void dispose() {
    _poller?.cancel();
    uiLanguageNotifier.removeListener(_bump);
    chatsListNotifier.removeListener(_bump);
    super.dispose();
  }

  void _bump() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;
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
                    s.chats,
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

            // ChitChat availability banner
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: _ChitChatChatsBanner(t: t),
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
                  : realChats.isEmpty && allChats.isEmpty && _pendingRequests.isEmpty && friendRequestsInboxNotifier.value.isEmpty
                      ? RefreshIndicator(
                          onRefresh: _refreshChats,
                          color: NeedHubTokens.clay,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.6,
                                child: Center(
                                  child: NhEmptyState(
                                    icon: Icons.chat_bubble_outline_rounded,
                                    title: s.noChatsYet,
                                    subtitle: s.noChatsSubtitle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                onRefresh: _refreshChats,
                color: NeedHubTokens.clay,
                child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                              s.friendRequests,
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
                                        lastMessage: s.friendRequestAccepted,
                                        time: s.now,
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
                        s.messagesHeader,
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

                  // "UP FOR A CHAT RIGHT NOW" section (shows when marked available)
                  ValueListenableBuilder<bool>(
                    valueListenable: chitChatAvailableNotifier,
                    builder: (context, available, _) {
                      if (!available) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Text(
                                s.upForAChatRightNow,
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.7,
                                  color: t.muted2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 68,
                              child: ValueListenableBuilder<List<ChitchatPerson>>(
                                valueListenable: chitchatRosterNotifier,
                                builder: (context, roster, _) {
                                  const mockPeople = <({String initials, String name, String area, Color color})>[];
                                  return ListView(
                                    scrollDirection: Axis.horizontal,
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 20),
                                    children: [
                                      ...roster.map(
                                        (p) => _ChatsTabPersonCuboidalTile(
                                            person: p, t: t),
                                      ),
                                      if (roster.isEmpty)
                                        ...mockPeople.map((p) =>
                                            _ChatsTabMockPersonCuboidalTile(
                                                person: p, t: t)),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
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
    final s = S.current;
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
                    s.wantsToConnect,
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
                  s.accept,
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
                  s.decline,
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
    final s = S.current;
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
                    request.otherDisplayName ?? s.someone,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.wantsToConnect,
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
                child: Text(s.accept,
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
                child: Text(s.decline,
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

const _mockUsers = <({String name, String username, String initials, Color color})>[];

class _SearchUserSheet extends ConsumerStatefulWidget {
  const _SearchUserSheet();

  @override
  ConsumerState<_SearchUserSheet> createState() => _SearchUserSheetState();
}

class _RemoteUser {
  final String id;
  final String name;
  final String username;
  final String? avatarUrl;
  _RemoteUser({
    required this.id,
    required this.name,
    required this.username,
    this.avatarUrl,
  });
}

class _SearchUserSheetState extends ConsumerState<_SearchUserSheet> {
  final _controller = TextEditingController();
  final Set<String> _sentRequests = {};
  String _query = '';
  List<_RemoteUser> _combinedResults = const [];
  bool _searching = false;
  String? _error;
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    final q = v.trim().toLowerCase();
    setState(() => _query = v);
    _debounce?.cancel();

    if (q.isEmpty) {
      setState(() {
        _searching = false;
        _combinedResults = const [];
      });
      return;
    }

    final localMatches = _mockUsers.where((u) {
      return u.name.toLowerCase().contains(q) ||
          u.username.toLowerCase().contains(q);
    }).map((u) {
      return _RemoteUser(
        id: 'mock_${u.username}',
        name: u.name,
        username: u.username,
        avatarUrl: null,
      );
    }).toList();

    setState(() {
      _combinedResults = localMatches;
      _searching = true;
      _error = null;
    });

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final api = ref.read(apiClientProvider);
        final rows =
            await api.getList('/profile/search', query: {'q': q});
        final remoteMatches = rows.map((j) {
          final profile = j['profile'] as Map<String, dynamic>?;
          final name = j['displayName'] as String? ?? '';
          final username = j['username'] as String? ??
              name.toLowerCase().replaceAll(' ', '');
          return _RemoteUser(
            id: j['id'] as String,
            name: name,
            username: username,
            avatarUrl: profile?['avatarUrl'] as String?,
          );
        }).toList();

        if (mounted) {
          final existingIds = remoteMatches.map((r) => r.id).toSet();
          final combined = [
            ...remoteMatches,
            ...localMatches.where((l) => !existingIds.contains(l.id)),
          ];
          setState(() {
            _combinedResults = combined;
            _error = null;
          });
        }
      } catch (e) {
        debugPrint('[SearchUserSheet] Search API error: $e');
        if (mounted) {
          setState(() {
            _combinedResults = localMatches;
            _error = S.current.couldNotReachServer;
          });
        }
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
      if (!u.id.startsWith('mock_')) {
        final api = ref.read(friendsApiProvider);
        await api.sendRequest(u.id);
      }
    } catch (_) {/* Keep optimistic sent state */}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.current.friendRequestSentTo(u.name))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        // Sheet takes up most of the screen so results always have room
        height: MediaQuery.of(context).size.height * 0.85,
        margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 40),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle + header
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
                    S.current.findByUsername,
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
                              hintText: S.current.nameOrUsername,
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

            // Results
            if (_error != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_off_rounded, size: 40, color: Colors.red.shade300),
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_query.trim().isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_search_rounded, size: 48, color: t.muted.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text(
                        S.current.searchByNameOrUsername,
                        style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else if (_searching && _combinedResults.isEmpty)
              const Expanded(
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_combinedResults.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off_rounded, size: 48, color: t.muted.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text(
                        S.current.noUsersFound,
                        style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.w700, color: t.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        S.current.tryDifferentName,
                        style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, bottomPad + 20),
                  itemCount: _combinedResults.length,
                  itemBuilder: (_, i) {
                    final u = _combinedResults[i];
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
                            // Tap avatar or name to view profile
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PersonScreen(
                                        name: u.name,
                                        initials: initials,
                                        avatarColor: NeedHubTokens.forest,
                                        avatarUrl: u.avatarUrl,
                                        userId: u.id,
                                      ),
                                    ),
                                  );
                                },
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: NeedHubTokens.forest
                                            .withValues(alpha: 0.15),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      alignment: Alignment.center,
                                      child: u.avatarUrl != null
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Image.network(
                                                  u.avatarUrl!,
                                                  width: 44,
                                                  height: 44,
                                                  fit: BoxFit.cover,
                                                  errorBuilder:
                                                      (_, __, ___) => Text(
                                                            initials,
                                                            style: GoogleFonts
                                                                .bricolageGrotesque(
                                                                    fontSize:
                                                                        15,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color:
                                                                        NeedHubTokens
                                                                            .forest),
                                                          )),
                                            )
                                          : Text(
                                              initials,
                                              style: GoogleFonts
                                                  .bricolageGrotesque(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: NeedHubTokens
                                                          .forest),
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            u.name,
                                            style: GoogleFonts.hankenGrotesk(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: t.ink),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '@${u.username}',
                                            style: GoogleFonts.hankenGrotesk(
                                                fontSize: 12,
                                                color: t.muted),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Action buttons: Message & Add
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context);
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ConversationScreen(
                                          name: u.name,
                                          initials: initials,
                                          avatarColor: NeedHubTokens.forest,
                                          avatarUrl: u.avatarUrl,
                                          userId: u.id,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: NeedHubTokens.forest,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                            Icons.chat_bubble_outline_rounded,
                                            size: 13,
                                            color: Colors.white),
                                        const SizedBox(width: 4),
                                        Text(
                                          S.current.messageBtn,
                                          style: GoogleFonts.hankenGrotesk(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (!alreadyFriend) ...[
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: sent ? null : () => _sendReal(u),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: sent ? t.chip : NeedHubTokens.clay,
                                        borderRadius: BorderRadius.circular(10),
                                        border: sent
                                            ? Border.all(
                                                color: t.rail, width: 1)
                                            : null,
                                      ),
                                      child: Text(
                                        sent ? S.current.pending : S.current.add,
                                        style: GoogleFonts.hankenGrotesk(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color:
                                              sent ? t.muted : Colors.white,
                                        ),
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
        : (chat.lastMessageImageUrl != null ? S.current.imageMsg : S.current.noMessagesYet);
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

class _ChitChatChatsBanner extends ConsumerStatefulWidget {
  final NeedHubTokens t;

  const _ChitChatChatsBanner({required this.t});

  @override
  ConsumerState<_ChitChatChatsBanner> createState() => _ChitChatChatsBannerState();
}

class _ChitChatChatsBannerState extends ConsumerState<_ChitChatChatsBanner> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    chitChatAvailableNotifier.addListener(_bump);
  }

  @override
  void dispose() {
    chitChatAvailableNotifier.removeListener(_bump);
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
        try {
          await api.clearAvailability();
        } catch (_) {}
        chitChatAvailableNotifier.value = false;
        chitchatAvailableUntilNotifier.value = null;
      } else {
        DateTime? until;
        try {
          final status = await api.setAvailability(4);
          until = status.availableUntil;
        } catch (_) {
          until = DateTime.now().add(const Duration(hours: 4));
        }
        chitChatAvailableNotifier.value = true;
        chitchatAvailableUntilNotifier.value = until;
      }
      try {
        chitchatRosterNotifier.value = await api.availablePeople();
      } catch (_) {}
    } catch (_) {
      chitChatAvailableNotifier.value = !currentlyAvailable;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final s = S.current;
    final available = chitChatAvailableNotifier.value;

    return GestureDetector(
      onTap: _busy ? null : () => _toggleAvailability(available),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
              color: available ? Colors.white : NeedHubTokens.clay,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                available
                    ? s.youreAvailableForChitChat24h
                    : s.markAvailableForChitchat,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: available ? Colors.white : t.ink,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: available ? Colors.white : t.muted2,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatsTabMockPersonCuboidalTile extends StatelessWidget {
  final ({
    String initials,
    String name,
    String area,
    Color color,
  }) person;
  final NeedHubTokens t;

  const _ChatsTabMockPersonCuboidalTile(
      {required this.person, required this.t});

  @override
  Widget build(BuildContext context) {
    final p = person;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ConversationScreen(
                name: p.name,
                initials: p.initials,
                avatarColor: p.color,
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
                  color: p.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Text(
                  p.initials,
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: p.color,
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
                      p.name,
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
                      p.area,
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

class _ChatsTabPersonCuboidalTile extends ConsumerWidget {
  final ChitchatPerson person;
  final NeedHubTokens t;

  const _ChatsTabPersonCuboidalTile({required this.person, required this.t});

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
                          : S.current.nearby,
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
