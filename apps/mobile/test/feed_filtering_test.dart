// Regression tests for the Explore/Earn/Connect feed filters.
//
// This logic has been re-broken several times, in ways that were invisible
// until someone tapped through the app: a distance slider labelled "Any" that
// still cut at 50km, chips that widened results instead of narrowing them, a
// sort option that did nothing, "Art" matching "Martial". Each test below pins
// one of those behaviours.

import 'package:flutter_test/flutter_test.dart';
import 'package:needhub/models/need.dart';
import 'package:needhub/models/user_state.dart';
import 'package:needhub/screens/hub/tabs/feed_tab.dart';

/// Minimal need builder — only the fields the filters actually read.
Need makeNeed(
  String id, {
  String title = 'A need',
  String description = 'Some description',
  double? distanceKm,
  int? budgetMin,
  String? posterGender,
  List<String> tags = const [],
  List<String> posterInterests = const [],
  DateTime? createdAt,
}) {
  return Need(
    id: id,
    title: title,
    description: description,
    category: 'earn',
    authorName: 'Test User',
    authorInitials: 'TU',
    location: 'Bangalore',
    distanceKm: distanceKm,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    budgetMin: budgetMin,
    tags: tags,
    posterGender: posterGender,
    posterInterests: posterInterests,
  );
}

List<String> idsOf(List<Need> needs) => needs.map((n) => n.id).toList();

void main() {
  group('no filters applied', () {
    test('an untouched filter excludes nothing', () {
      final needs = [
        makeNeed('a', distanceKm: 2),
        makeNeed('b', distanceKm: 104),
        makeNeed('c'), // distance unknown
      ];
      final result = filterAndSortNeeds(needs, const FeedFilter());
      expect(result.length, 3);
    });

    test('default sort is newest first', () {
      final needs = [
        makeNeed('old', createdAt: DateTime(2026, 1, 1)),
        makeNeed('newest', createdAt: DateTime(2026, 3, 1)),
        makeNeed('middle', createdAt: DateTime(2026, 2, 1)),
      ];
      expect(idsOf(filterAndSortNeeds(needs, const FeedFilter())),
          ['newest', 'middle', 'old']);
    });
  });

  group('distance', () {
    // The slider's top notch reads "50+ km (Any)". It once still cut at
    // exactly 50km, which silently hid nearly the whole feed by default.
    test('50 means any distance, not a 50km cut', () {
      final needs = [makeNeed('far', distanceKm: 104)];
      final result =
          filterAndSortNeeds(needs, const FeedFilter(maxDistanceKm: 50));
      expect(idsOf(result), ['far']);
    });

    test('a real limit excludes needs beyond it', () {
      final needs = [
        makeNeed('near', distanceKm: 4),
        makeNeed('far', distanceKm: 104),
      ];
      final result =
          filterAndSortNeeds(needs, const FeedFilter(maxDistanceKm: 10));
      expect(idsOf(result), ['near']);
    });

    test('needs with unknown distance are kept, not silently dropped', () {
      final needs = [makeNeed('unknown')];
      final result =
          filterAndSortNeeds(needs, const FeedFilter(maxDistanceKm: 10));
      expect(idsOf(result), ['unknown']);
    });
  });

  group('budget', () {
    test('minBudget excludes cheaper needs and needs with no budget', () {
      final needs = [
        makeNeed('rich', budgetMin: 1000),
        makeNeed('cheap', budgetMin: 100),
        makeNeed('unpaid'),
      ];
      final result =
          filterAndSortNeeds(needs, const FeedFilter(minBudget: 500));
      expect(idsOf(result), ['rich']);
    });

    test('maxBudget excludes needs above the ceiling', () {
      final needs = [
        makeNeed('rich', budgetMin: 5000),
        makeNeed('modest', budgetMin: 400),
      ];
      final result =
          filterAndSortNeeds(needs, const FeedFilter(maxBudget: 1000));
      expect(idsOf(result), ['modest']);
    });
  });

  group('gender', () {
    test('an explicit gender filter excludes posters with no gender set', () {
      final needs = [
        makeNeed('female', posterGender: 'Female'),
        makeNeed('male', posterGender: 'Male'),
        makeNeed('unset'),
      ];
      final result =
          filterAndSortNeeds(needs, FeedFilter(genders: const {'Female'}));
      expect(idsOf(result), ['female']);
    });

    test('gender comparison ignores case and punctuation', () {
      final needs = [makeNeed('nb', posterGender: 'Non-binary')];
      final result =
          filterAndSortNeeds(needs, FeedFilter(genders: const {'non binary'}));
      expect(idsOf(result), ['nb']);
    });
  });

  group('termMatches', () {
    test('matches whole words, not substrings inside other words', () {
      // The original bug: bidirectional substring matching meant "Art" hit
      // "Martial" (m-ART-ial) and "Java" hit "JavaScript".
      expect(termMatches('Martial law seminar', 'Art'), isFalse);
      expect(termMatches('Java developer needed', 'JavaScript'), isFalse);
      expect(termMatches('Carpentry work', 'Art'), isFalse);
    });

    test('a standalone word still matches even next to a near-miss word', () {
      // "Martial arts" does match "Art" — but via the separate word "arts",
      // not by reaching inside "Martial". That distinction is the whole fix.
      expect(termMatches('Martial arts club', 'Art'), isTrue);
    });

    test('matches a word inside a longer phrase', () {
      expect(termMatches('Join our local sports groups', 'Sports'), isTrue);
    });

    test('tolerates plurals in either direction', () {
      expect(termMatches('Movie night', 'Movies'), isTrue);
      expect(termMatches('Chess games', 'Game'), isTrue);
    });

    test('multi-word terms match as a contiguous phrase', () {
      expect(termMatches('Need help with UI design work', 'UI Design'), isTrue);
      expect(termMatches('Design a UI eventually', 'UI Design'), isFalse);
    });

    test('empty terms never match', () {
      expect(termMatches('anything', ''), isFalse);
      expect(termMatches('', 'Flutter'), isFalse);
    });
  });

  group('chips combine as a strict AND', () {
    test('a need must satisfy every selected chip', () {
      final needs = [
        makeNeed('both', tags: const ['Flutter', 'Tutoring']),
        makeNeed('onlyFlutter', tags: const ['Flutter']),
        makeNeed('onlyTutoring', tags: const ['Tutoring']),
        makeNeed('neither', tags: const ['Chess']),
      ];
      final result = filterAndSortNeeds(
        needs,
        FeedFilter(interests: const {'Flutter'}, skills: const {'Tutoring'}),
      );
      expect(idsOf(result), ['both']);
    });

    test('selecting more chips narrows, never widens', () {
      final needs = [
        makeNeed('a', tags: const ['Flutter']),
        makeNeed('b', tags: const ['Chess']),
      ];
      final one =
          filterAndSortNeeds(needs, FeedFilter(interests: const {'Flutter'}));
      final two = filterAndSortNeeds(
          needs, FeedFilter(interests: const {'Flutter', 'Chess'}));
      expect(one.length, 1);
      expect(two.length, lessThanOrEqualTo(one.length));
      expect(two, isEmpty);
    });

    test('chips with no overlap correctly return nothing', () {
      final needs = [makeNeed('a', tags: const ['Flutter'])];
      final result = filterAndSortNeeds(
          needs, FeedFilter(interests: const {'Flutter', 'Cooking'}));
      expect(result, isEmpty);
    });
  });

  group('what a chip matches against', () {
    test('matches the AI tags the server assigned', () {
      final needs = [makeNeed('tagged', tags: const ['Photography'])];
      final result = filterAndSortNeeds(
          needs, FeedFilter(interests: const {'Photography'}));
      expect(idsOf(result), ['tagged']);
    });

    test('falls back to the title when tags are absent', () {
      final needs = [
        makeNeed('titled', title: 'Looking for a Flutter developer'),
      ];
      final result =
          filterAndSortNeeds(needs, FeedFilter(skills: const {'Flutter'}));
      expect(idsOf(result), ['titled']);
    });

    test('falls back to the description', () {
      final needs = [
        makeNeed('described', description: 'Help me with Python scripting'),
      ];
      final result =
          filterAndSortNeeds(needs, FeedFilter(skills: const {'Python'}));
      expect(idsOf(result), ['described']);
    });

    test("matches the poster's declared interests", () {
      final needs = [makeNeed('poster', posterInterests: const ['Chess'])];
      final result =
          filterAndSortNeeds(needs, FeedFilter(interests: const {'Chess'}));
      expect(idsOf(result), ['poster']);
    });
  });

  group('sorting', () {
    final needs = [
      makeNeed('mid',
          distanceKm: 5, budgetMin: 500, createdAt: DateTime(2026, 2, 1)),
      makeNeed('near',
          distanceKm: 1, budgetMin: 100, createdAt: DateTime(2026, 1, 1)),
      makeNeed('far',
          distanceKm: 50, budgetMin: 900, createdAt: DateTime(2026, 3, 1)),
    ];

    test('newest', () {
      expect(idsOf(filterAndSortNeeds(needs, const FeedFilter(sortBy: 'newest'))),
          ['far', 'mid', 'near']);
    });

    test('nearest', () {
      expect(
          idsOf(filterAndSortNeeds(needs, const FeedFilter(sortBy: 'nearest'))),
          ['near', 'mid', 'far']);
    });

    test('highest_points sorts by budget descending', () {
      expect(
          idsOf(filterAndSortNeeds(
              needs, const FeedFilter(sortBy: 'highest_points'))),
          ['far', 'mid', 'near']);
    });

    test('nearest puts unknown distances last', () {
      final withUnknown = [makeNeed('unknown'), makeNeed('known', distanceKm: 9)];
      expect(
          idsOf(filterAndSortNeeds(
              withUnknown, const FeedFilter(sortBy: 'nearest'))),
          ['known', 'unknown']);
    });
  });

  group('serverSortFor', () {
    // "Newest" used to sort a page the server had already truncated to the 60
    // most *relevant* needs, so a brand-new low-relevance need never arrived
    // and the option looked dead. The sort has to reach the server.
    test('newest asks the server for newest', () {
      expect(serverSortFor('newest'), 'newest');
    });

    test('nearest maps onto the server\'s distance sort', () {
      expect(serverSortFor('nearest'), 'distance');
    });

    test('highest_points has no server equivalent and keeps the smart page', () {
      expect(serverSortFor('highest_points'), 'smart');
    });

    test('an unknown sort falls back to smart rather than breaking the feed', () {
      expect(serverSortFor('something_else'), 'smart');
      expect(serverSortFor(''), 'smart');
    });
  });

  group('filters stay independent of AI ranking', () {
    // The server ranks the feed; these chips are the user's own narrowing on
    // top. Filter results must depend only on the filter, not on feed order.
    test('input order does not change which needs survive', () {
      final needs = [
        makeNeed('a', tags: const ['Flutter'], createdAt: DateTime(2026, 1, 1)),
        makeNeed('b', tags: const ['Flutter'], createdAt: DateTime(2026, 2, 1)),
      ];
      final forward =
          filterAndSortNeeds(needs, FeedFilter(interests: const {'Flutter'}));
      final reversed = filterAndSortNeeds(
          needs.reversed.toList(), FeedFilter(interests: const {'Flutter'}));
      expect(idsOf(forward), idsOf(reversed));
    });
  });
}
