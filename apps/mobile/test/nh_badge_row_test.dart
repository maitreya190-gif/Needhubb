// Widget tests for the badge row.
//
// Badges are new UI on two profile screens, and the failure mode for a
// horizontal row of fixed-size tiles is layout — a RenderFlex overflow, or a
// long label blowing out its box. `pumpWidget` surfaces those as test failures,
// which is the part that reading the code cannot tell you.
//
// The behavioural rule being pinned: this widget renders exactly what the
// server said and never decides for itself that something is earned. The
// version it replaced hardcoded three earned badges for every new user.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needhub/services/profiles_api.dart';
import 'package:needhub/theme/tokens.dart';
import 'package:needhub/widgets/nh_badge_row.dart';

ProfileBadge badge(
  String id, {
  String? label,
  bool earned = false,
  String description = 'Do the thing',
  String group = 'helping',
}) {
  return ProfileBadge(
    id: id,
    label: label ?? id,
    description: description,
    group: group,
    earned: earned,
  );
}

Widget wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 380, child: child),
    ),
  );
}

void main() {
  // Presets live on NeedHubThemes, not NeedHubTokens — the latter has a
  // `paper` instance field that would collide (see the note in tokens.dart).
  const t = NeedHubThemes.paper;

  group('rendering', () {
    testWidgets('renders a tile per badge, earned and locked alike',
        (tester) async {
      await tester.pumpWidget(wrap(NhBadgeRow(
        badges: [
          badge('face_verified', label: 'Face Verified', earned: true),
          badge('first_help', label: 'First Help', earned: true),
          badge('veteran', label: 'Veteran'),
        ],
        t: t,
      )));

      expect(find.text('Face Verified'), findsOneWidget);
      expect(find.text('First Help'), findsOneWidget);
      expect(find.text('Veteran'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a full set of 12 badges lays out without overflowing',
        (tester) async {
      // The real vocabulary is 12 badges in a horizontal scroller — the exact
      // case most likely to blow the layout.
      await tester.pumpWidget(wrap(NhBadgeRow(
        badges: List.generate(
          12,
          (i) => badge('b$i', label: 'Badge $i', earned: i.isEven),
        ),
        t: t,
      )));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an over-long label is clipped rather than overflowing',
        (tester) async {
      await tester.pumpWidget(wrap(NhBadgeRow(
        badges: [
          badge('x', label: 'An Extremely Long Badge Name That Will Not Fit'),
        ],
        t: t,
      )));
      expect(tester.takeException(), isNull);
    });
  });

  group('showLocked', () {
    testWidgets('own profile shows locked badges as goals', (tester) async {
      await tester.pumpWidget(wrap(NhBadgeRow(
        badges: [
          badge('a', label: 'Earned One', earned: true),
          badge('b', label: 'Locked One'),
        ],
        t: t,
      )));

      expect(find.text('Earned One'), findsOneWidget);
      expect(find.text('Locked One'), findsOneWidget);
    });

    testWidgets("another person's profile hides locked badges", (tester) async {
      await tester.pumpWidget(wrap(NhBadgeRow(
        badges: [
          badge('a', label: 'Earned One', earned: true),
          badge('b', label: 'Locked One'),
        ],
        t: t,
        showLocked: false,
      )));

      expect(find.text('Earned One'), findsOneWidget);
      expect(find.text('Locked One'), findsNothing);
    });
  });

  group('empty states', () {
    testWidgets('a brand new user sees an empty state, never a fake badge',
        (tester) async {
      // The regression this guards: the old row padded itself with hardcoded
      // "First Help" / "5-Star" entries marked as earned.
      await tester.pumpWidget(wrap(const NhBadgeRow(badges: [], t: t)));

      expect(find.textContaining('No badges yet'), findsOneWidget);
      expect(find.text('First Help'), findsNothing);
      expect(find.text('5-Star'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('someone with only locked badges shows nothing to a viewer',
        (tester) async {
      await tester.pumpWidget(wrap(NhBadgeRow(
        badges: [badge('a', label: 'Locked')],
        t: t,
        showLocked: false,
      )));

      expect(find.text('Locked'), findsNothing);
      expect(find.textContaining('No badges earned yet'), findsOneWidget);
    });
  });

  group('tapping explains what a badge takes', () {
    testWidgets('a locked badge shows its requirement', (tester) async {
      await tester.pumpWidget(wrap(NhBadgeRow(
        badges: [
          badge('veteran',
              label: 'Veteran', description: 'Complete 25 needs for others'),
        ],
        t: t,
      )));

      await tester.tap(find.text('Veteran'));
      await tester.pump();

      expect(find.textContaining('Complete 25 needs for others'),
          findsOneWidget);
    });

    testWidgets('an earned badge reads as earned', (tester) async {
      await tester.pumpWidget(wrap(NhBadgeRow(
        badges: [badge('first_help', label: 'First Help', earned: true)],
        t: t,
      )));

      await tester.tap(find.text('First Help'));
      await tester.pump();

      expect(find.textContaining('earned'), findsOneWidget);
    });
  });

  group('icons', () {
    test('every known badge id maps to a specific icon', () {
      const ids = [
        'email_verified', 'phone_verified', 'face_verified', 'fully_verified',
        'first_help', 'helping_hand', 'reliable', 'veteran', 'follows_through',
        'five_star', 'well_reviewed', 'certified', 'community_builder',
      ];
      final fallback = NhBadgeRow.iconFor('definitely_not_a_badge');
      for (final id in ids) {
        expect(NhBadgeRow.iconFor(id), isNot(fallback), reason: 'icon for $id');
      }
    });

    test('an unknown id still gets an icon rather than crashing', () {
      expect(NhBadgeRow.iconFor('brand_new_badge'), isA<IconData>());
    });
  });
}
