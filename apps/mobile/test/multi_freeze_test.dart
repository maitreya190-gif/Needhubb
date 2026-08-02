import 'package:flutter_test/flutter_test.dart';
import 'package:needhub/models/need.dart';

Need makeTestNeed({
  int peopleNeeded = 1,
  int acceptedCount = 0,
  String status = 'OPEN',
}) {
  return Need(
    id: 'test_multi',
    title: 'Need 5 volunteers',
    description: 'Looking for 5 volunteers for community event.',
    category: 'connect',
    authorName: 'Test Author',
    authorInitials: 'TA',
    location: 'Nearby',
    createdAt: DateTime.now(),
    peopleNeeded: peopleNeeded,
    acceptedCount: acceptedCount,
    status: status,
  );
}

void main() {
  group('Multi-person Need freezing tests', () {
    test('single person need defaults to 0/1 accepted and is not fully frozen when open', () {
      final n = makeTestNeed(peopleNeeded: 1, acceptedCount: 0);
      expect(n.peopleNeeded, equals(1));
      expect(n.acceptedCount, equals(0));
      expect(n.isFullyFrozen, isFalse);
      expect(n.isFrozen, isFalse);
      expect(n.freezeProgressLabel, equals('0/1 Frozen'));
    });

    test('multi-person need stays open when partially accepted (2/5)', () {
      final n = makeTestNeed(peopleNeeded: 5, acceptedCount: 2, status: 'OPEN');
      expect(n.isFullyFrozen, isFalse);
      expect(n.isFrozen, isFalse);
      expect(n.freezeProgressLabel, equals('2/5 Frozen'));
    });

    test('accepting 1 out of 5 offers (1/5) keeps need open so poster can accept up to 5 offers', () {
      final n = makeTestNeed(peopleNeeded: 5, acceptedCount: 1, status: 'OPEN');
      expect(n.isFullyFrozen, isFalse);
      expect(n.isFrozen, isFalse);
      expect(n.freezeProgressLabel, equals('1/5 Frozen'));
    });

    test('multi-person need becomes fully frozen when accepted count meets quota (5/5)', () {
      final n = makeTestNeed(peopleNeeded: 5, acceptedCount: 5, status: 'FULFILLED');
      expect(n.isFullyFrozen, isTrue);
      expect(n.isFrozen, isTrue);
      expect(n.freezeProgressLabel, equals('5/5 Frozen'));
    });

    test('copyWith updates peopleNeeded and recalculates progress label', () {
      final n1 = makeTestNeed(peopleNeeded: 2, acceptedCount: 1, status: 'OPEN');
      expect(n1.freezeProgressLabel, equals('1/2 Frozen'));

      final n2 = n1.copyWith(peopleNeeded: 10);
      expect(n2.peopleNeeded, equals(10));
      expect(n2.acceptedCount, equals(1));
      expect(n2.freezeProgressLabel, equals('1/10 Frozen'));
      expect(n2.isFullyFrozen, isFalse);
    });
  });
}
