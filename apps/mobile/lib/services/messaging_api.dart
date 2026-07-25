import 'package:flutter/foundation.dart';
import 'api_client.dart';

class ChatSummary {
  final String threadId;
  final String otherUserId;
  final String otherDisplayName;
  final String? otherAvatarUrl;
  final String? lastMessageBody;
  final String? lastMessageImageUrl;
  final String? lastMessageSenderId;
  final DateTime updatedAt;
  final int unreadCount;

  const ChatSummary({
    required this.threadId,
    required this.otherUserId,
    required this.otherDisplayName,
    this.otherAvatarUrl,
    this.lastMessageBody,
    this.lastMessageImageUrl,
    this.lastMessageSenderId,
    required this.updatedAt,
    required this.unreadCount,
  });

DateTime _parseDateTime(dynamic value) {
  if (value is! String || value.trim().isEmpty) return DateTime.now();
  final raw = value.trim();
  final str = raw.endsWith('Z') || raw.contains('+') || (raw.length > 10 && raw.substring(10).contains('-'))
      ? raw
      : '${raw}Z';
  final parsed = DateTime.tryParse(str) ?? DateTime.tryParse(raw);
  return parsed?.toLocal() ?? DateTime.now();
}

class ChatSummary {
  final String threadId;
  final String otherUserId;
  final String otherDisplayName;
  final String? otherAvatarUrl;
  final String? lastMessageBody;
  final String? lastMessageImageUrl;
  final String? lastMessageSenderId;
  final DateTime updatedAt;
  final int unreadCount;

  const ChatSummary({
    required this.threadId,
    required this.otherUserId,
    required this.otherDisplayName,
    this.otherAvatarUrl,
    this.lastMessageBody,
    this.lastMessageImageUrl,
    this.lastMessageSenderId,
    required this.updatedAt,
    required this.unreadCount,
  });

  factory ChatSummary.fromJson(Map<String, dynamic> j) {
    final other = j['otherUser'] as Map<String, dynamic>? ?? const {};
    final profile = other['profile'] as Map<String, dynamic>?;
    final last = j['lastMessage'] as Map<String, dynamic>?;
    return ChatSummary(
      threadId: j['threadId'] as String,
      otherUserId: other['id'] as String? ?? '',
      otherDisplayName: other['displayName'] as String? ?? 'Unknown',
      otherAvatarUrl: profile?['avatarUrl'] as String?,
      lastMessageBody: last?['body'] as String?,
      lastMessageImageUrl: last?['imageUrl'] as String?,
      lastMessageSenderId: last?['senderId'] as String?,
      updatedAt: _parseDateTime(j['updatedAt']),
      unreadCount: (j['unreadCount'] as int?) ?? 0,
    );
  }

  String get timeLabel {
    final localTime = updatedAt.toLocal();
    final diff = DateTime.now().difference(localTime);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }
}

class DmMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String body;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime? readAt;

  const DmMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.body,
    this.imageUrl,
    required this.createdAt,
    this.readAt,
  });

  factory DmMessage.fromJson(Map<String, dynamic> j) {
    final sender = j['sender'] as Map<String, dynamic>? ?? const {};
    return DmMessage(
      id: j['id'] as String,
      senderId: j['senderId'] as String? ?? sender['id'] as String? ?? '',
      senderName: sender['displayName'] as String? ?? '',
      body: j['body'] as String? ?? '',
      imageUrl: j['imageUrl'] as String?,
      createdAt: _parseDateTime(j['createdAt']),
      readAt: j['readAt'] != null ? _parseDateTime(j['readAt']) : null,
    );
  }
}

class MessagingApi {
  final ApiClient _api;
  MessagingApi(this._api);

  Future<List<ChatSummary>> chats() async {
    final res = await _api.getList('/chats');
    return res.map(ChatSummary.fromJson).toList();
  }

  Future<List<DmMessage>> messages(
    String threadId, {
    int limit = 50,
    String? since,
    String? before,
  }) async {
    final res = await _api.getList(
      '/chats/$threadId/messages',
      query: {
        'limit': limit,
        if (since != null) 'since': since,
        if (before != null) 'before': before,
      },
    );
    return res.map(DmMessage.fromJson).toList();
  }

  Future<void> deleteMessage(String id) => _api.delete('/chats/messages/$id');
}

/// Global chats list, hydrated on chats tab open + focus.
final chatsListNotifier = ValueNotifier<List<ChatSummary>>(const []);
