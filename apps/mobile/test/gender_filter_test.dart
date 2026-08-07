import 'package:flutter_test/flutter_test.dart';
import 'package:needhub/models/user_state.dart';
import 'package:needhub/screens/hub/tabs/feed_tab.dart';
import 'package:needhub/services/needs_api.dart';

Map<String, dynamic> feedNeed(String id, String? gender) => {
      'id': id,
      'title': 'Need $id',
      'description': 'desc',
      'needType': 'EARN',
      'status': 'OPEN',
      'createdAt': '2026-03-01T10:00:00.000Z',
      'poster': {
        'id': 'u$id',
        'displayName': 'Poster $id',
        'profile': {
          'avatarUrl': null,
          if (gender != null) 'gender': gender,
        },
      },
    };

void main() {
  // Regression: the gender filter appeared to do nothing because stored
  // values ranged over "male", "Male" and "M" while the chips always send
  // "Male". Matching is now canonicalised on both sides.

  test('every stored gender spelling matches its chip', () {
    // Every way gender is actually written across the codebase's history.
    final maleVariants = ['male', 'Male', 'MALE', ' Male ', 'M', 'm', 'man'];
    final femaleVariants = [
      'female',
      'Female',
      'FEMALE',
      ' female ',
      'F',
      'woman'
    ];

    for (final v in maleVariants) {
      final needs = [needFromSocketData(feedNeed('x', v))];
      expect(
        filterAndSortNeeds(needs, const FeedFilter(genders: {'Male'})).length,
        1,
        reason: 'stored "$v" should match the Male chip',
      );
      expect(
        filterAndSortNeeds(needs, const FeedFilter(genders: {'Female'})),
        isEmpty,
        reason: 'stored "$v" must NOT match the Female chip',
      );
    }

    for (final v in femaleVariants) {
      final needs = [needFromSocketData(feedNeed('x', v))];
      expect(
        filterAndSortNeeds(needs, const FeedFilter(genders: {'Female'})).length,
        1,
        reason: 'stored "$v" should match the Female chip',
      );
    }
  });

  test('non-binary variants match', () {
    for (final v in ['Non-binary', 'non binary', 'nonbinary', 'NB']) {
      final needs = [needFromSocketData(feedNeed('x', v))];
      expect(
        filterAndSortNeeds(needs, const FeedFilter(genders: {'Non-binary'}))
            .length,
        1,
        reason: 'stored "$v" should match the Non-binary chip',
      );
    }
  });

  test('mixed feed splits correctly by gender', () {
    final needs = [
      needFromSocketData(feedNeed('m1', 'male')),
      needFromSocketData(feedNeed('f1', 'Female')),
      needFromSocketData(feedNeed('m2', 'M')),
      needFromSocketData(feedNeed('nb', 'Non-binary')),
      needFromSocketData(feedNeed('none', null)),
    ];
    expect(
      filterAndSortNeeds(needs, const FeedFilter(genders: {'Male'}))
          .map((n) => n.id)
          .toSet(),
      {'m1', 'm2'},
    );
    expect(
      filterAndSortNeeds(needs, const FeedFilter(genders: {'Female'}))
          .map((n) => n.id)
          .toSet(),
      {'f1'},
    );
    // Selecting both widens to the union.
    expect(
      filterAndSortNeeds(needs, const FeedFilter(genders: {'Male', 'Female'}))
          .map((n) => n.id)
          .toSet(),
      {'m1', 'm2', 'f1'},
    );
    // A poster with no gender never satisfies an explicit gender filter.
    expect(
      filterAndSortNeeds(needs, const FeedFilter(genders: {'Male'}))
          .map((n) => n.id),
      isNot(contains('none')),
    );
  });

  test('no gender filter leaves everyone in, including unset', () {
    final needs = [
      needFromSocketData(feedNeed('m', 'male')),
      needFromSocketData(feedNeed('none', null)),
    ];
    expect(filterAndSortNeeds(needs, const FeedFilter()).length, 2);
  });
}
