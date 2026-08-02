// Sharing exposes a Need on a public, unauthenticated URL, so the rule that
// decides *whether* a Need can be shared is the part worth pinning here —
// it must stay in lockstep with isShareable() in the API's lib/share-card.ts.
// The card widget is checked for the same thing visually: it renders public
// fields only, and never a coordinate.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needhub/models/need.dart';
import 'package:needhub/widgets/nh_share_need_sheet.dart';
import 'package:needhub/widgets/nh_shareable_need_card.dart';

Need buildNeed({
  String status = 'OPEN',
  bool isUrgent = false,
  DateTime? deadline,
  int? budgetMin,
  int? budgetMax,
  String location = 'Koramangala',
}) {
  return Need(
    id: 'need-1',
    posterId: 'poster-1',
    title: 'Need a Flutter tutor',
    description: 'Help with state management this weekend.',
    category: 'earn',
    authorName: 'Aarav',
    authorInitials: 'AA',
    location: location,
    createdAt: DateTime.now(),
    status: status,
    isUrgent: isUrgent,
    deadline: deadline,
    budgetMin: budgetMin,
    budgetMax: budgetMax,
    lat: 12.9352,
    lng: 77.6245,
  );
}

Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('canShareNeed — mirrors the API eligibility rule', () {
    test('an open need is shareable', () {
      expect(canShareNeed(buildNeed()), isTrue);
    });

    test('an in-progress need is still shareable', () {
      expect(canShareNeed(buildNeed(status: 'IN_PROGRESS')), isTrue);
    });

    test('finished, closed and expired needs are not shareable', () {
      for (final status in ['FULFILLED', 'CLOSED', 'EXPIRED']) {
        expect(canShareNeed(buildNeed(status: status)), isFalse,
            reason: '$status should not be shareable');
      }
    });

    test('an urgent need past its deadline is not shareable', () {
      final need = buildNeed(
        isUrgent: true,
        deadline: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(canShareNeed(need), isFalse);
    });

    test('an urgent need still within its deadline is shareable', () {
      final need = buildNeed(
        isUrgent: true,
        deadline: DateTime.now().add(const Duration(hours: 6)),
      );
      expect(canShareNeed(need), isTrue);
    });

    test('a stale deadline on a non-urgent need does not block sharing', () {
      final need = buildNeed(
        deadline: DateTime.now().subtract(const Duration(days: 5)),
      );
      expect(canShareNeed(need), isTrue);
    });

    test('status matching is case-insensitive', () {
      expect(canShareNeed(buildNeed(status: 'open')), isTrue);
    });
  });

  group('NhShareableNeedCard', () {
    testWidgets('renders the public need details and NeedHub branding',
        (tester) async {
      await tester.pumpWidget(wrap(NhShareableNeedCard(
        need: buildNeed(budgetMin: 500, budgetMax: 900),
        shareUrl: 'https://needhub.example/n/need-1',
      )));

      expect(find.text('Need a Flutter tutor'), findsOneWidget);
      expect(find.text('NeedHub'), findsOneWidget);
      expect(find.text('Aarav'), findsOneWidget);
      expect(find.text('Koramangala'), findsOneWidget);
      expect(find.text('₹500–₹900'), findsOneWidget);
      expect(find.text('Earn'), findsOneWidget);
    });

    testWidgets('never renders raw coordinates', (tester) async {
      await tester.pumpWidget(wrap(NhShareableNeedCard(
        need: buildNeed(),
        shareUrl: 'https://needhub.example/n/need-1',
      )));

      expect(find.textContaining('12.93'), findsNothing);
      expect(find.textContaining('77.62'), findsNothing);
    });

    testWidgets('shows an Urgent chip only for urgent needs', (tester) async {
      await tester.pumpWidget(wrap(NhShareableNeedCard(
        need: buildNeed(),
        shareUrl: 'https://needhub.example/n/need-1',
      )));
      expect(find.text('Urgent'), findsNothing);

      await tester.pumpWidget(wrap(NhShareableNeedCard(
        need: buildNeed(
          isUrgent: true,
          deadline: DateTime.now().add(const Duration(hours: 5)),
        ),
        shareUrl: 'https://needhub.example/n/need-1',
      )));
      expect(find.text('Urgent'), findsOneWidget);
    });

    testWidgets('omits the budget chip when the need has no budget',
        (tester) async {
      await tester.pumpWidget(wrap(NhShareableNeedCard(
        need: buildNeed(),
        shareUrl: 'https://needhub.example/n/need-1',
      )));
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets('collapses an equal min/max budget to a single value',
        (tester) async {
      await tester.pumpWidget(wrap(NhShareableNeedCard(
        need: buildNeed(budgetMin: 700, budgetMax: 700),
        shareUrl: 'https://needhub.example/n/need-1',
      )));
      expect(find.text('₹700'), findsOneWidget);
    });

    testWidgets('lays out a long title and description without overflowing',
        (tester) async {
      await tester.pumpWidget(wrap(NhShareableNeedCard(
        need: Need(
          id: 'n', posterId: 'p',
          title: 'A very long need title ' * 6,
          description: 'A very long description that keeps going ' * 12,
          category: 'connect',
          authorName: 'Someone With A Rather Long Display Name',
          authorInitials: 'SW',
          location: 'A fairly long neighbourhood name, Bengaluru',
          createdAt: DateTime.now(),
          status: 'OPEN',
        ),
        shareUrl: 'https://needhub.example/n/n',
      )));

      expect(tester.takeException(), isNull);
    });
  });
}
