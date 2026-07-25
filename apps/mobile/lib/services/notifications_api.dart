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

  /// Delete a single notification.
  Future<void> deleteOne(String id) =>
      _api.delete('/notifications/$id');

  /// Bulk clear notifications by range: 'day', 'week', or 'all'.
  Future<int> clearByRange(String range) async {
    final r = await _api.post('/notifications/clear', {'range': range});
    return (r['deleted'] as int?) ?? 0;
  }

  /// Delete selected notifications by their IDs.
  Future<int> clearSelected(List<String> ids) async {
    final r = await _api.post('/notifications/clear-selected', {'ids': ids});
    return (r['deleted'] as int?) ?? 0;
  }
}

final notificationsListNotifier = ValueNotifier<List<NhNotification>>([
  NhNotification(
    id: 'seed_notif_1',
    type: 'NEED_RESPONSE_RECEIVED',
    title: 'New Offer Received!',
    body: 'Aarav Kumar submitted an offer for "Need someone to drop off my laptop charger in HSR Sector 2"',
    refType: 'NEED',
    refId: 'earn_1',
    createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
  ),
  NhNotification(
    id: 'seed_notif_2',
    type: 'NEED_RESPONSE_RECEIVED',
    title: 'New Offer Received!',
    body: 'Priya Nair submitted an offer for "Looking for a tutor for Flutter state management & Riverpod"',
    refType: 'NEED',
    refId: 'earn_2',
    createdAt: DateTime.now().subtract(const Duration(hours: 1)),
  ),
  NhNotification(
    id: 'seed_notif_3',
    type: 'FRIEND_REQUEST_RECEIVED',
    title: 'Friend Request',
    body: 'Rohan Verma sent you a friend request.',
    refType: 'USER',
    refId: 'user_rohan',
    createdAt: DateTime.now().subtract(const Duration(hours: 3)),
  ),
]);

final unreadCountNotifier = ValueNotifier<int>(3);
