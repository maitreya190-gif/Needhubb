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
  int? budgetMax,
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
    budgetMax: budgetMax,
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

    // The default is the server's personalized AI ranking, so the client must
    // hand the list back untouched. It used to re-sort by createdAt here,
    // which meant the AI ordering never actually reached the screen.
    test('default sort preserves the AI order the server sent', () {
      final needs = [
        makeNeed('old', createdAt: DateTime(2026, 1, 1)),
        makeNeed('newest', createdAt: DateTime(2026, 3, 1)),
        makeNeed('middle', createdAt: DateTime(2026, 2, 1)),
      ];
      expect(idsOf(filterAndSortNeeds(needs, const FeedFilter())),
          ['old', 'newest', 'middle']);
    });

    test('default sortBy is smart, not newest', () {
      expect(const FeedFilter().sortBy, kSortSmart);
      expect(serverSortFor(const FeedFilter().sortBy), 'smart');
    });

    // An untouched filter must not look "active", or the feed would show a
    // clear-filters ribbon on a fresh launch.
    test('an untouched filter reports no active badges', () {
      expect(const FeedFilter().filterCount, 0);
      expect(const FeedFilter().isDefault, isTrue);
    });

    // Choosing newest is now an explicit departure from the AI ranking, so it
    // has to be visible and clearable — and clearing returns to smart.
    test('explicit newest is a clearable badge that resets to smart', () {
      const f = FeedFilter(sortBy: kSortNewest);
      expect(f.filterCount, 1);
      final cleared = f.removeBadge(f.activeBadges.first);
      expect(cleared.sortBy, kSortSmart);
    });

    test('explicit newest still sorts newest first', () {
      final needs = [
        makeNeed('old', createdAt: DateTime(2026, 1, 1)),
        makeNeed('newest', createdAt: DateTime(2026, 3, 1)),
        makeNeed('middle', createdAt: DateTime(2026, 2, 1)),
      ];
      expect(
        idsOf(filterAndSortNeeds(needs, const FeedFilter(sortBy: kSortNewest))),
        ['newest', 'middle', 'old'],
      );
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
    test('minBudget excludes cheaper needs but passes needs with no budget',
        () {
      // A budget filter only means something for needs that declare one.
      // Connect needs carry no budget at all — excluding them the moment a
      // budget slider moved made the whole feed look broken for a filter
      // that was never meant to apply to them.
      final needs = [
        makeNeed('rich', budgetMin: 1000),
        makeNeed('cheap', budgetMin: 100),
        makeNeed('unpaid'),
      ];
      final result =
          filterAndSortNeeds(needs, const FeedFilter(minBudget: 500));
      expect(idsOf(result).toSet(), {'rich', 'unpaid'});
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
          filterAndSortNeeds(needs, const FeedFilter(genders: {'Female'}));
      expect(idsOf(result), ['female']);
    });

    test('gender comparison ignores case and punctuation', () {
      final needs = [makeNeed('nb', posterGender: 'Non-binary')];
      final result =
          filterAndSortNeeds(needs, const FeedFilter(genders: {'non binary'}));
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

  group('chips combine as an OR, ranked by hit count', () {
    test('a need matching every chip leads the list', () {
      final needs = [
        makeNeed('onlyFlutter', tags: const ['Flutter']),
        makeNeed('both', tags: const ['Flutter', 'Tutoring']),
        makeNeed('onlyTutoring', tags: const ['Tutoring']),
        makeNeed('neither', tags: const ['Chess']),
      ];
      final result = filterAndSortNeeds(
        needs,
        const FeedFilter(interests: {'Flutter'}, skills: {'Tutoring'}),
      );
      // Every partial match is kept; the 2-hit need is ranked first.
      expect(result.first.id, 'both');
      expect(idsOf(result).toSet(), {'both', 'onlyFlutter', 'onlyTutoring'});
      expect(idsOf(result), isNot(contains('neither')));
    });

    test('selecting a second chip widens, never empties', () {
      final needs = [
        makeNeed('a', tags: const ['Flutter']),
        makeNeed('b', tags: const ['Chess']),
      ];
      final one =
          filterAndSortNeeds(needs, const FeedFilter(interests: {'Flutter'}));
      final two = filterAndSortNeeds(
          needs, const FeedFilter(interests: {'Flutter', 'Chess'}));
      expect(one.length, 1);
      // This is the exact case that made two filters look broken before.
      expect(two.length, greaterThanOrEqualTo(one.length));
      expect(idsOf(two).toSet(), {'a', 'b'});
    });

    test('two orthogonal chips still return both sides, never nothing', () {
      final needs = [
        makeNeed('f', tags: const ['Flutter']),
        makeNeed('c', tags: const ['Cooking']),
      ];
      final result = filterAndSortNeeds(
          needs, const FeedFilter(interests: {'Flutter', 'Cooking'}));
      expect(idsOf(result).toSet(), {'f', 'c'});
    });
  });

  group('what a chip matches against', () {
    test('matches the AI tags the server assigned', () {
      final needs = [makeNeed('tagged', tags: const ['Photography'])];
      final result = filterAndSortNeeds(
          needs, const FeedFilter(interests: {'Photography'}));
      expect(idsOf(result), ['tagged']);
    });

    test('falls back to the title when tags are absent', () {
      final needs = [
        makeNeed('titled', title: 'Looking for a Flutter developer'),
      ];
      final result =
          filterAndSortNeeds(needs, const FeedFilter(skills: {'Flutter'}));
      expect(idsOf(result), ['titled']);
    });

    test('falls back to the description', () {
      final needs = [
        makeNeed('described', description: 'Help me with Python scripting'),
      ];
      final result =
          filterAndSortNeeds(needs, const FeedFilter(skills: {'Python'}));
      expect(idsOf(result), ['described']);
    });

    test("matches the poster's declared interests", () {
      final needs = [makeNeed('poster', posterInterests: const ['Chess'])];
      final result =
          filterAndSortNeeds(needs, const FeedFilter(interests: {'Chess'}));
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

  group('partialMatchNeeds is retired', () {
    // Under OR matching, every "partial" need is already in the main list.
    // If this ever returned rows again the surfaces would render them twice.
    test('is always empty, so nothing renders twice', () {
      final needs = [
        makeNeed('both', tags: const ['Flutter', 'Tutoring']),
        makeNeed('one', tags: const ['Flutter']),
        makeNeed('none', tags: const ['Chess']),
      ];
      const filter = FeedFilter(interests: {'Flutter'}, skills: {'Tutoring'});
      expect(partialMatchNeeds(needs, filter), isEmpty);
    });

    test('the main list already carries every partial match', () {
      final needs = [
        makeNeed('both', tags: const ['Flutter', 'Tutoring']),
        makeNeed('one', tags: const ['Flutter']),
      ];
      const filter = FeedFilter(interests: {'Flutter'}, skills: {'Tutoring'});
      final main = idsOf(filterAndSortNeeds(needs, filter)).toSet();
      expect(main, containsAll(<String>['both', 'one']));
      expect(partialMatchNeeds(needs, filter), isEmpty);
    });

    test('main and partial can never overlap, so no duplicate rendering', () {
      final needs = [
        makeNeed('both', tags: const ['Flutter', 'Tutoring']),
        makeNeed('one', tags: const ['Flutter']),
      ];
      const filter = FeedFilter(interests: {'Flutter'}, skills: {'Tutoring'});
      final main = idsOf(filterAndSortNeeds(needs, filter)).toSet();
      final partial = idsOf(partialMatchNeeds(needs, filter)).toSet();
      expect(main.intersection(partial), isEmpty);
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
          filterAndSortNeeds(needs, const FeedFilter(interests: {'Flutter'}));
      final reversed = filterAndSortNeeds(
          needs.reversed.toList(), const FeedFilter(interests: {'Flutter'}));
      // Membership is order-independent; ordering deliberately is not, since
      // the default sort preserves the server's AI ranking.
      expect(idsOf(forward).toSet(), idsOf(reversed).toSet());
    });

    // Under an explicit sort the result must be fully order-independent.
    test('an explicit sort is not affected by input order', () {
      final needs = [
        makeNeed('a', tags: const ['Flutter'], createdAt: DateTime(2026, 1, 1)),
        makeNeed('b', tags: const ['Flutter'], createdAt: DateTime(2026, 2, 1)),
      ];
      const f = FeedFilter(interests: {'Flutter'}, sortBy: kSortNewest);
      expect(idsOf(filterAndSortNeeds(needs, f)),
          idsOf(filterAndSortNeeds(needs.reversed.toList(), f)));
    });
  });

  // Reported in the field as "no filters work, combining two works even less,
  // gender does nothing". Root causes were (a) posterGender never parsed from
  // the API so every need looked genderless, and (b) budget compared only
  // against budgetMin so ranges were mis-tested.
  group('reported filter failures', () {
    test('gender filter keeps matching posters rather than emptying the feed',
        () {
      final needs = [
        makeNeed('f', posterGender: 'Female'),
        makeNeed('m', posterGender: 'Male'),
      ];
      expect(
        idsOf(filterAndSortNeeds(needs, const FeedFilter(genders: {'Female'}))),
        ['f'],
      );
    });

    test('selecting several genders widens rather than narrows', () {
      final needs = [
        makeNeed('f', posterGender: 'Female'),
        makeNeed('m', posterGender: 'Male'),
        makeNeed('n', posterGender: 'Non-binary'),
      ];
      final r = filterAndSortNeeds(
          needs, const FeedFilter(genders: {'Female', 'Male'}));
      expect(idsOf(r).toSet(), {'f', 'm'});
    });

    test('gender combines with a topic chip instead of cancelling it', () {
      final needs = [
        makeNeed('want', posterGender: 'Female', tags: const ['Flutter']),
        makeNeed('wrongGender', posterGender: 'Male', tags: const ['Flutter']),
        makeNeed('wrongTopic', posterGender: 'Female', tags: const ['Chess']),
      ];
      final r = filterAndSortNeeds(
        needs,
        const FeedFilter(genders: {'Female'}, interests: {'Flutter'}),
      );
      expect(idsOf(r), ['want']);
    });

    test('three filters together still resolve to the one real match', () {
      final needs = [
        makeNeed('match',
            posterGender: 'Female',
            tags: const ['Flutter'],
            distanceKm: 3,
            budgetMin: 500,
            budgetMax: 1500),
        makeNeed('tooFar',
            posterGender: 'Female',
            tags: const ['Flutter'],
            distanceKm: 40,
            budgetMin: 500,
            budgetMax: 1500),
        makeNeed('tooCheap',
            posterGender: 'Female',
            tags: const ['Flutter'],
            distanceKm: 3,
            budgetMin: 50,
            budgetMax: 90),
      ];
      final r = filterAndSortNeeds(
        needs,
        const FeedFilter(
          genders: {'Female'},
          interests: {'Flutter'},
          maxDistanceKm: 10,
          minBudget: 400,
        ),
      );
      expect(idsOf(r), ['match']);
    });

    // A need paying ₹500–₹2000 does satisfy "at least ₹1000": its top end
    // clears the bar. Testing budgetMin alone wrongly dropped it.
    test('a budget range spanning the minimum is kept', () {
      final needs = [makeNeed('span', budgetMin: 500, budgetMax: 2000)];
      expect(
        idsOf(filterAndSortNeeds(needs, const FeedFilter(minBudget: 1000))),
        ['span'],
      );
    });

    test('a need priced entirely under the minimum is dropped', () {
      final needs = [makeNeed('cheap', budgetMin: 100, budgetMax: 200)];
      expect(
        filterAndSortNeeds(needs, const FeedFilter(minBudget: 1000)),
        isEmpty,
      );
    });

    test('a need starting above the maximum is dropped', () {
      final needs = [makeNeed('pricey', budgetMin: 5000, budgetMax: 9000)];
      expect(
        filterAndSortNeeds(needs, const FeedFilter(maxBudget: 1000)),
        isEmpty,
      );
    });
  });

  // ── Full sweep: every filter alone, then every combination ──────────────
  // Built from the brief "all filters must work individually AND in group".
  // Each filter is proven to (a) keep what matches, (b) drop what doesn't,
  // and (c) still behave when stacked with the others.
  group('every filter, individually', () {
    List<Need> sample() => [
          makeNeed('a',
              distanceKm: 2,
              budgetMin: 500,
              budgetMax: 1500,
              posterGender: 'Female',
              tags: const ['Flutter'],
              createdAt: DateTime(2026, 3, 1)),
          makeNeed('b',
              distanceKm: 25,
              budgetMin: 3000,
              budgetMax: 5000,
              posterGender: 'Male',
              tags: const ['Cooking'],
              createdAt: DateTime(2026, 1, 1)),
          makeNeed('c',
              distanceKm: 8,
              posterGender: 'Non-binary',
              tags: const ['Chess'],
              createdAt: DateTime(2026, 2, 1)),
        ];

    test('distance alone keeps only what is inside the radius', () {
      final r =
          filterAndSortNeeds(sample(), const FeedFilter(maxDistanceKm: 10));
      expect(idsOf(r).toSet(), {'a', 'c'});
    });

    test('minBudget alone keeps budget-less needs and clears the bar', () {
      final r = filterAndSortNeeds(sample(), const FeedFilter(minBudget: 2000));
      // 'a' tops out at 1500 → dropped. 'c' declares no budget → kept.
      expect(idsOf(r).toSet(), {'b', 'c'});
    });

    test('maxBudget alone drops needs priced entirely above it', () {
      final r = filterAndSortNeeds(sample(), const FeedFilter(maxBudget: 2000));
      expect(idsOf(r).toSet(), {'a', 'c'});
    });

    test('gender alone keeps exactly the matching poster', () {
      final r =
          filterAndSortNeeds(sample(), const FeedFilter(genders: {'Male'}));
      expect(idsOf(r), ['b']);
    });

    test('a single interest chip alone keeps only that topic', () {
      final r = filterAndSortNeeds(
          sample(), const FeedFilter(interests: {'Flutter'}));
      expect(idsOf(r), ['a']);
    });

    test('a single skill chip alone behaves the same as an interest', () {
      final r =
          filterAndSortNeeds(sample(), const FeedFilter(skills: {'Chess'}));
      expect(idsOf(r), ['c']);
    });

    test('sort alone reorders without dropping anything', () {
      final r =
          filterAndSortNeeds(sample(), const FeedFilter(sortBy: kSortNewest));
      expect(r.length, 3);
      expect(idsOf(r), ['a', 'c', 'b']);
    });

    test('nearest sort orders by distance ascending', () {
      final r =
          filterAndSortNeeds(sample(), const FeedFilter(sortBy: kSortNearest));
      expect(idsOf(r), ['a', 'c', 'b']);
    });

    test('an untouched filter returns everything, untouched', () {
      final r = filterAndSortNeeds(sample(), const FeedFilter());
      expect(idsOf(r), ['a', 'b', 'c']);
    });
  });

  group('filters in combination', () {
    List<Need> sample() => [
          makeNeed('match',
              distanceKm: 3,
              budgetMin: 800,
              budgetMax: 2000,
              posterGender: 'Female',
              tags: const ['Flutter', 'Tutoring']),
          makeNeed('tooFar',
              distanceKm: 40,
              budgetMin: 800,
              budgetMax: 2000,
              posterGender: 'Female',
              tags: const ['Flutter']),
          makeNeed('wrongGender',
              distanceKm: 3,
              budgetMin: 800,
              budgetMax: 2000,
              posterGender: 'Male',
              tags: const ['Flutter']),
          makeNeed('tooCheap',
              distanceKm: 3,
              budgetMin: 50,
              budgetMax: 100,
              posterGender: 'Female',
              tags: const ['Flutter']),
          makeNeed('offTopic',
              distanceKm: 3,
              budgetMin: 800,
              budgetMax: 2000,
              posterGender: 'Female',
              tags: const ['Chess']),
        ];

    test('distance + gender', () {
      final r = filterAndSortNeeds(sample(),
          const FeedFilter(maxDistanceKm: 10, genders: {'Female'}));
      expect(idsOf(r).toSet(), {'match', 'tooCheap', 'offTopic'});
    });

    test('distance + budget', () {
      final r = filterAndSortNeeds(
          sample(), const FeedFilter(maxDistanceKm: 10, minBudget: 500));
      expect(idsOf(r).toSet(), {'match', 'wrongGender', 'offTopic'});
    });

    test('gender + chip', () {
      final r = filterAndSortNeeds(sample(),
          const FeedFilter(genders: {'Female'}, interests: {'Flutter'}));
      expect(idsOf(r).toSet(), {'match', 'tooFar', 'tooCheap'});
    });

    test('all four hard filters plus a chip resolve to the one real match', () {
      final r = filterAndSortNeeds(
        sample(),
        const FeedFilter(
          maxDistanceKm: 10,
          minBudget: 500,
          maxBudget: 2500,
          genders: {'Female'},
          interests: {'Flutter'},
        ),
      );
      expect(idsOf(r), ['match']);
    });

    test('hard filters still apply on top of an OR chip match', () {
      // 'offTopic' hits the Chess chip but is out of radius once narrowed.
      final r = filterAndSortNeeds(
        sample(),
        const FeedFilter(
          maxDistanceKm: 5,
          genders: {'Female'},
          interests: {'Flutter', 'Chess'},
        ),
      );
      expect(idsOf(r).toSet(), {'match', 'tooCheap', 'offTopic'});
      expect(idsOf(r), isNot(contains('tooFar')));
      expect(idsOf(r), isNot(contains('wrongGender')));
    });

    test('combining filters never resurrects something a filter excluded', () {
      final r = filterAndSortNeeds(
        sample(),
        const FeedFilter(
          maxDistanceKm: 10,
          genders: {'Female'},
          interests: {'Flutter', 'Chess', 'Tutoring'},
        ),
      );
      // Adding more chips widens the topic net but can never override the
      // hard distance/gender constraints.
      expect(idsOf(r), isNot(contains('tooFar')));
      expect(idsOf(r), isNot(contains('wrongGender')));
    });

    test('an over-narrow combination returns empty rather than wrong rows', () {
      final r = filterAndSortNeeds(
        sample(),
        const FeedFilter(maxDistanceKm: 1, genders: {'Non-binary'}),
      );
      expect(r, isEmpty);
    });
  });

  group('boundary values', () {
    test('a need exactly at the distance limit is kept', () {
      final needs = [makeNeed('edge', distanceKm: 10)];
      expect(
          idsOf(filterAndSortNeeds(needs, const FeedFilter(maxDistanceKm: 10))),
          ['edge']);
    });

    test('a need exactly at the min budget is kept', () {
      final needs = [makeNeed('edge', budgetMin: 1000, budgetMax: 1000)];
      expect(idsOf(filterAndSortNeeds(needs, const FeedFilter(minBudget: 1000))),
          ['edge']);
    });

    test('a need exactly at the max budget is kept', () {
      final needs = [makeNeed('edge', budgetMin: 1000, budgetMax: 1000)];
      expect(idsOf(filterAndSortNeeds(needs, const FeedFilter(maxBudget: 1000))),
          ['edge']);
    });

    test('min and max budget together form an inclusive window', () {
      final needs = [
        makeNeed('inside', budgetMin: 800, budgetMax: 1200),
        makeNeed('below', budgetMin: 100, budgetMax: 200),
        makeNeed('above', budgetMin: 5000, budgetMax: 9000),
      ];
      final r = filterAndSortNeeds(
          needs, const FeedFilter(minBudget: 500, maxBudget: 2000));
      expect(idsOf(r), ['inside']);
    });

    test('a need with unknown distance survives a radius filter', () {
      // Distance is unknown until the server geocodes both ends — hiding it
      // would silently shrink the feed for reasons the user cannot see.
      final needs = [makeNeed('unknown')];
      expect(
          idsOf(filterAndSortNeeds(needs, const FeedFilter(maxDistanceKm: 5))),
          ['unknown']);
    });

    test('an empty source list never throws', () {
      expect(
        filterAndSortNeeds(const <Need>[],
            const FeedFilter(maxDistanceKm: 5, genders: {'Male'}, interests: {'Flutter'})),
        isEmpty,
      );
    });

    test('a chip matching nothing returns empty, not everything', () {
      final needs = [makeNeed('a', tags: const ['Flutter'])];
      expect(
        filterAndSortNeeds(
            needs, const FeedFilter(interests: {'Underwater Basketweaving'})),
        isEmpty,
      );
    });
  });
}
