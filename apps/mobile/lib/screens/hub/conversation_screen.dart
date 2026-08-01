import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/user_state.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/profiles_api.dart';
import '../../services/social_providers.dart';
import '../../services/socket_service.dart';
import '../../theme/tokens.dart';
import '../../widgets/nh_avatar.dart';
import '../../widgets/nh_empty_state.dart';
import '../../widgets/nh_full_screen_image_viewer.dart';
import '../../widgets/nh_report_sheet.dart';
import '../person/person_screen.dart';
import '../../providers/language_provider.dart';
import '../../l10n/app_strings.dart';
import '../../services/translate_api.dart';

// In-memory cache (fast path, lives for the app session)
final Map<String, List<_Message>> _threadMessageCache = {};

Future<void> _persistMessages(String key, List<_Message> messages) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(messages.map((m) => {
      'text': m.text,
      'imageUrl': m.imageUrl,
      'isMe': m.isMe,
      'time': m.time.toIso8601String(),
      'remoteId': m.remoteId,
      'senderName': m.senderName,
      'isRead': m.isRead,
      'reactionsMap': m.reactionsMap,
      'replyTo': m.replyTo == null ? null : {
        'text': m.replyTo!.text,
        'isMe': m.replyTo!.isMe,
        'time': m.replyTo!.time.toIso8601String(),
        'senderName': m.replyTo!.senderName,
        'remoteId': m.replyTo!.remoteId,
      },
    }).toList());
    await prefs.setString('msg_cache_$key', encoded);
  } catch (_) {}
}

Future<List<_Message>> _loadPersistedMessages(String key) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('msg_cache_$key');
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map((m) {
      _Message? replyTo;
      if (m['replyTo'] is Map) {
        final r = (m['replyTo'] as Map).cast<String, dynamic>();
        replyTo = _Message(
          text: r['text'] as String?,
          isMe: r['isMe'] as bool? ?? false,
          time: DateTime.tryParse(r['time'] as String? ?? '') ?? DateTime.now(),
          senderName: r['senderName'] as String? ?? '',
          remoteId: r['remoteId'] as String?,
        );
      }
      return _Message(
        text: m['text'] as String?,
        imageUrl: m['imageUrl'] as String?,
        isMe: m['isMe'] as bool? ?? false,
        time: DateTime.tryParse(m['time'] as String? ?? '') ?? DateTime.now(),
        remoteId: m['remoteId'] as String?,
        senderName: m['senderName'] as String? ?? '',
        isRead: m['isRead'] as bool? ?? false,
        reactionsMap: m['reactionsMap'] is Map ? (m['reactionsMap'] as Map).cast<String, String>() : const {},
        replyTo: replyTo,
      );
    }).toList();
  } catch (_) { return []; }
}

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
  bool _loading = false;
  _Message? _replyingTo;

  bool get _isFriend =>
      widget.userId != null &&
      friendUserIdsNotifier.value.contains(widget.userId!);
  bool get _isBlocked =>
      widget.userId != null &&
      blockedUserIdsNotifier.value.contains(widget.userId!);
  bool get _hasRealApi => widget.userId != null;

  void _bump() {
    if (mounted) setState(() {});
  }

  late List<_Message> _messages;
  String? _resolvedThreadId;
  Timer? _tailPoller;

  @override
  void initState() {
    super.initState();
    friendsNotifier.addListener(_bump);
    blockedNotifier.addListener(_bump);
    friendUserIdsNotifier.addListener(_bump);
    blockedUserIdsNotifier.addListener(_bump);
    _resolvedThreadId = widget.threadId;

    if (_hasRealApi) {
      final cacheKey = widget.threadId ?? widget.userId ?? '';
      // Seed from in-memory cache instantly (same session)
      _messages = List.from(_threadMessageCache[cacheKey] ?? []);
      _loading = _messages.isEmpty;
      if (_messages.isEmpty) {
        // Load from disk cache before API call so messages show instantly
        _loadPersistedMessages(cacheKey).then((persisted) {
          if (!mounted) return;
          if (persisted.isNotEmpty) {
            _threadMessageCache[cacheKey] = persisted;
            setState(() { _messages = persisted; _loading = false; });
            _scrollToBottom();
          }
        });
      }
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
        final myId = ref.read(authProvider).userId ?? myProfileNotifier.value?.id;
        final loaded = msgs
              .map((m) => _Message(
                    text: m.body.isEmpty ? null : m.body,
                    imageUrl: m.imageUrl,
                    isMe: myId != null && m.senderId == myId,
                    time: m.createdAt,
                    senderName: m.senderName,
                    reactionsMap: _parseReactionsMap(m.reactions),
                    replyTo: m.replyTo != null ? _Message(
                      text: m.replyTo!.body.isEmpty ? null : m.replyTo!.body,
                      isMe: myId != null && m.replyTo!.senderId == myId,
                      time: m.replyTo!.createdAt,
                      senderName: m.replyTo!.senderName,
                      remoteId: m.replyTo!.id,
                    ) : null,
                    isRead: m.readAt != null,
                    remoteId: m.id,
                  ))
              .toList();
        final cacheKey = _resolvedThreadId ?? widget.userId ?? '';
        _threadMessageCache[cacheKey] = loaded;
        _persistMessages(cacheKey, loaded);
        _saveCache();
        setState(() { _messages = loaded; _loading = false; });
        _scrollToBottom();
      } catch (_) {/* keep empty */}
    } else {
      if (mounted) setState(() { _loading = false; });
    }

    _setupSocketListeners();

    // Fallback poll every 30s in case socket drops
    _tailPoller?.cancel();
    _tailPoller = Timer.periodic(const Duration(seconds: 30), (_) => _tail());
  }

  void _saveCache() {
    final keys = <String>{
      if (_resolvedThreadId != null) _resolvedThreadId!,
      if (widget.threadId != null) widget.threadId!,
      if (widget.userId != null) widget.userId!,
    };
    for (final k in keys) {
      if (k.isNotEmpty) {
        _threadMessageCache[k] = List.from(_messages);
        _persistMessages(k, _messages);
      }
    }
  }

  bool _socketListenersRegistered = false;

  void _setupSocketListeners() {
    if (_resolvedThreadId == null || _socketListenersRegistered) return;
    _socketListenersRegistered = true;
    final socket = SocketService();
    socket.joinThread(_resolvedThreadId!);

    socket.onNewMessage((data) {
      final msgId = data['id'] as String?;
      if (!mounted) return;
      if (msgId != null && _messages.any((m) => m.remoteId == msgId)) return;
      final myId = ref.read(authProvider).userId ?? myProfileNotifier.value?.id;
      final body = data['body'] as String? ?? '';
      final imageUrl = data['imageUrl'] as String?;
      final senderId = data['senderId'] as String?;
      final senderData = data['sender'] is Map ? Map<String, dynamic>.from(data['sender'] as Map) : null;
      final msgSenderName = senderData?['displayName'] as String? ?? widget.name;
      final createdAt = data['createdAt'] != null
          ? DateTime.tryParse(data['createdAt'] as String) ?? DateTime.now()
          : DateTime.now();
      final isMine = myId != null && senderId == myId;

      _Message? replyToRef;
      final replyToData = data['replyTo'];
      if (replyToData is Map) {
        final rMap = Map<String, dynamic>.from(replyToData);
        final rBody = rMap['body'] as String? ?? '';
        final rSenderId = rMap['senderId'] as String?;
        final rCreatedAt = rMap['createdAt'] != null
            ? DateTime.tryParse(rMap['createdAt'] as String) ?? DateTime.now()
            : DateTime.now();
        final rSender = rMap['sender'] is Map ? Map<String, dynamic>.from(rMap['sender'] as Map) : null;
        final rSenderName = rSender?['displayName'] as String? ?? widget.name;
        replyToRef = _Message(
          text: rBody.isEmpty ? null : rBody,
          isMe: myId != null && rSenderId == myId,
          time: rCreatedAt,
          senderName: rSenderName,
          remoteId: rMap['id'] as String?,
        );
      }

      final reactionsMap = _parseReactionsMap(
        data['reactions'] is Map ? Map<String, dynamic>.from(data['reactions'] as Map) : null,
      );

      if (isMine) {
        final optimisticIdx = _messages.lastIndexWhere((m) =>
            m.isMe &&
            m.remoteId == null &&
            (m.text ?? '') == body &&
            (m.imageUrl ?? '') == (imageUrl ?? ''));
        if (optimisticIdx != -1) {
          setState(() {
            _messages[optimisticIdx] = _messages[optimisticIdx].copyWith(
              remoteId: msgId,
              reactionsMap: reactionsMap.isNotEmpty ? reactionsMap : null,
              replyTo: replyToRef ?? _messages[optimisticIdx].replyTo,
            );
          });
          _saveCache();
          return;
        }
      }

      final newMsg = _Message(
        text: body.isEmpty ? null : body,
        imageUrl: imageUrl,
        isMe: isMine,
        time: createdAt,
        remoteId: msgId,
        senderName: msgSenderName,
        replyTo: replyToRef,
        reactionsMap: reactionsMap,
      );
      setState(() => _messages.add(newMsg));
      _saveCache();
      Future.microtask(_scrollToBottom);
      if (!isMine && _resolvedThreadId != null) {
        ref.read(messagingApiProvider).markRead(_resolvedThreadId!);
      }
    });

    socket.onMessageReaction((data) {
      if (!mounted) return;
      final msgId = data['messageId'] as String?;
      if (msgId == null) return;
      final rawReactions = data['reactions'];
      final updatedMap = _parseReactionsMap(
        rawReactions is Map ? Map<String, dynamic>.from(rawReactions) : null,
      );
      final idx = _messages.indexWhere((m) => m.remoteId == msgId);
      if (idx != -1) {
        setState(() {
          _messages[idx] = _messages[idx].copyWith(reactionsMap: updatedMap);
        });
        _saveCache();
      }
    });

    socket.onMessagesRead((data) {
      if (!mounted) return;
      final ids = (data['messageIds'] as List?)?.cast<String>() ?? const [];
      if (ids.isEmpty) return;
      final myId = ref.read(authProvider).userId ?? myProfileNotifier.value?.id;
      if (myId == null) return;
      final readerId = data['readerId'] as String?;
      if (readerId == myId) return;
      var changed = false;
      setState(() {
        for (var i = 0; i < _messages.length; i++) {
          final m = _messages[i];
          if (m.isMe && !m.isRead && m.remoteId != null && ids.contains(m.remoteId)) {
            _messages[i] = m.copyWith(isRead: true);
            changed = true;
          }
        }
      });
      if (changed) {
        _saveCache();
      }
    });
  }

  Future<void> _tail() async {
    if (_resolvedThreadId == null || widget.userId == null) return;
    final api = ref.read(messagingApiProvider);
    final myId = ref.read(authProvider).userId ?? myProfileNotifier.value?.id;
    try {
      final newer = await api.messages(
        _resolvedThreadId!,
        limit: 30,
      );

      bool hasNewMessage = false;
      setState(() {
        for (final m in newer.reversed) {
          final replyToMsg = m.replyTo != null ? _Message(
            text: m.replyTo!.body.isEmpty ? null : m.replyTo!.body,
            isMe: myId != null && m.replyTo!.senderId == myId,
            time: m.replyTo!.createdAt,
            senderName: m.replyTo!.senderName,
            remoteId: m.replyTo!.id,
          ) : null;
          final existingIdx = _messages.indexWhere((existing) =>
              existing.remoteId == m.id ||
              (existing.remoteId == null &&
                  existing.isMe &&
                  myId != null &&
                  m.senderId == myId &&
                  existing.text == (m.body.isEmpty ? null : m.body)));
          if (existingIdx != -1) {
            _messages[existingIdx] = _messages[existingIdx].copyWith(
              remoteId: m.id,
              reactionsMap: _parseReactionsMap(m.reactions),
              isRead: m.readAt != null,
              replyTo: replyToMsg ?? _messages[existingIdx].replyTo,
            );
          } else {
            hasNewMessage = true;
            _messages.add(_Message(
              text: m.body.isEmpty ? null : m.body,
              imageUrl: m.imageUrl,
              isMe: myId != null && m.senderId == myId,
              time: m.createdAt,
              isRead: m.readAt != null,
              remoteId: m.id,
              senderName: m.senderName,
              reactionsMap: _parseReactionsMap(m.reactions),
              replyTo: replyToMsg,
            ));
          }
        }
      });
      _saveCache();
      if (hasNewMessage) {
        _scrollToBottom();
      }
    } catch (_) {/* keep last state */}
  }

  @override
  void dispose() {
    _tailPoller?.cancel();
    final socket = SocketService();
    if (_resolvedThreadId != null) socket.leaveThread(_resolvedThreadId!);
    socket.off('new_message');
    socket.off('message_reaction');
    socket.off('messages_read');
    friendsNotifier.removeListener(_bump);
    blockedNotifier.removeListener(_bump);
    friendUserIdsNotifier.removeListener(_bump);
    blockedUserIdsNotifier.removeListener(_bump);
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

  Future<void> _sendToApi({String? text, String? imagePath, String? replyToId}) async {
    if (widget.userId == null) return;
    debugPrint('[CHAT] _sendToApi called: text=$text, replyToId=$replyToId');
    final api = ref.read(apiClientProvider);
    Map<String, dynamic> res;
    if (imagePath != null) {
      final form = FormData.fromMap({
        if (text != null && text.isNotEmpty) 'body': text,
        if (replyToId != null) 'replyToId': replyToId,
        'image': await MultipartFile.fromFile(imagePath,
            filename: imagePath.split('/').last),
      });
      res = await api.postForm('/chats/dm/${widget.userId}/messages', form);
    } else if (text != null && text.isNotEmpty) {
      final body = {
        'body': text,
        if (replyToId != null) 'replyToId': replyToId,
      };
      debugPrint('[CHAT] Sending POST body: $body');
      res = await api.post('/chats/dm/${widget.userId}/messages', body);
    } else {
      return;
    }
    debugPrint('[CHAT] Server response: replyTo=${res['replyTo']}, id=${res['id']}');
    // Remember thread + last-message id so the tail poller skips our own
    // just-sent message and hydrates without duplicates.
    final threadId = res['threadId'] as String? ??
        (res['thread'] as Map<String, dynamic>?)?['id'] as String?;
    final msgId = res['id'] as String?;
    if (threadId != null) {
      final wasNull = _resolvedThreadId == null;
      _resolvedThreadId = threadId;
      if (wasNull) _setupSocketListeners();
    }
    if (msgId != null && mounted) {
      _Message? replyToRef;
      final replyToData = res['replyTo'];
      if (replyToData is Map) {
        final rMap = Map<String, dynamic>.from(replyToData);
        final rBody = rMap['body'] as String? ?? '';
        final rSenderId = rMap['senderId'] as String?;
        final rCreatedAt = rMap['createdAt'] != null
            ? DateTime.tryParse(rMap['createdAt'] as String) ?? DateTime.now()
            : DateTime.now();
        final rSender = rMap['sender'] is Map ? Map<String, dynamic>.from(rMap['sender'] as Map) : null;
        final rSenderName = rSender?['displayName'] as String? ?? widget.name;
        final myId = ref.read(authProvider).userId ?? myProfileNotifier.value?.id;
        replyToRef = _Message(
          text: rBody.isEmpty ? null : rBody,
          isMe: myId != null && rSenderId == myId,
          time: rCreatedAt,
          senderName: rSenderName,
          remoteId: rMap['id'] as String?,
        );
      }

      setState(() {
        final idx = _messages.lastIndexWhere((m) =>
            m.isMe &&
            m.remoteId == null &&
            ((text != null && m.text == text) || (imagePath != null && m.imagePath == imagePath)));
        if (idx != -1) {
          _messages[idx] = _messages[idx].copyWith(
            remoteId: msgId,
            replyTo: replyToRef ?? _messages[idx].replyTo,
          );
        } else if (_messages.isNotEmpty) {
          _messages[_messages.length - 1] = _messages.last.copyWith(
            remoteId: msgId,
            replyTo: replyToRef ?? _messages.last.replyTo,
          );
        }
      });
      _saveCache();
    }
    // Kick off the poller if this send happened before hydration finished.
    _tailPoller ??=
        Timer.periodic(const Duration(seconds: 2), (_) => _tail());
  }

  String _sendErrorMessage(Object e) {
    if (e is DioException) {
      final code = (e.response?.data as Map?)?['code'] as String?;
      switch (code) {
        case 'BLOCKED':
          return 'This person has blocked you';
        case 'NOT_FRIENDS':
          return 'Add them as a friend first to send messages';
      }
      final msg = (e.response?.data as Map?)?['error'] as String?;
      if (msg != null) return msg;
    }
    return 'Failed to send message';
  }

  Future<void> _send() async {
    if (_isBlocked) return;
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();
    final replyRef = _replyingTo;
    setState(() => _replyingTo = null);
    
    String? sendReplyToId = replyRef?.remoteId;
    if (replyRef != null && sendReplyToId == null) {
      final match = _messages.firstWhere(
        (m) => m.text == replyRef.text && m.remoteId != null,
        orElse: () => replyRef,
      );
      sendReplyToId = match.remoteId;
    }

    final msg = _Message(text: text, isMe: true, time: DateTime.now(), replyTo: replyRef);
    setState(() { _messages.add(msg); _isTyping = !_hasRealApi; });
    _saveCache();
    _scrollToBottom();

    if (_hasRealApi) {
      setState(() => _sending = true);
      try {
        await _sendToApi(text: text, replyToId: sendReplyToId);
      } catch (e) {
        if (mounted) {
          setState(() => _messages.removeLast());
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_sendErrorMessage(e))));
        }
      } finally {
        if (mounted) setState(() => _sending = false);
      }
    } else {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isTyping = false);
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
    if (_isBlocked) return;
    final replyRef = _replyingTo;
    setState(() => _replyingTo = null);
    
    final msg = _Message(imagePath: path, isMe: true, time: DateTime.now(), replyTo: replyRef);
    setState(() { _messages.add(msg); _isTyping = !_hasRealApi; });
    _scrollToBottom();

    if (_hasRealApi) {
      setState(() => _sending = true);
      try {
        await _sendToApi(imagePath: path, replyToId: replyRef?.remoteId);
      } catch (e) {
        if (mounted) {
          setState(() => _messages.removeLast());
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_sendErrorMessage(e))));
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

  Future<void> _addReaction(int idx, String emoji) async {
    if (idx < 0 || idx >= _messages.length) return;
    final msg = _messages[idx];
    final myId = ref.read(authProvider).userId ?? myProfileNotifier.value?.id ?? 'me';

    setState(() {
      final updatedMap = Map<String, String>.from(msg.reactionsMap);
      if (updatedMap[myId] == emoji) {
        updatedMap.remove(myId);
      } else {
        updatedMap[myId] = emoji;
      }
      _messages[idx] = msg.copyWith(reactionsMap: updatedMap);
    });
    _saveCache();

    if (msg.remoteId != null) {
      try {
        final serverReactions = await ref.read(messagingApiProvider).react(msg.remoteId!, emoji);
        if (mounted && serverReactions != null) {
          setState(() {
            final currentIdx = _messages.indexWhere((m) => m.remoteId == msg.remoteId);
            if (currentIdx != -1) {
              _messages[currentIdx] = _messages[currentIdx].copyWith(
                reactionsMap: _parseReactionsMap(serverReactions),
              );
            }
          });
          _saveCache();
        }
      } catch (_) {}
    }
  }

  Future<void> _deleteMessage(int idx) async {
    final msg = _messages[idx];
    setState(() {
      _messages.removeAt(idx);
    });

    if (msg.remoteId != null) {
      try {
        await ref.read(messagingApiProvider).deleteMessage(msg.remoteId!);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not delete message on server.')),
          );
        }
      }
    }
  }

  void _copyMessage(int idx) {
    final msg = _messages[idx];
    if (msg.text != null && msg.text!.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: msg.text!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message copied to clipboard'),
          duration: Duration(seconds: 1),
        ),
      );
    }
    setState(() {});
  }

  void _scrollToMessage(String? remoteId, DateTime? time) {
    if (remoteId == null && time == null) return;
    final idx = _messages.indexWhere((m) =>
        (remoteId != null && m.remoteId == remoteId) ||
        (time != null && m.time == time));
    if (idx != -1 && _scrollController.hasClients) {
      final target = (idx * 68.0).clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _showReactionMenu(int index, _Message message) {
    HapticFeedback.mediumImpact();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss Reactions',
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
          child: FadeTransition(opacity: anim1, child: child),
        );
      },
      pageBuilder: (context, anim1, anim2) {
        final t = context.tokens;
        return SafeArea(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(color: t.rail, width: 1.2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: message.isMe ? NeedHubTokens.clay : t.chip,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              message.text ?? (message.imageUrl != null || message.imagePath != null ? '📷 Image' : 'Message'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 13.5,
                                color: message.isMe ? Colors.white : t.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        '❤️', '👍', '🔥', '😂', '😮', '😢', '🙏', '👏', '🎉', '💡', '😍', '💯'
                      ].map((emoji) {
                        final myId = ref.read(authProvider).userId ?? myProfileNotifier.value?.id ?? 'me';
                        final isSelected = message.reactionsMap[myId] == emoji;
                        return _PopUpEmojiButton(
                          emoji: emoji,
                          isSelected: isSelected,
                          t: t,
                          onTap: () {
                            Navigator.of(context).pop();
                            _addReaction(index, emoji);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Divider(color: t.rail, height: 1),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _QuickActionButton(
                          icon: Icons.reply_rounded,
                          label: 'Reply',
                          color: NeedHubTokens.clay,
                          t: t,
                          onTap: () {
                            Navigator.of(context).pop();
                            HapticFeedback.lightImpact();
                            setState(() => _replyingTo = message);
                          },
                        ),
                        if (message.text != null && message.text!.isNotEmpty)
                          _QuickActionButton(
                            icon: Icons.copy_rounded,
                            label: 'Copy',
                            color: t.ink,
                            t: t,
                            onTap: () {
                              Navigator.of(context).pop();
                              _copyMessage(index);
                            },
                          ),
                        if (message.isMe)
                          _QuickActionButton(
                            icon: Icons.delete_outline_rounded,
                            label: 'Delete',
                            color: Colors.red,
                            t: t,
                            onTap: () {
                              Navigator.of(context).pop();
                              _deleteMessage(index);
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<dynamic> get _listItems {
    final items = <dynamic>[];
    DateTime? lastDate;
    for (int i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final localTime = m.time.toLocal();
      final d = DateTime(localTime.year, localTime.month, localTime.day);
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
      onTap: () => setState(() {}),
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
              Expanded(
                child: Column(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                  threadId: _resolvedThreadId,
                  isFriend: _isFriend,
                  isBlocked: _isBlocked,
                  onToggleFriend: () {
                    final friendsApi = ref.read(friendsApiProvider);
                    if (_isFriend) {
                      removeFriend(widget.name,
                          userId: widget.userId, api: friendsApi);
                    } else {
                      addFriend(widget.name,
                          userId: widget.userId, api: friendsApi);
                    }
                  },
                  onBlock: () {
                    blockUser(widget.name,
                        userId: widget.userId,
                        api: ref.read(friendsApiProvider));
                  },
                  onUnblock: () {
                    unblockUser(widget.name,
                        userId: widget.userId,
                        api: ref.read(friendsApiProvider));
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
            if (_isBlocked)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Colors.red.shade50,
                child: Row(
                  children: [
                    Icon(Icons.block_rounded, color: Colors.red.shade400, size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You\'ve blocked ${widget.name}. Unblock to send messages.',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 13, color: Colors.red.shade600),
                      ),
                    ),
                  ],
                ),
              )
            else if (_hasRealApi && !_isFriend)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: NeedHubTokens.forest.withValues(alpha: 0.08),
                child: Row(
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded,
                        color: NeedHubTokens.forest, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Chitchat mode · Add friend to move to official DMs',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 12,
                            color: NeedHubTokens.forest),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
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
                      onDoubleTap: () {
                        HapticFeedback.lightImpact();
                        _addReaction(item.index, '❤️');
                      },
                      onLongPress: () => _showReactionMenu(item.index, item.message),
                      child: Dismissible(
                        key: ValueKey('msg_${item.index}_${item.message.remoteId ?? item.message.time.millisecondsSinceEpoch}'),
                        direction: DismissDirection.startToEnd,
                        confirmDismiss: (_) async {
                          HapticFeedback.mediumImpact();
                          setState(() {
                            _replyingTo = item.message;
                          });
                          return false; // Don't dismiss bubble
                        },
                        background: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 20),
                          child: Icon(Icons.reply_rounded, color: NeedHubTokens.clay, size: 22),
                        ),
                        child: Column(
                          crossAxisAlignment: item.message.isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            _Bubble(
                              msg: item.message,
                              t: t,
                              avatarColor: widget.avatarColor,
                              initials: widget.initials,
                              avatarUrl: widget.avatarUrl,
                              senderName: item.message.isMe ? 'You' : widget.name,
                              onQuoteTap: () => _scrollToMessage(
                                  item.message.replyTo?.remoteId,
                                  item.message.replyTo?.time),
                            ),
                            if (item.message.reactionsMap.isNotEmpty)
                              _ReactionsBadgeBar(
                                reactionsMap: item.message.reactionsMap,
                                currentUserId: ref.read(authProvider).userId ?? myProfileNotifier.value?.id ?? 'me',
                                isMe: item.message.isMe,
                                t: t,
                                onToggleEmoji: (emoji) => _addReaction(item.index, emoji),
                              ),
                          ],
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),

            // Input bar
            Column(
              children: [
                if (_replyingTo != null)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: t.card,
                      border: Border(top: BorderSide(color: t.rail, width: 1)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 36,
                          decoration: BoxDecoration(
                            color: NeedHubTokens.clay,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.reply_rounded, color: NeedHubTokens.clay, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    _replyingTo!.isMe ? 'Replying to yourself' : 'Replying to ${widget.name}',
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: NeedHubTokens.clay,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _replyingTo!.text ?? (_replyingTo!.imagePath != null || _replyingTo!.imageUrl != null ? '📷 Image' : 'Message'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.hankenGrotesk(fontSize: 12.5, color: t.muted),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _replyingTo = null),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: t.chip,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.close_rounded, color: t.muted2, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, bottomPad + 10),
                  decoration: BoxDecoration(
                    color: t.card,
                    border: Border(top: BorderSide(color: t.rail, width: 1)),
                  ),
              child: _isBlocked
                  ? SizedBox(
                      height: 42,
                      child: Center(
                        child: Text(
                          'Unblock ${widget.name} to send messages',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 13, color: t.muted),
                        ),
                      ),
                    )
                  : Row(
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
                              style: GoogleFonts.hankenGrotesk(
                                  fontSize: 14, color: t.ink),
                              decoration: InputDecoration(
                                hintText: 'Message…',
                                hintStyle: GoogleFonts.hankenGrotesk(
                                    fontSize: 14, color: t.muted),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
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
          ],
        ),
      ),
    );
  }
}

Map<String, String> _parseReactionsMap(Map<String, dynamic>? raw) {
  if (raw == null) return const {};
  final result = <String, String>{};
  raw.forEach((key, val) {
    if (val != null) result[key] = val.toString();
  });
  return result;
}

class _Message {
  final String? text;
  final String? imagePath;
  /// Remote image URL (from API). Preferred over imagePath when set.
  final String? imageUrl;
  final bool isMe;
  final DateTime time;
  final Map<String, String> reactionsMap;
  final _Message? replyTo;
  final bool isRead;
  /// Server message id — set for messages loaded from the API.
  final String? remoteId;
  final String senderName;

  _Message({
    this.text,
    this.imagePath,
    this.imageUrl,
    required this.isMe,
    required this.time,
    Map<String, String>? reactionsMap,
    this.replyTo,
    this.isRead = false,
    this.remoteId,
    this.senderName = '',
  }) : reactionsMap = reactionsMap ?? const {};

  List<String> get reactions => reactionsMap.values.toList();

  _Message copyWith({
    String? text,
    String? imagePath,
    String? imageUrl,
    bool? isMe,
    DateTime? time,
    Map<String, String>? reactionsMap,
    _Message? replyTo,
    bool? isRead,
    String? remoteId,
    String? senderName,
  }) {
    return _Message(
      text: text ?? this.text,
      imagePath: imagePath ?? this.imagePath,
      imageUrl: imageUrl ?? this.imageUrl,
      isMe: isMe ?? this.isMe,
      time: time ?? this.time,
      reactionsMap: reactionsMap ?? Map.from(this.reactionsMap),
      replyTo: replyTo ?? this.replyTo,
      isRead: isRead ?? this.isRead,
      remoteId: remoteId ?? this.remoteId,
      senderName: senderName ?? this.senderName,
    );
  }

  String get timeLabel {
    final localTime = time.toLocal();
    final h = localTime.hour.toString().padLeft(2, '0');
    final m = localTime.minute.toString().padLeft(2, '0');
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
    final localDate = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDay = DateTime(localDate.year, localDate.month, localDate.day);
    if (msgDay == today) return 'Today';
    if (msgDay == yesterday) return 'Yesterday';
    return '${localDate.day}/${localDate.month}/${localDate.year}';
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



class _ReactionsBadgeBar extends StatelessWidget {
  final Map<String, String> reactionsMap;
  final String currentUserId;
  final ValueChanged<String> onToggleEmoji;
  final NeedHubTokens t;
  final bool isMe;

  const _ReactionsBadgeBar({
    required this.reactionsMap,
    required this.currentUserId,
    required this.onToggleEmoji,
    required this.t,
    required this.isMe,
  });

  Map<String, int> get _counts {
    final map = <String, int>{};
    for (final r in reactionsMap.values) {
      map[r] = (map[r] ?? 0) + 1;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    if (reactionsMap.isEmpty) return const SizedBox.shrink();
    final counts = _counts;
    final myReaction = reactionsMap[currentUserId];

    return Padding(
      padding: EdgeInsets.only(
        top: 3,
        left: isMe ? 0 : 32,
        right: isMe ? 4 : 0,
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: counts.entries.map((entry) {
          final isSelected = myReaction == entry.key;
          return _ReactionBadgeChip(
            emoji: entry.key,
            count: entry.value,
            isSelected: isSelected,
            onTap: () => onToggleEmoji(entry.key),
            t: t,
          );
        }).toList(),
      ),
    );
  }
}

class _ReactionBadgeChip extends StatefulWidget {
  final String emoji;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;
  final NeedHubTokens t;

  const _ReactionBadgeChip({
    required this.emoji,
    required this.count,
    required this.isSelected,
    required this.onTap,
    required this.t,
  });

  @override
  State<_ReactionBadgeChip> createState() => _ReactionBadgeChipState();
}

class _ReactionBadgeChipState extends State<_ReactionBadgeChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final activeBg = widget.isSelected ? NeedHubTokens.clay.withValues(alpha: 0.18) : t.card;
    final activeBorder = widget.isSelected ? NeedHubTokens.clay : t.rail;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: activeBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: activeBorder, width: widget.isSelected ? 1.4 : 1.0),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: NeedHubTokens.clay.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.emoji, style: const TextStyle(fontSize: 13.5)),
              if (widget.count > 1) ...[
                const SizedBox(width: 3.5),
                Text(
                  '${widget.count}',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 11,
                    fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: widget.isSelected ? NeedHubTokens.clay : t.ink,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PopUpEmojiButton extends StatefulWidget {
  final String emoji;
  final bool isSelected;
  final NeedHubTokens t;
  final VoidCallback onTap;

  const _PopUpEmojiButton({
    required this.emoji,
    required this.isSelected,
    required this.t,
    required this.onTap,
  });

  @override
  State<_PopUpEmojiButton> createState() => _PopUpEmojiButtonState();
}

class _PopUpEmojiButtonState extends State<_PopUpEmojiButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 1.35 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutBack,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? NeedHubTokens.clay.withValues(alpha: 0.18)
                : widget.t.chip,
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.isSelected
                  ? NeedHubTokens.clay
                  : widget.t.rail,
              width: widget.isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Text(
            widget.emoji,
            style: const TextStyle(fontSize: 24),
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final NeedHubTokens t;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.t,
    required this.onTap,
  });

  @override
  State<_QuickActionButton> createState() => _QuickActionButtonState();
}

class _QuickActionButtonState extends State<_QuickActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(widget.icon, color: widget.color, size: 20),
            ),
            const SizedBox(height: 4),
            Text(
              widget.label,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: widget.t.muted2,
              ),
            ),
          ],
        ),
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

const _apiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://10.0.2.2:3000',
);

String? _resolveUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http://localhost:3000') ||
      url.startsWith('http://127.0.0.1:3000')) {
    return url.replaceAll(
        RegExp(r'http://(localhost|127\.0\.0\.1):3000'), _apiBaseUrl);
  }
  if (url.contains('10.0.2.2:3000') && _apiBaseUrl != 'http://10.0.2.2:3000') {
    return url.replaceAll('http://10.0.2.2:3000', _apiBaseUrl);
  }
  if (url.startsWith('/')) {
    return '$_apiBaseUrl$url';
  }
  return url;
}

class _Bubble extends StatefulWidget {
  final _Message msg;
  final NeedHubTokens t;
  final Color avatarColor;
  final String initials;
  final String? avatarUrl;
  final String senderName;
  final VoidCallback? onQuoteTap;

  const _Bubble({
    required this.msg,
    required this.t,
    required this.avatarColor,
    required this.initials,
    this.avatarUrl,
    this.senderName = '',
    this.onQuoteTap,
  });

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  String? _translatedText;
  bool _showingTranslation = false;
  bool _translating = false;

  Future<void> _doTranslate(String targetLang) async {
    if (widget.msg.text == null || widget.msg.text!.isEmpty) return;
    setState(() => _translating = true);
    try {
      final result = await globalTranslateApi.translate(widget.msg.text!, targetLang);
      if (mounted) {
        setState(() {
          _translatedText = result;
          _showingTranslation = true;
          _translating = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _translating = false);
    }
  }

  void _showTranslatePicker(BuildContext context) {
    final t = widget.t;
    final s = S.of(uiLanguageNotifier.value);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: t.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.rail,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              s.translateTo,
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: t.ink,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kSupportedLanguages.map((lang) {
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _doTranslate(lang['code']!);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: t.rail, width: 1.5),
                    ),
                    child: Text(
                      lang['native']!,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.muted2,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.msg;
    final t = widget.t;
    final isImage = msg.imagePath != null || msg.imageUrl != null;
    final resolvedUrl = _resolveUrl(msg.imageUrl);
    final heroTag = msg.remoteId ??
        resolvedUrl ??
        msg.imagePath ??
        'img_${msg.time.millisecondsSinceEpoch}';
    final s = S.of(uiLanguageNotifier.value);

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
                Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 2),
                  child: NhAvatar(
                    avatarUrl: widget.avatarUrl,
                    initials: widget.initials,
                    size: 26,
                    borderRadius: 8,
                    backgroundColor: widget.avatarColor.withValues(alpha: 0.15),
                    textColor: widget.avatarColor,
                    fontSize: 9,
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
                      if (msg.replyTo != null)
                        GestureDetector(
                          onTap: widget.onQuoteTap,
                          child: Container(
                            margin: EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border(left: BorderSide(color: NeedHubTokens.forest.withValues(alpha: 0.8), width: 3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg.replyTo!.isMe ? 'You' : msg.replyTo!.senderName,
                                  style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.bold, color: msg.isMe ? Colors.white70 : t.muted2),
                                ),
                                Text(
                                  msg.replyTo!.text ?? 'Image',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.hankenGrotesk(fontSize: 12, color: msg.isMe ? Colors.white60 : t.muted),
                                ),
                              ],
                            ),
                          ),
                        ),
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
                                title: widget.senderName.isNotEmpty
                                    ? widget.senderName
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
                            _showingTranslation && _translatedText != null
                                ? _translatedText!
                                : msg.text!,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 14,
                              color: msg.isMe ? Colors.white : t.ink,
                              height: 1.45,
                            ),
                          ),
                        ),
                      if (!msg.isMe && msg.text != null && msg.text!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 2, 4, 2),
                          child: GestureDetector(
                            onTap: _showingTranslation
                                ? () => setState(() {
                                      _showingTranslation = false;
                                      _translatedText = null;
                                    })
                                : _translating
                                    ? null
                                    : () => _showTranslatePicker(context),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_translating)
                                  SizedBox(
                                    width: 10,
                                    height: 10,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: t.muted,
                                    ),
                                  )
                                else
                                  Icon(
                                    _showingTranslation
                                        ? Icons.undo_rounded
                                        : Icons.translate_rounded,
                                    size: 11,
                                    color: t.muted,
                                  ),
                                const SizedBox(width: 3),
                                Text(
                                  _translating
                                      ? s.translating
                                      : _showingTranslation
                                          ? s.showOriginal
                                          : s.translate,
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 10.5,
                                    color: t.muted,
                                  ),
                                ),
                              ],
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
  final String? threadId;
  final bool isFriend;
  final bool isBlocked;
  final VoidCallback onToggleFriend;
  final VoidCallback onBlock;
  final VoidCallback onUnblock;
  final VoidCallback onDeleteForMe;

  const _ChatMenuSheet({
    required this.personName,
    this.personUserId,
    this.threadId,
    required this.isFriend,
    required this.isBlocked,
    required this.onToggleFriend,
    required this.onBlock,
    required this.onUnblock,
    required this.onDeleteForMe,
  });

  void _openReport(BuildContext context, {required bool alsoBlock}) {
    Navigator.of(context).pop();
    NhReportSheet.open(
      context,
      targetName: personName,
      targetType: personUserId != null ? 'USER' : null,
      targetId: personUserId,
      threadId: threadId,
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
              onBlock();
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
                onUnblock();
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
