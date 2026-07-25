import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/user_state.dart';
import '../../services/api_client.dart';
import '../../services/messaging_api.dart';
import '../../services/profiles_api.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/nh_avatar.dart';
import '../../widgets/nh_empty_state.dart';
import '../../widgets/nh_full_screen_image_viewer.dart';
import '../../widgets/nh_report_sheet.dart';
import '../person/person_screen.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  final String name;
  final String initials;
  final Color avatarColor;
  final String? avatarUrl;
  /// The other user's ID. When provided, messages are sent to the real API.
  final String? userId;
  /// Existing DM thread id. When null, will be resolved lazily from GET /chats.
  final String? threadId;

  const ConversationScreen({
    super.key,
    required this.name,
    required this.initials,
    required this.avatarColor,
    this.avatarUrl,
    this.userId,
    this.threadId,
  });

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  bool _isTyping = false;
  bool _sending = false;
  int? _reactingIndex;

  bool get _isFriend => friendsNotifier.value.contains(widget.name);
  bool get _isBlocked => blockedNotifier.value.contains(widget.name);
  bool get _hasRealApi => widget.userId != null;

  void _bump() {
    if (mounted) setState(() {});
  }

  late List<_Message> _messages;
  String? _resolvedThreadId;
  String? _lastRealMessageId;
  bool _initialLoaded = false;
  Timer? _tailPoller;

  @override
  void initState() {
    super.initState();
    friendsNotifier.addListener(_bump);
    blockedNotifier.addListener(_bump);
    _resolvedThreadId = widget.threadId;

    if (_hasRealApi) {
      // Start empty when using the real API; hydrate from the server.
      _messages = [];
      Future.microtask(_hydrateReal);
    } else {
      // Mock conversation demo data for legacy screens.
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      _messages = [
        _Message(text: 'Hi! I saw your need and I think I can help.', isMe: false,
            time: DateTime(yesterday.year, yesterday.month, yesterday.day, 10, 23), isRead: true),
        _Message(text: "That's great! When are you available?", isMe: true,
            time: DateTime(yesterday.year, yesterday.month, yesterday.day, 10, 25), isRead: true),
        _Message(text: "I'm free on weekends. Saturday morning works best.", isMe: false,
            time: DateTime(yesterday.year, yesterday.month, yesterday.day, 10, 26), isRead: true),
        _Message(text: "Perfect, let's lock in Saturday 10am.", isMe: true,
            time: DateTime(yesterday.year, yesterday.month, yesterday.day, 10, 28), isRead: true),
        _Message(text: "See you then! I'll bring my portfolio.", isMe: false,
            time: DateTime(now.year, now.month, now.day, 9, 15)),
      ];
    }
  }

  /// Load history + start the 2s tail poller.
  Future<void> _hydrateReal() async {
    if (widget.userId == null) return;
    final api = ref.read(messagingApiProvider);

    // Resolve threadId if we don't have it.
    if (_resolvedThreadId == null) {
      try {
        final chats = await api.chats();
        final match = chats
            .where((c) => c.otherUserId == widget.userId)
            .toList();
        if (match.isNotEmpty) _resolvedThreadId = match.first.threadId;
      } catch (_) {/* first-message send will create the thread */}
    }

    if (_resolvedThreadId != null) {
      try {
        final msgs = await api.messages(_resolvedThreadId!, limit: 50);
        if (!mounted) return;
        final myId = myProfileNotifier.value?.id;
        setState(() {
          _messages = msgs
              .map((m) => _Message(
                    text: m.body.isEmpty ? null : m.body,
                    imageUrl: m.imageUrl,
                    isMe: myId != null && m.senderId == myId,
                    time: m.createdAt,
                    isRead: m.readAt != null,
                    remoteId: m.id,
                  ))
              .toList();
          if (msgs.isNotEmpty) _lastRealMessageId = msgs.last.id;
          _initialLoaded = true;
        });
        _scrollToBottom();
      } catch (_) {/* keep empty */}
    } else {
      if (mounted) setState(() => _initialLoaded = true);
    }

    // Tail-poll every 2s while foregrounded.
    _tailPoller?.cancel();
    _tailPoller = Timer.periodic(const Duration(seconds: 2), (_) => _tail());
  }

  Future<void> _tail() async {
    if (_resolvedThreadId == null || widget.userId == null) return;
    final api = ref.read(messagingApiProvider);
    try {
      final newer = await api.messages(
        _resolvedThreadId!,
        limit: 30,
        since: _lastRealMessageId,
      );
      if (newer.isEmpty || !mounted) return;
      final myId = myProfileNotifier.value?.id;
      // Deduplicate: skip anything already in the list by remoteId.
      final existingIds = _messages
          .where((m) => m.remoteId != null)
          .map((m) => m.remoteId!)
          .toSet();
      final incoming = newer.where((m) => !existingIds.contains(m.id)).toList();
      if (incoming.isEmpty) return;
      setState(() {
        for (final m in incoming) {
          _messages.add(_Message(
            text: m.body.isEmpty ? null : m.body,
            imageUrl: m.imageUrl,
            isMe: myId != null && m.senderId == myId,
            time: m.createdAt,
            isRead: m.readAt != null,
            remoteId: m.id,
          ));
        }
        _lastRealMessageId = incoming.last.id;
      });
      _scrollToBottom();
    } catch (_) {/* keep last state */}
  }

  @override
  void dispose() {
    _tailPoller?.cancel();
    friendsNotifier.removeListener(_bump);
    blockedNotifier.removeListener(_bump);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendToApi({String? text, String? imagePath}) async {
    if (widget.userId == null) return;
    final api = ref.read(apiClientProvider);
    Map<String, dynamic> res;
    if (imagePath != null) {
      final form = FormData.fromMap({
        if (text != null && text.isNotEmpty) 'body': text,
        'image': await MultipartFile.fromFile(imagePath,
            filename: imagePath.split('/').last),
      });
      res = await api.postForm('/chats/dm/${widget.userId}/messages', form);
    } else if (text != null && text.isNotEmpty) {
      res = await api.post(
          '/chats/dm/${widget.userId}/messages', {'body': text});
    } else {
      return;
    }
    // Remember thread + last-message id so the tail poller skips our own
    // just-sent message and hydrates without duplicates.
    final threadId = res['threadId'] as String? ??
        (res['thread'] as Map<String, dynamic>?)?['id'] as String?;
    final msgId = res['id'] as String?;
    if (threadId != null) _resolvedThreadId = threadId;
    if (msgId != null) _lastRealMessageId = msgId;
    if (msgId != null && mounted) {
      // Stamp the just-appended local bubble with the server id so tail
      // dedupe recognises it.
      setState(() {
        if (_messages.isNotEmpty) {
          _messages[_messages.length - 1] =
              _messages.last.copyWith(remoteId: msgId);
        }
      });
    }
    // Kick off the poller if this send happened before hydration finished.
    _tailPoller ??=
        Timer.periodic(const Duration(seconds: 2), (_) => _tail());
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();
    final msg = _Message(text: text, isMe: true, time: DateTime.now());
    setState(() { _messages.add(msg); _isTyping = !_hasRealApi; });
    _scrollToBottom();

    if (_hasRealApi) {
      setState(() => _sending = true);
      try {
        await _sendToApi(text: text);
        if (mounted) setState(() { _messages.last = _messages.last.copyWith(isRead: true); });
      } catch (e) {
        if (mounted) {
          setState(() => _messages.removeLast());
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send failed: $e')));
        }
      } finally {
        if (mounted) setState(() => _sending = false);
      }
    } else {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() { _isTyping = false; _messages.last = _messages.last.copyWith(isRead: true); });
        _scrollToBottom();
      });
    }
  }

  Future<void> _showAttachmentMenu() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AttachmentSheet(
        onCamera: () async {
          Navigator.pop(context);
          final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
          if (file != null && mounted) _addImage(file.path);
        },
        onGallery: () async {
          Navigator.pop(context);
          final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
          if (file != null && mounted) _addImage(file.path);
        },
      ),
    );
  }

  Future<void> _addImage(String path) async {
    final msg = _Message(imagePath: path, isMe: true, time: DateTime.now());
    setState(() { _messages.add(msg); _isTyping = !_hasRealApi; });
    _scrollToBottom();

    if (_hasRealApi) {
      setState(() => _sending = true);
      try {
        await _sendToApi(imagePath: path);
        if (mounted) setState(() { _messages.last = _messages.last.copyWith(isRead: true); });
      } catch (e) {
        if (mounted) {
          setState(() => _messages.removeLast());
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image send failed: $e')));
        }
      } finally {
        if (mounted) setState(() => _sending = false);
      }
    } else {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isTyping = false);
      });
    }
  }

  void _addReaction(int idx, String emoji) {
    setState(() {
      final msg = _messages[idx];
      final reacts = List<String>.from(msg.reactions);
      if (reacts.contains(emoji)) {
        reacts.remove(emoji);
      } else {
        reacts.add(emoji);
      }
      _messages[idx] = msg.copyWith(reactions: reacts);
      _reactingIndex = null;
    });
  }

  List<dynamic> get _listItems {
    final items = <dynamic>[];
    DateTime? lastDate;
    for (int i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final d = DateTime(m.time.year, m.time.month, m.time.day);
      if (lastDate == null || d != lastDate) {
        items.add(_DateDividerData(d));
        lastDate = d;
      }
      items.add(_IndexedMessage(index: i, message: m));
    }
    if (_isTyping) items.add('typing');
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final items = _listItems;

    return GestureDetector(
      onTap: () => setState(() => _reactingIndex = null),
      child: Scaffold(
        backgroundColor: t.paper,
        appBar: AppBar(
          backgroundColor: t.paper,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: t.ink),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  PersonScreen.route(
                    name: widget.name,
                    initials: widget.initials,
                    avatarColor: widget.avatarColor,
                    avatarUrl: widget.avatarUrl,
                    subtitle: 'Active now',
                    userId: widget.userId,
                  ),
                ),
                child: Stack(
                  children: [
                    NhAvatar(
                      avatarUrl: widget.avatarUrl,
                      initials: widget.initials,
                      size: 38,
                      borderRadius: 12,
                      backgroundColor: widget.avatarColor.withValues(alpha: 0.15),
                      textColor: widget.avatarColor,
                      fontSize: 13,
                    ),
                  Positioned(
                    bottom: 1,
                    right: 1,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: NeedHubTokens.forest,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.paper, width: 2),
                      ),
                    ),
                  ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.name,
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                  Text(
                    'Online',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: NeedHubTokens.forest,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.videocam_outlined, color: t.muted2, size: 22),
              onPressed: () {},
            ),
            IconButton(
              icon: Icon(Icons.more_vert_rounded, color: t.muted2),
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _ChatMenuSheet(
                  personName: widget.name,
                  personUserId: widget.userId,
                  isFriend: _isFriend,
                  isBlocked: _isBlocked,
                  onToggleFriend: () {
                    if (_isFriend) {
                      removeFriend(widget.name);
                    } else {
                      addFriend(widget.name);
                    }
                  },
                  onDeleteForMe: () {
                    setState(() => _messages.clear());
                  },
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: NhEmptyState(
                        icon: Icons.waving_hand_rounded,
                        title: 'Say hello!',
                        subtitle: 'This is the beginning of your conversation with ${widget.name}',
                      ),
                    )
                  : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  if (item is _DateDividerData) {
                    return _DateDivider(date: item.date, t: t);
                  }
                  if (item == 'typing') {
                    return _TypingIndicator(
                        initials: widget.initials, color: widget.avatarColor, t: t);
                  }
                  if (item is _IndexedMessage) {
                    return GestureDetector(
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        setState(() => _reactingIndex = item.index);
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _Bubble(
                            msg: item.message,
                            t: t,
                            avatarColor: widget.avatarColor,
                            initials: widget.initials,
                            senderName: item.message.isMe ? 'You' : widget.name,
                          ),
                          if (_reactingIndex == item.index)
                            Positioned(
                              top: -44,
                              right: item.message.isMe ? 0 : null,
                              left: item.message.isMe ? null : 36,
                              child: _ReactionPicker(
                                onPick: (emoji) => _addReaction(item.index, emoji),
                                t: t,
                              ),
                            ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),

            // Input bar
            Container(
              padding: EdgeInsets.fromLTRB(12, 10, 12, bottomPad + 10),
              decoration: BoxDecoration(
                color: t.card,
                border: Border(top: BorderSide(color: t.rail, width: 1)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: _showAttachmentMenu,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: t.chip,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: t.rail, width: 1.5),
                      ),
                      child: Icon(Icons.add_rounded, color: t.muted2, size: 22),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      decoration: BoxDecoration(
                        color: t.paper,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: t.rail, width: 1.5),
                      ),
                      child: TextField(
                        controller: _controller,
                        maxLines: null,
                        style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
                        decoration: InputDecoration(
                          hintText: 'Message…',
                          hintStyle: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          filled: false,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: NeedHubTokens.clay,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.arrow_upward_rounded,
                          color: Colors.white, size: 20),
                    ),
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

// ── Data classes ──────────────────────────────────────────────────────────────

class _Message {
  final String? text;
  final String? imagePath;
  /// Remote image URL (from API). Preferred over imagePath when set.
  final String? imageUrl;
  final bool isMe;
  final DateTime time;
  final List<String> reactions;
  final bool isRead;
  /// Server message id — set for messages loaded from the API.
  final String? remoteId;

  _Message({
    this.text,
    this.imagePath,
    this.imageUrl,
    required this.isMe,
    required this.time,
    List<String>? reactions,
    this.isRead = false,
    this.remoteId,
  }) : reactions = reactions ?? [];

  _Message copyWith({
    String? text,
    String? imagePath,
    String? imageUrl,
    bool? isMe,
    DateTime? time,
    List<String>? reactions,
    bool? isRead,
    String? remoteId,
  }) {
    return _Message(
      text: text ?? this.text,
      imagePath: imagePath ?? this.imagePath,
      imageUrl: imageUrl ?? this.imageUrl,
      isMe: isMe ?? this.isMe,
      time: time ?? this.time,
      reactions: reactions ?? List.from(this.reactions),
      isRead: isRead ?? this.isRead,
      remoteId: remoteId ?? this.remoteId,
    );
  }

  String get timeLabel {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _DateDividerData {
  final DateTime date;
  const _DateDividerData(this.date);
}

class _IndexedMessage {
  final int index;
  final _Message message;
  const _IndexedMessage({required this.index, required this.message});
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _DateDivider extends StatelessWidget {
  final DateTime date;
  final NeedHubTokens t;
  const _DateDivider({required this.date, required this.t});

  String get _label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (date == today) return 'Today';
    if (date == yesterday) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: t.rail, height: 1)),
          const SizedBox(width: 10),
          Text(
            _label,
            style: GoogleFonts.hankenGrotesk(
                fontSize: 11.5, color: t.muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: t.rail, height: 1)),
        ],
      ),
    );
  }
}

class _ReactionPicker extends StatelessWidget {
  final ValueChanged<String> onPick;
  final NeedHubTokens t;
  const _ReactionPicker({required this.onPick, required this.t});

  static const _emojis = ['❤️', '👍', '😂', '😮', '😢', '🙏'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 14,
              offset: const Offset(0, 4))
        ],
        border: Border.all(color: t.rail, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _emojis
            .map((e) => GestureDetector(
                  onTap: () => onPick(e),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(e, style: const TextStyle(fontSize: 22)),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _AttachmentSheet extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  const _AttachmentSheet({required this.onCamera, required this.onGallery});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: t.rail, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachOption(
                icon: Icons.camera_alt_rounded,
                label: 'Camera',
                color: NeedHubTokens.clay,
                onTap: onCamera,
                t: t,
              ),
              _AttachOption(
                icon: Icons.photo_library_rounded,
                label: 'Gallery',
                color: NeedHubTokens.forest,
                onTap: onGallery,
                t: t,
              ),
              _AttachOption(
                icon: Icons.insert_drive_file_rounded,
                label: 'File',
                color: NeedHubTokens.ochre,
                onTap: () => Navigator.pop(context),
                t: t,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final NeedHubTokens t;
  const _AttachOption(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap,
      required this.t});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.22), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.hankenGrotesk(
                fontSize: 12, fontWeight: FontWeight.w600, color: t.muted2),
          ),
        ],
      ),
    );
  }
}

String? _resolveUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http://localhost:3000') ||
      url.startsWith('http://127.0.0.1:3000')) {
    return url.replaceAll(
        RegExp(r'http://(localhost|127\.0\.0\.1):3000'), 'http://10.0.2.2:3000');
  }
  if (url.startsWith('/')) {
    return 'http://10.0.2.2:3000$url';
  }
  return url;
}

class _Bubble extends StatelessWidget {
  final _Message msg;
  final NeedHubTokens t;
  final Color avatarColor;
  final String initials;
  final String senderName;

  const _Bubble({
    required this.msg,
    required this.t,
    required this.avatarColor,
    required this.initials,
    this.senderName = '',
  });

  @override
  Widget build(BuildContext context) {
    final isImage = msg.imagePath != null || msg.imageUrl != null;
    final resolvedUrl = _resolveUrl(msg.imageUrl);
    final heroTag = msg.remoteId ??
        resolvedUrl ??
        msg.imagePath ??
        'img_${msg.time.millisecondsSinceEpoch}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment:
            msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                msg.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!msg.isMe) ...[
                Container(
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.only(right: 6, bottom: 2),
                  decoration: BoxDecoration(
                    color: avatarColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: GoogleFonts.bricolageGrotesque(
                        fontSize: 9, fontWeight: FontWeight.w700, color: avatarColor),
                  ),
                ),
              ],
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72),
                  decoration: BoxDecoration(
                    color: msg.isMe ? NeedHubTokens.clay : t.card,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(msg.isMe ? 18 : 4),
                      bottomRight: Radius.circular(msg.isMe ? 4 : 18),
                    ),
                    border: msg.isMe
                        ? null
                        : Border.all(color: t.rail, width: 1),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: msg.isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isImage)
                        Padding(
                          padding: EdgeInsets.only(
                              bottom: (msg.text != null && msg.text!.isNotEmpty) ? 6 : 4),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              NHFullScreenImageViewer.open(
                                context,
                                imageUrl: resolvedUrl,
                                imagePath: msg.imagePath,
                                heroTag: heroTag,
                                title: senderName.isNotEmpty
                                    ? senderName
                                    : (msg.isMe ? 'You' : 'Image'),
                                subtitle: msg.timeLabel,
                              );
                            },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Hero(
                                  tag: heroTag,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: resolvedUrl != null
                                        ? Image.network(
                                            resolvedUrl,
                                            fit: BoxFit.cover,
                                            width: MediaQuery.of(context).size.width * 0.64,
                                            errorBuilder: (_, __, ___) => Container(
                                              width: MediaQuery.of(context).size.width * 0.64,
                                              height: 140,
                                              color: t.rail,
                                              alignment: Alignment.center,
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.broken_image_outlined,
                                                      color: t.muted),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Tap to expand full screen',
                                                    style: TextStyle(
                                                        color: t.muted, fontSize: 11),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                        : Image.file(
                                            File(msg.imagePath!),
                                            fit: BoxFit.cover,
                                            width: MediaQuery.of(context).size.width * 0.64,
                                            errorBuilder: (_, __, ___) => Container(
                                              width: MediaQuery.of(context).size.width * 0.64,
                                              height: 140,
                                              color: t.rail,
                                              alignment: Alignment.center,
                                              child: Icon(Icons.broken_image_outlined,
                                                  color: t.muted),
                                            ),
                                          ),
                                  ),
                                ),
                                Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.65),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.fullscreen_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (msg.text != null && msg.text!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text(
                            msg.text!,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 14,
                              color: msg.isMe ? Colors.white : t.ink,
                              height: 1.45,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 2, 4, 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              msg.timeLabel,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 10.5,
                                color: msg.isMe
                                    ? Colors.white.withValues(alpha: 0.65)
                                    : t.muted,
                              ),
                            ),
                            if (msg.isMe) ...[
                              const SizedBox(width: 3),
                              Icon(
                                msg.isRead
                                    ? Icons.done_all_rounded
                                    : Icons.done_rounded,
                                size: 13,
                                color: msg.isRead
                                    ? const Color(0xFF5BC8FB)
                                    : Colors.white.withValues(alpha: 0.65),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (msg.reactions.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                  top: 4, left: msg.isMe ? 0 : 32, right: msg.isMe ? 4 : 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.rail, width: 1),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4)
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: msg.reactions
                      .map((e) =>
                          Text(e, style: const TextStyle(fontSize: 14)))
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  final String initials;
  final Color color;
  final NeedHubTokens t;

  const _TypingIndicator(
      {required this.initials, required this.color, required this.t});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.initials,
              style: GoogleFonts.bricolageGrotesque(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: widget.color),
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: widget.t.card,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: widget.t.rail, width: 1),
            ),
            child: AnimatedBuilder(
              animation: _anim,
              builder: (_, __) => Row(
                children: List.generate(3, (i) {
                  final delay = i * 0.25;
                  final value = (_anim.value - delay).clamp(0.0, 1.0);
                  return Padding(
                    padding: EdgeInsets.only(right: i < 2 ? 4.0 : 0),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: widget.t.muted
                            .withValues(alpha: 0.3 + value * 0.7),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMenuSheet extends StatelessWidget {
  final String personName;
  final String? personUserId;
  final bool isFriend;
  final bool isBlocked;
  final VoidCallback onToggleFriend;
  final VoidCallback onDeleteForMe;

  const _ChatMenuSheet({
    required this.personName,
    this.personUserId,
    required this.isFriend,
    required this.isBlocked,
    required this.onToggleFriend,
    required this.onDeleteForMe,
  });

  void _openReport(BuildContext context, {required bool alsoBlock}) {
    Navigator.of(context).pop();
    NhReportSheet.open(
      context,
      targetName: personName,
      targetType: personUserId != null ? 'USER' : null,
      targetId: personUserId,
      alsoBlock: alsoBlock,
    );
  }

  void _confirmDelete(BuildContext context) {
    Navigator.of(context).pop();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete this chat for you?'),
        content: const Text(
            'Messages will be removed from your device only. The other person will still see them.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              onDeleteForMe();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Chat cleared for you')),
              );
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmBlock(BuildContext context) {
    Navigator.of(context).pop();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Block $personName?'),
        content: const Text(
            'They will not be able to message or find you. You can unblock later from settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              blockUser(personName);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$personName has been blocked')),
              );
            },
            child: const Text('Block', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(
          8, 14, 8, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: t.rail, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),
          _MenuRow(
            icon: isFriend
                ? Icons.person_remove_outlined
                : Icons.person_add_outlined,
            label: isFriend ? 'Remove friend' : 'Add friend',
            color: NeedHubTokens.clay,
            onTap: () {
              Navigator.of(context).pop();
              onToggleFriend();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(isFriend
                        ? '$personName removed from friends'
                        : 'Friend request sent')),
              );
            },
          ),
          if (isBlocked)
            _MenuRow(
              icon: Icons.lock_open_rounded,
              label: 'Unblock',
              color: NeedHubTokens.forest,
              onTap: () {
                Navigator.of(context).pop();
                unblockUser(personName);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$personName unblocked')),
                );
              },
            )
          else
            _MenuRow(
              icon: Icons.block_rounded,
              label: 'Block',
              color: Colors.red.shade400,
              onTap: () => _confirmBlock(context),
            ),
          _MenuRow(
            icon: Icons.flag_outlined,
            label: 'Report',
            color: Colors.red.shade400,
            onTap: () => _openReport(context, alsoBlock: false),
          ),
          if (!isBlocked)
            _MenuRow(
              icon: Icons.gpp_bad_outlined,
              label: 'Block and report',
              color: Colors.red.shade400,
              onTap: () => _openReport(context, alsoBlock: true),
            ),
          _MenuRow(
            icon: Icons.delete_outline_rounded,
            label: 'Delete chat for me',
            color: Colors.red.shade400,
            onTap: () => _confirmDelete(context),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.muted2)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: t.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
