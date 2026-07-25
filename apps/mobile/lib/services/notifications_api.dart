import 'package:flutter/foundation.dart';
import 'api_client.dart';

class NhNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final String? refType;
  final String? refId;
  final DateTime createdAt;
  final DateTime? readAt;

  const NhNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.refType,
    this.refId,
    required this.createdAt,
    this.readAt,
  });

  bool get isUnread => readAt == null;

  factory NhNotification.fromJson(Map<String, dynamic> j) => NhNotification(
        id: j['id'] as String,
        type: j['type'] as String? ?? 'UNKNOWN',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        refType: j['refType'] as String?,
        refId: j['refId'] as String?,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        readAt: j['readAt'] != null
            ? DateTime.tryParse(j['readAt'] as String)
            : null,
      );
}

class NotificationsApi {
  final ApiClient _api;
  NotificationsApi(this._api);

  Future<List<NhNotification>> list({int take = 30, String? before}) async {
    final res = await _api.getList(
      '/notifications',
      query: {'take': take, if (before != null) 'before': before},
    );
    return res.map(NhNotification.fromJson).toList();
  }

  Future<int> unreadCount() async {
    final r = await _api.get('/notifications/count');
    return (r['unread'] as int?) ?? 0;
  }

  Future<void> markRead(String id) =>
      _api.post('/notifications/$id/read', const {});

  Future<void> markAllRead() =>
      _api.post('/notifications/read-all', const {});
}

// ── Global notifiers ─────────────────────────────────────────────────────────

final notificationsListNotifier =
    ValueNotifier<List<NhNotification>>(const []);
final unreadCountNotifier = ValueNotifier<int>(0);
