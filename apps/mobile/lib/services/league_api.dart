import 'api_client.dart';

/// Current 3-month Impact League season — mirrors SeasonInfo in
/// lib/impact-league.ts. Season boundaries are the only thing about the
/// league that isn't derived; everything else is computed from data that
/// already existed before this feature shipped.
class SeasonInfo {
  final int seasonNumber;
  final int year;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;

  const SeasonInfo({
    required this.seasonNumber,
    required this.year,
    required this.startsAt,
    required this.endsAt,
    required this.status,
  });

  factory SeasonInfo.fromJson(Map<String, dynamic> j) => SeasonInfo(
        seasonNumber: (j['seasonNumber'] as num?)?.toInt() ?? 0,
        year: (j['year'] as num?)?.toInt() ?? DateTime.now().year,
        startsAt: DateTime.tryParse(j['startsAt'] as String? ?? '') ?? DateTime.now(),
        endsAt: DateTime.tryParse(j['endsAt'] as String? ?? '') ?? DateTime.now(),
        status: j['status'] as String? ?? 'ACTIVE',
      );

  Duration get remaining {
    final d = endsAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }
}

/// One row on a leaderboard — current, friends, or a past season's archive.
class LeaderboardEntry {
  final int rank;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int seasonPoints;
  final int lifetimePoints;
  final String? badgeId;

  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.seasonPoints,
    required this.lifetimePoints,
    this.badgeId,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
        rank: (j['rank'] as num?)?.toInt() ?? 0,
        userId: j['userId'] as String? ?? '',
        displayName: j['displayName'] as String? ?? 'Someone',
        avatarUrl: j['avatarUrl'] as String?,
        seasonPoints: (j['seasonPoints'] as num?)?.toInt() ?? 0,
        lifetimePoints: (j['lifetimePoints'] as num?)?.toInt() ?? 0,
        badgeId: j['badgeId'] as String?,
      );
}

/// A subtle nudge shown only when close to a notable rank threshold — never
/// a push notification, just one extra field on [MyRank].
class MotivationHint {
  final String label;
  final int spotsAway;

  const MotivationHint({required this.label, required this.spotsAway});

  factory MotivationHint.fromJson(Map<String, dynamic> j) => MotivationHint(
        label: j['label'] as String? ?? '',
        spotsAway: (j['spotsAway'] as num?)?.toInt() ?? 0,
      );
}

class MyRank {
  final int? rank;
  final int seasonPoints;
  final int lifetimePoints;
  final MotivationHint? nearestMilestone;

  const MyRank({
    this.rank,
    required this.seasonPoints,
    required this.lifetimePoints,
    this.nearestMilestone,
  });

  factory MyRank.fromJson(Map<String, dynamic> j) => MyRank(
        rank: (j['rank'] as num?)?.toInt(),
        seasonPoints: (j['seasonPoints'] as num?)?.toInt() ?? 0,
        lifetimePoints: (j['lifetimePoints'] as num?)?.toInt() ?? 0,
        nearestMilestone: j['nearestMilestone'] is Map
            ? MotivationHint.fromJson(Map<String, dynamic>.from(j['nearestMilestone'] as Map))
            : null,
      );
}

/// A permanent Hall of Impact entry — one of the top-5 finishers of a past
/// season, forever. Never changes after the season it belongs to ends.
class HallOfImpactEntry {
  final int seasonNumber;
  final int year;
  final int rank;
  final String badgeId;
  final String userId;
  final String displayName;
  final String? avatarUrl;

  const HallOfImpactEntry({
    required this.seasonNumber,
    required this.year,
    required this.rank,
    required this.badgeId,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });

  factory HallOfImpactEntry.fromJson(Map<String, dynamic> j) => HallOfImpactEntry(
        seasonNumber: (j['seasonNumber'] as num?)?.toInt() ?? 0,
        year: (j['year'] as num?)?.toInt() ?? 0,
        rank: (j['rank'] as num?)?.toInt() ?? 0,
        badgeId: j['badgeId'] as String? ?? '',
        userId: j['userId'] as String? ?? '',
        displayName: j['displayName'] as String? ?? 'Someone',
        avatarUrl: j['avatarUrl'] as String?,
      );
}

/// A permanent seasonal badge on a profile — one of the top-5 finishes a
/// user has ever had. Never expires, never re-evaluated.
class SeasonalBadge {
  final String badgeId;
  final String label;
  final int seasonNumber;
  final int year;
  final int rank;

  const SeasonalBadge({
    required this.badgeId,
    required this.label,
    required this.seasonNumber,
    required this.year,
    required this.rank,
  });

  factory SeasonalBadge.fromJson(Map<String, dynamic> j) => SeasonalBadge(
        badgeId: j['badgeId'] as String? ?? '',
        label: j['label'] as String? ?? '',
        seasonNumber: (j['seasonNumber'] as num?)?.toInt() ?? 0,
        year: (j['year'] as num?)?.toInt() ?? 0,
        rank: (j['rank'] as num?)?.toInt() ?? 0,
      );

  static List<SeasonalBadge> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => SeasonalBadge.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }
}

/// A milestone achievement — participation, ranking, or lifetime-point based.
/// Locked achievements are included on purpose: the goal is visible, not
/// hidden, same reasoning as the earned-badges row elsewhere in the app.
class LeagueAchievement {
  final String id;
  final String label;
  final String description;
  final String category;
  final bool earned;
  final DateTime? earnedAt;

  const LeagueAchievement({
    required this.id,
    required this.label,
    required this.description,
    required this.category,
    required this.earned,
    this.earnedAt,
  });

  factory LeagueAchievement.fromJson(Map<String, dynamic> j) => LeagueAchievement(
        id: j['id'] as String? ?? '',
        label: j['label'] as String? ?? '',
        description: j['description'] as String? ?? '',
        category: j['category'] as String? ?? 'participation',
        earned: j['earned'] as bool? ?? false,
        earnedAt: j['earnedAt'] is String ? DateTime.tryParse(j['earnedAt'] as String) : null,
      );

  static List<LeagueAchievement> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => LeagueAchievement.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }
}

/// Everything shown on a profile's Achievement Showcase: permanent seasonal
/// badges, derived milestone achievements, and which of them (up to 3) this
/// user has chosen to feature.
class LeagueAchievementProfile {
  final List<SeasonalBadge> seasonalBadges;
  final List<LeagueAchievement> achievements;
  final List<String> featuredAchievementIds;

  const LeagueAchievementProfile({
    required this.seasonalBadges,
    required this.achievements,
    required this.featuredAchievementIds,
  });

  factory LeagueAchievementProfile.fromJson(Map<String, dynamic> j) => LeagueAchievementProfile(
        seasonalBadges: SeasonalBadge.listFrom(j['seasonalBadges']),
        achievements: LeagueAchievement.listFrom(j['achievements']),
        featuredAchievementIds: ((j['featuredAchievementIds'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
      );
}

class SeasonArchive {
  final SeasonInfo? season;
  final List<LeaderboardEntry> rows;

  const SeasonArchive({this.season, required this.rows});

  factory SeasonArchive.fromJson(Map<String, dynamic> j) => SeasonArchive(
        season: j['season'] is Map ? SeasonInfo.fromJson(Map<String, dynamic>.from(j['season'] as Map)) : null,
        rows: ((j['rows'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => LeaderboardEntry.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );
}

class LeagueApi {
  final ApiClient _api;
  LeagueApi(this._api);

  Future<SeasonInfo> season() async {
    return SeasonInfo.fromJson(await _api.get('/league/season'));
  }

  Future<List<LeaderboardEntry>> leaderboard({String scope = 'global', int? take}) async {
    final query = <String>['scope=$scope', if (take != null) 'take=$take'];
    final res = await _api.get('/league/leaderboard?${query.join('&')}');
    final list = (res['rows'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((m) => LeaderboardEntry.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<MyRank> myRank() async {
    return MyRank.fromJson(await _api.get('/league/me'));
  }

  Future<SeasonArchive> archive(int seasonNumber) async {
    return SeasonArchive.fromJson(await _api.get('/league/archive/$seasonNumber'));
  }

  Future<List<HallOfImpactEntry>> hallOfImpact() async {
    final res = await _api.get('/league/hall-of-impact');
    final list = (res['entries'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((m) => HallOfImpactEntry.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<LeagueAchievementProfile> achievementsFor(String userId) async {
    return LeagueAchievementProfile.fromJson(await _api.get('/league/achievements/$userId'));
  }

  /// Chooses up to 3 achievements/badges to showcase — the server silently
  /// drops unknown ids and enforces the cap, this just reflects what came
  /// back.
  Future<List<String>> setFeatured(List<String> achievementIds) async {
    final res = await _api.patch('/league/featured', {'achievementIds': achievementIds});
    return ((res['featuredAchievementIds'] as List?) ?? const []).whereType<String>().toList();
  }
}
