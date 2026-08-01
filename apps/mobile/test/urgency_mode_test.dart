// Urgency Mode is additive on the mobile side too: a Need with isUrgent=false
// (every need before this shipped, and every need that never opts in) must
// render exactly as it always did. These pin the model logic and the badge
// widget's non-urgent no-op, mirroring the API-side guarantee in
// apps/api/src/lib/urgency.ts.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:needhub/models/need.dart';
import 'package:needhub/widgets/nh_urgent_badge.dart';

Need makeNeed({
  bool isUrgent = false,
  DateTime? deadline,
  String status = 'OPEN',
}) {
  return Need(
    id: 'n1',
    title: 'Test need',
    description: 'desc',
    category: 'earn',
    authorName: 'Someone',
    authorInitials: 'S',
    location: 'Nearby',
    createdAt: DateTime.now(),
    isUrgent: isUrgent,
    deadline: deadline,
    status: status,
  );
}

void main() {
  group('Need.isFrozen / isExpiredUrgent', () {
    test('a non-urgent OPEN need is not frozen', () {
      expect(makeNeed().isFrozen, isFalse);
      expect(makeNeed().isExpiredUrgent, isFalse);
    });

    test('EXPIRED status is both frozen and recognised as expired-urgent', () {
      final n = makeNeed(isUrgent: true, status: 'EXPIRED');
      expect(n.isFrozen, isTrue);
      expect(n.isExpiredUrgent, isTrue);
    });

    test('FULFILLED is frozen but not expired-urgent — done, not abandoned', () {
      final n = makeNeed(isUrgent: true, status: 'FULFILLED');
      expect(n.isFrozen, isTrue);
      expect(n.isExpiredUrgent, isFalse);
    });
  });

  group('Need.urgencyCountdown', () {
    test('null for a non-urgent need, however close the deadline field is', () {
      final n = makeNeed(
          deadline: DateTime.now().add(const Duration(minutes: 5)));
      expect(n.urgencyCountdown, isNull);
    });

    test('null once the deadline has passed', () {
      final n = makeNeed(
          isUrgent: true,
          deadline: DateTime.now().subtract(const Duration(hours: 1)));
      expect(n.urgencyCountdown, isNull);
    });

    test('null with no deadline set at all', () {
      expect(makeNeed(isUrgent: true).urgencyCountdown, isNull);
    });

    test('shows minutes under an hour out', () {
      final n = makeNeed(
          isUrgent: true,
          deadline: DateTime.now().add(const Duration(minutes: 30)));
      expect(n.urgencyCountdown, contains('m left'));
    });

    test('shows hours under a day out', () {
      final n = makeNeed(
          isUrgent: true,
          deadline: DateTime.now().add(const Duration(hours: 5)));
      expect(n.urgencyCountdown, contains('h left'));
    });

    test('shows days at a day or more out', () {
      final n = makeNeed(
          isUrgent: true,
          deadline: DateTime.now().add(const Duration(days: 2)));
      expect(n.urgencyCountdown, contains('d left'));
    });
  });

  group('NhUrgentBadge', () {
    Widget wrap(Widget child) =>
        MaterialApp(home: Scaffold(body: SizedBox(width: 200, child: child)));

    testWidgets('renders nothing for a non-urgent need', (tester) async {
      await tester.pumpWidget(wrap(NhUrgentBadge(need: makeNeed())));
      expect(find.byType(Container), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders nothing once the deadline has passed', (tester) async {
      final n = makeNeed(
          isUrgent: true,
          deadline: DateTime.now().subtract(const Duration(minutes: 1)));
      await tester.pumpWidget(wrap(NhUrgentBadge(need: n)));
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('renders the countdown for an active urgent need', (tester) async {
      final n = makeNeed(
          isUrgent: true,
          deadline: DateTime.now().add(const Duration(hours: 3)));
      await tester.pumpWidget(wrap(NhUrgentBadge(need: n)));
      expect(find.textContaining('h left'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact mode does not throw and still shows the countdown',
        (tester) async {
      final n = makeNeed(
          isUrgent: true,
          deadline: DateTime.now().add(const Duration(hours: 3)));
      await tester.pumpWidget(wrap(NhUrgentBadge(need: n, compact: true)));
      expect(find.textContaining('h left'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
