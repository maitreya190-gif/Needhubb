import 'package:flutter/foundation.dart';
import 'api_client.dart';

class PendingReview {
  final String needId;
  final String needTitle;
  final String counterpartyId;
  final String counterpartyName;
  final String? counterpartyAvatarUrl;

  const PendingReview({
    required this.needId,
    required this.needTitle,
    required this.counterpartyId,
    required this.counterpartyName,
    this.counterpartyAvatarUrl,
  });

  factory PendingReview.fromJson(Map<String, dynamic> j) {
    final c = j['counterparty'] as Map<String, dynamic>? ?? const {};
    final profile = c['profile'] as Map<String, dynamic>?;
    return PendingReview(
      needId: j['needId'] as String,
      needTitle: j['needTitle'] as String? ?? '',
      counterpartyId: c['id'] as String? ?? '',
      counterpartyName: c['displayName'] as String? ?? 'Someone',
      counterpartyAvatarUrl: profile?['avatarUrl'] as String?,
    );
  }
}

class ReviewsApi {
  final ApiClient _api;
  ReviewsApi(this._api);

  Future<int> submit({
    required String needId,
    required String revieweeId,
    required int rating,
    String? comment,
  }) async {
    final r = await _api.post('/reviews', {
      'needId': needId,
      'revieweeId': revieweeId,
      'rating': rating,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
    return (r['pointsAwarded'] as int?) ?? 0;
  }

  Future<List<PendingReview>> pending() async {
    final res = await _api.getList('/reviews/pending');
    return res.map(PendingReview.fromJson).toList();
  }

  Future<({double avg, int count, List<Map<String, dynamic>> reviews})> forUser(
      String userId) async {
    final r = await _api.get('/reviews/for/$userId');
    return (
      avg: ((r['avg'] as num?) ?? 0).toDouble(),
      count: (r['count'] as int?) ?? 0,
      reviews: ((r['reviews'] as List?) ?? const []).cast<Map<String, dynamic>>(),
    );
  }
}

final pendingReviewsNotifier =
    ValueNotifier<List<PendingReview>>(const []);
