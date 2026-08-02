// Tests for the Impact League client models (defensive JSON parsing — this
// feature adds a lot of new response shapes, so a malformed/partial field
// must never crash a profile or leaderboard screen) and the two small,
// self-contained widgets: the permanent seasonal-badge row and the
// motivation-hint pill. Full-screen widgets (ImpactLeagueScreen,
// you_screen's _ImpactLeagueSection) depend on live network calls through
// riverpod providers and are exercised manually per the plan's verification
// steps instead of re-mocked here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needhub/services/league_api.dart';
import 'package:needhub/theme/tokens.dart';
import 'package:needhub/widgets/nh_motivation_hint.dart';
import 'package:needhub/widgets/nh_seasonal_badge.dart';

Widget wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 380, child: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  const t = NeedHubThemes.paper;

  group('model parsing is defensive', () {
    test('SeasonInfo.fromJson survives missing/malformed fields', () {
      final info = SeasonInfo.fromJson(const {});
      expect(info.seasonNumber, 0);
      expect(info.status, 'ACTIVE');
    });

    test('SeasonInfo.remaining is zero once endsAt has passed, never negative', () {
      final info = SeasonInfo.fromJson({
        'seasonNumber': 1,
        'year': 2026,
        'startsAt': '2020-01-01T00:00:00Z',
        'endsAt': '2020-04-01T00:00:00Z',
        'status': 'ARCHIVED',
      });
      expect(info.remaining, Duration.zero);
    });

    test('LeaderboardEntry.fromJson defaults missing numeric fields to 0', () {
      final entry = LeaderboardEntry.fromJson(const {'userId': 'u1'});
      expect(entry.rank, 0);
      expect(entry.seasonPoints, 0);
      expect(entry.lifetimePoints, 0);
      expect(entry.badgeId, isNull);
      expect(entry.displayName, 'Someone');
    });

    test('MyRank.fromJson parses a null rank and a nested motivation hint', () {
      final rank = MyRank.fromJson({
        'rank': null,
        'seasonPoints': 40,
        'lifetimePoints': 900,
        'nearestMilestone': {'label': 'Top 10', 'spotsAway': 3},
      });
      expect(rank.rank, isNull);
      expect(rank.nearestMilestone?.label, 'Top 10');
      expect(rank.nearestMilestone?.spotsAway, 3);
    });

    test('MyRank.fromJson tolerates a missing motivation hint entirely', () {
      final rank = MyRank.fromJson({'seasonPoints': 0, 'lifetimePoints': 0});
      expect(rank.nearestMilestone, isNull);
    });

    test('SeasonalBadge.listFrom ignores non-list input rather than throwing', () {
      expect(SeasonalBadge.listFrom(null), isEmpty);
      expect(SeasonalBadge.listFrom('not a list'), isEmpty);
    });

    test('LeagueAchievement.fromJson defaults earned to false and earnedAt to null', () {
      final a = LeagueAchievement.fromJson(const {'id': 'x', 'label': 'X'});
      expect(a.earned, false);
      expect(a.earnedAt, isNull);
    });

    test('LeagueAchievementProfile.fromJson tolerates a fully empty response', () {
      final profile = LeagueAchievementProfile.fromJson(const {});
      expect(profile.seasonalBadges, isEmpty);
      expect(profile.achievements, isEmpty);
      expect(profile.featuredAchievementIds, isEmpty);
    });

    test('SeasonArchive.fromJson handles a null season (season not yet ended)', () {
      final archive = SeasonArchive.fromJson(const {'season': null, 'rows': []});
      expect(archive.season, isNull);
      expect(archive.rows, isEmpty);
    });
  });

  group('NhSeasonalBadgeRow', () {
    testWidgets('shows an empty-state message with no badges', (tester) async {
      await tester.pumpWidget(wrap(const NhSeasonalBadgeRow(badges: [], t: t)));
      expect(find.textContaining('No seasonal badges yet'), findsOneWidget);
    });

    testWidgets('renders one seal per badge, newest season first', (tester) async {
      await tester.pumpWidget(wrap(const NhSeasonalBadgeRow(
        badges: [
          SeasonalBadge(badgeId: 'impact_pioneer', label: 'Impact Pioneer', seasonNumber: 1, year: 2026, rank: 3),
          SeasonalBadge(badgeId: 'impact_champion', label: 'Impact Champion', seasonNumber: 2, year: 2026, rank: 1),
        ],
        t: t,
      )));
      expect(find.byType(NhSeasonalBadgeSeal), findsNWidgets(2));
      // Season 2 (newer) should render before season 1 in the list order.
      final seals = tester.widgetList<NhSeasonalBadgeSeal>(find.byType(NhSeasonalBadgeSeal)).toList();
      expect(seals.first.badge.seasonNumber, 2);
    });

    testWidgets('tapping a seal shows season, year and rank', (tester) async {
      await tester.pumpWidget(wrap(const NhSeasonalBadgeRow(
        badges: [SeasonalBadge(badgeId: 'impact_champion', label: 'Impact Champion', seasonNumber: 3, year: 2027, rank: 1)],
        t: t,
      )));
      await tester.tap(find.byType(NhSeasonalBadgeSeal));
      await tester.pump();
      expect(find.textContaining('Season 3, 2027'), findsOneWidget);
      expect(find.textContaining('Rank #1'), findsOneWidget);
    });
  });

  group('NhMotivationHint', () {
    testWidgets('renders nothing when there is no hint', (tester) async {
      await tester.pumpWidget(wrap(const NhMotivationHint(hint: null, t: t)));
      expect(find.byType(Container), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('uses singular "spot" for exactly one spot away', (tester) async {
      await tester.pumpWidget(wrap(const NhMotivationHint(
        hint: MotivationHint(label: 'Top 5', spotsAway: 1),
        t: t,
      )));
      expect(find.text('1 spot from Top 5'), findsOneWidget);
    });

    testWidgets('uses plural "spots" for more than one', (tester) async {
      await tester.pumpWidget(wrap(const NhMotivationHint(
        hint: MotivationHint(label: 'Top 10', spotsAway: 4),
        t: t,
      )));
      expect(find.text('4 spots from Top 10'), findsOneWidget);
    });
  });
}
