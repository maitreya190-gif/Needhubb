import 'package:flutter/foundation.dart';
import '../models/need.dart';
import 'api_client.dart';

/// Result of a feed fetch — includes the ranker metadata so the UI can badge
/// "AI-ranked" when embeddings fired.
class FeedResult {
  final List<Need> needs;
  final String ranker; // 'embeddings' | 'heuristic'
  final String sort; // 'smart' | 'newest' | 'distance'
  const FeedResult(
      {required this.needs, required this.ranker, required this.sort});
}

class NeedsApi {
  final ApiClient _api;
  NeedsApi(this._api);

  /// Fetch the ranked feed. Backend uses the caller's profile (interests + lat/lng)
  /// to score each need semantically. Query params override profile fields.
  Future<FeedResult> feed({
    String? type, // 'EARN' | 'CONNECT'
    double? distanceKm,
    double? lat,
    double? lng,
    int? minBudget,
    int? maxBudget,
    List<String>? interests,
    List<String>? genders,
    String sort = 'smart',
    int take = 60,
    int skip = 0,
  }) async {
    final res = await _api.get('/needs?${_qs({
          if (type != null) 'type': type,
          if (distanceKm != null) 'distanceKm': distanceKm,
          if (lat != null) 'lat': lat,
          if (lng != null) 'lng': lng,
          if (minBudget != null) 'minBudget': minBudget,
          if (maxBudget != null) 'maxBudget': maxBudget,
          if (interests != null && interests.isNotEmpty)
            'interests': interests.join(','),
          if (genders != null && genders.isNotEmpty)
            'genders': genders.join(','),
          'sort': sort,
          'take': take,
          'skip': skip,
        })}');

    final list =
        ((res['needs'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final needs = list.map(_needFromJson).toList();
    return FeedResult(
      needs: needs,
      ranker: (res['ranker'] as String?) ?? 'heuristic',
      sort: (res['sort'] as String?) ?? sort,
    );
  }

  Future<Need> getById(String id) async {
    final res = await _api.get('/needs/$id');
    return _needFromJson(res);
  }
}

String _qs(Map<String, dynamic> params) {
  return params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent('${e.value}')}')
      .join('&');
}

Need _needFromJson(Map<String, dynamic> j) {
  final poster = j['poster'] as Map<String, dynamic>? ?? const {};
  final posterProfile = poster['profile'] as Map<String, dynamic>? ?? const {};
  final needType = (j['needType'] as String? ?? 'CONNECT').toLowerCase();
  final category = needType == 'earn' ? 'earn' : 'connect';
  final name = poster['displayName'] as String? ?? 'Someone';
  final initials = _initials(name);
  final distance =
      j['_distanceKm'] is num ? (j['_distanceKm'] as num).toDouble() : null;
  final createdIso = j['createdAt'] as String?;
  final createdAt = createdIso != null
      ? (DateTime.tryParse(createdIso) ?? DateTime.now())
      : DateTime.now();
  final profile = poster['profile'] as Map<String, dynamic>? ?? const {};
  final posterFaceVerified = profile['faceVerifiedAt'] != null;

  final posterInterestsRaw = profile['interests'];
  final posterInterests = posterInterestsRaw is List
      ? posterInterestsRaw
          .map((pi) {
            if (pi is Map && pi['interest'] is Map) {
              return (pi['interest'] as Map)['label']?.toString();
            }
            return null;
          })
          .whereType<String>()
          .toList()
      : const <String>[];

  final personalityTraits = profile['personalityTraits'];

  return Need(
    id: j['id'] as String,
    posterId: poster['id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    description: j['description'] as String? ?? '',
    category: category,
    authorName: name,
    authorInitials: initials,
    location: j['locationText'] as String? ?? 'Nearby',
    distanceKm: distance,
    createdAt: createdAt,
    budgetMin: (j['budgetMin'] as num?)?.toInt(),
    budgetMax: (j['budgetMax'] as num?)?.toInt(),
    tags: _tagsFor(j),
    posterAvatarUrl: posterProfile['avatarUrl'] as String?,
    posterFaceVerified: posterFaceVerified,
    offerCount: (j['offerCount'] as num?)?.toInt() ?? 0,
    posterBio: profile['bio'] as String?,
    posterInterests: posterInterests,
    posterPersonalityTraits: personalityTraits is Map
        ? Map<String, dynamic>.from(personalityTraits)
        : null,
    posterPersonalityNickname: profile['personalityNickname'] as String?,
  );
}

List<String> _tagsFor(Map<String, dynamic> j) {
  final tags = <String>[];
  final earn = j['earnCategory'] as String?;
  final connect = j['connectCategory'] as String?;
  if (earn != null) tags.add(earn.toLowerCase().replaceAll('_', ' '));
  if (connect != null) tags.add(connect.toLowerCase().replaceAll('_', ' '));
  return tags;
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts[0].isEmpty) return '?';
  if (parts.length == 1) {
    return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
  }
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}

// ── Global feed state ─────────────────────────────────────────────────────────

/// The ranked feed hydrated from the API. Feed screens read from this notifier
/// so any change (initial load, refresh, filter change) triggers a rebuild.
///
/// Initial value = the mock needs, so the UI is never empty pre-fetch and
/// pre-login. On first successful fetch, the mock data is replaced.
final feedNeedsNotifier = ValueNotifier<List<Need>>(mockNeeds);

/// 'embeddings' when semantic ML ranking was used, 'heuristic' when it fell
/// back to substring matching. UI can badge the feed with a small "AI-ranked"
/// indicator when this is 'embeddings'.
final feedRankerNotifier = ValueNotifier<String>('heuristic');
