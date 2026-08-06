import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/need.dart';
import '../../../models/person.dart';
import '../../../models/user_state.dart';
import '../../../services/chitchat_api.dart';
import '../../../services/messaging_api.dart';
import '../../../services/needs_api.dart';
import '../../../services/notification_navigator.dart';
import '../../../services/notifications_api.dart';
import '../../../services/personality_api.dart';
import '../../../services/profiles_api.dart';
import '../../../services/social_providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/nh_avatar.dart';
import '../../../widgets/nh_plus_badge.dart';
import '../../../widgets/nh_skeleton.dart';
import '../../../widgets/nh_empty_state.dart';
import '../../../widgets/nh_report_sheet.dart';
import '../../../widgets/nh_filter_sheet.dart';
import '../../../widgets/nh_urgent_badge.dart';
import '../../needs/need_detail_screen.dart';
import '../../connect/connect_detail_screen.dart';
import '../../person/person_screen.dart';
import '../conversation_screen.dart';
import '../view_on_map_screen.dart';
import 'package:needhub/services/messaging_api.dart';
import '../../../l10n/app_strings.dart';
import '../../../providers/language_provider.dart';
import '../../../services/translate_api.dart';
import '../../../widgets/nh_ad_card.dart';

// ── Feed filtering & sorting ─────────────────────────────────────────────────
// Earn and Connect share these so the two surfaces can't drift apart again.

/// Lowercases and collapses punctuation to single spaces so "Non-binary",
/// "non binary" and "Non_Binary" all compare equal.
String normalizeTerm(String s) =>
    s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Whole-word match with light plural tolerance, so "Sports" hits
/// "local sports groups" but "Art" does not hit "Martial".
bool termMatches(String haystack, String term) {
  final h = normalizeTerm(haystack);
  final tm = normalizeTerm(term);
  if (tm.isEmpty || h.isEmpty) return false;
  if (h == tm) return true;
  // Multi-word terms ("UI design") match as a contiguous phrase.
  if (tm.contains(' ')) return h.contains(tm);
  for (final w in h.split(' ')) {
    if (w == tm || w == '${tm}s' || '${w}s' == tm) return true;
  }
  return false;
}

/// Every text signal a chip may legitimately match against.
///
/// `tags` leads because the server now fills it with semantic tags drawn from
/// the same vocabulary as the chips themselves (see `need-tagging.ts`), which
/// is the signal a chip is really meant to match. Title and description stay in
/// as a widener so a need still matches when tagging is unavailable.
List<String> needHaystack(Need n) =>
    [...n.posterInterests, ...n.tags, n.title, n.description];

/// Hard limits the user set explicitly — distance, budget, gender. Anything
/// outside these is excluded outright; they are constraints, not preferences.
bool passesHardFilters(Need n, FeedFilter filter) {
  // The slider's top notch (50) is labelled "50+ km (Any)" in the filter
  // sheet, so it must mean no limit — not a hard 50km cut.
  if (filter.maxDistanceKm < 50 &&
      n.distanceKm != null &&
      n.distanceKm! > filter.maxDistanceKm) {
    return false;
  }
  // Budget is a range-overlap test, matching what the API does: a need with
  // ₹500–₹2000 satisfies "min ₹1000" because its top end clears the bar.
  // Comparing only against budgetMin (as this used to) dropped needs whose
  // range did cover the requested budget.
  if (filter.minBudget != null) {
    final top = n.budgetMax ?? n.budgetMin;
    if (top == null || top < filter.minBudget!) return false;
  }
  if (filter.maxBudget != null) {
    final bottom = n.budgetMin ?? n.budgetMax;
    if (bottom != null && bottom > filter.maxBudget!) return false;
  }
  // Gender is one-of by nature (a poster has a single gender), so selecting
  // several widens. A poster who never set a gender can't satisfy an
  // explicit gender filter.
  if (filter.genders.isNotEmpty) {
    final g = n.posterGender;
    if (g == null) return false;
    if (!filter.genders.any((f) => normalizeTerm(f) == normalizeTerm(g))) {
      return false;
    }
  }
  return true;
}

/// How many of the selected topic chips this need satisfies.
int chipHits(List<String> haystack, Set<String> chips) =>
    chips.where((c) => haystack.any((h) => termMatches(h, c))).length;

/// The user's explicit sort choice.
///
/// Returns 0 for the default AI ranking so the server's personalized order is
/// preserved exactly. This previously fell through to a createdAt sort, which
/// silently re-ordered smart-ranked results by recency — the AI ranking could
/// never actually reach the screen. Callers must use a *stable* sort for that
/// zero to mean "leave as the server sent it".
int compareBySort(Need a, Need b, FeedFilter filter) {
  if (filter.sortBy == kSortNearest) {
    return (a.distanceKm ?? double.infinity)
        .compareTo(b.distanceKm ?? double.infinity);
  }
  if (filter.sortBy == kSortHighestPoints) {
    return (b.budgetMax ?? b.budgetMin ?? 0)
        .compareTo(a.budgetMax ?? a.budgetMin ?? 0);
  }
  if (filter.sortBy == kSortNewest) {
    return b.createdAt.compareTo(a.createdAt);
  }
  return 0; // kSortSmart — keep the server's AI order.
}

/// Maps the user's sort choice onto the server's own sort parameter.
///
/// Sorting locally is not sufficient on its own. The server ranks the whole
/// feed and then truncates to `take`, so a locally-sorted page of smart-ranked
/// needs is only ever "the newest of the 60 most *relevant* needs" — a need
/// posted a minute ago that scores low on relevance never arrives at all, and
/// "Newest" looks like it does nothing. Asking the server to sort means we
/// fetch the right 60 rows in the first place.
///
/// 'highest_points' has no server equivalent (the API cannot sort by budget),
/// so it keeps the smart page and is sorted locally.
String serverSortFor(String sortBy) {
  switch (sortBy) {
    case kSortNewest:
      return 'newest';
    case kSortNearest:
      return 'distance';
    default:
      return 'smart';
  }
}

/// Dart's [List.sort] is not stable, so a comparator returning 0 is free to
/// reorder equal elements. The AI ranking depends on ties keeping the server's
/// order, so sort on (comparator, original index) instead.
void stableSortNeeds(List<Need> list, int Function(Need, Need) compare) {
  final indexed = <({Need need, int i})>[
    for (var i = 0; i < list.length; i++) (need: list[i], i: i),
  ];
  indexed.sort((a, b) {
    final c = compare(a.need, b.need);
    return c != 0 ? c : a.i.compareTo(b.i);
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = indexed[i].need;
  }
}

/// Applies the user's filters. This is deliberately independent of the
/// server's AI relevance ranking (`_score`, surfaced as the "AI-ranked"
/// badge): the AI decides what the raw feed contains and its base order,
/// while these chips are the user's own explicit narrowing on top of it.
///
/// Topic chips (interests + skills) combine as a strict AND — a need must
/// satisfy *every* selected chip to show. Selecting more chips therefore
/// always narrows, never widens, and picking chips with no overlap correctly
/// yields nothing rather than a grab-bag of partial matches.
///
/// With no chips selected nothing is excluded here, so an untouched filter
/// leaves the feed exactly as the server sent it, only re-sorted.
List<Need> filterAndSortNeeds(List<Need> source, FeedFilter filter) {
  final pool = source.where((n) => passesHardFilters(n, filter)).toList();
  final chips = {...filter.interests, ...filter.skills};

  final matched = chips.isEmpty
      ? pool
      : pool
          .where((n) => chipHits(needHaystack(n), chips) == chips.length)
          .toList();

  stableSortNeeds(matched, (a, b) => compareBySort(a, b, filter));
  return matched;
}

/// Needs that satisfy at least one selected chip but not all of them.
///
/// [filterAndSortNeeds] is a strict AND by design, so it can legitimately
/// return nothing — pick "Flutter" and "Cooking" and no need is both. Rather
/// than leave a dead feed, the surfaces render these underneath, clearly
/// labelled as *not* exact matches. The user's AND result always comes first
/// and is never padded, so a partial match can't be mistaken for one that
/// satisfied every chip.
///
/// Deliberately not the silent fallback to the unfiltered list that was
/// removed in fbb9f8e: the hard filters still apply, and a need matching zero
/// chips never appears here. Ordered by how many chips each need does satisfy.
List<Need> partialMatchNeeds(List<Need> source, FeedFilter filter) {
  final chips = {...filter.interests, ...filter.skills};
  if (chips.isEmpty) return const [];

  final scored = <({Need need, int hits, int i})>[];
  for (final n in source) {
    if (!passesHardFilters(n, filter)) continue;
    final hits = chipHits(needHaystack(n), chips);
    if (hits > 0 && hits < chips.length) {
      scored.add((need: n, hits: hits, i: scored.length));
    }
  }
  // Original index is the final tie-breaker so equal-scoring needs keep the
  // server's AI order under the default sort.
  scored.sort((a, b) {
    if (a.hits != b.hits) return b.hits.compareTo(a.hits);
    final c = compareBySort(a.need, b.need, filter);
    return c != 0 ? c : a.i.compareTo(b.i);
  });
  return scored.map((s) => s.need).toList();
}

/// Separator introducing the partial matches below an exact-AND result, so
/// the two groups can never be visually confused.
class _PartialMatchDivider extends StatelessWidget {
  final String title;
  final NeedHubTokens t;

  const _PartialMatchDivider({required this.title, required this.t});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: t.rail)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            title,
            style: GoogleFonts.hankenGrotesk(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: t.ink.withValues(alpha: 0.55),
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: t.rail)),
      ],
    );
  }
}

List<Widget> _interleaveAds(List<Widget> cards, NeedHubTokens t, {int interval = 10}) {
  if (cards.isEmpty) return cards;
  final result = <Widget>[];
  for (int i = 0; i < cards.length; i++) {
    result.add(cards[i]);
    // After every `interval` items, insert an ad card
    if ((i + 1) % interval == 0 && i < cards.length - 1) {
      result.add(Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: NhAdCard(t: t),
      ));
    }
  }
  return result;
}

class FeedTab extends ConsumerStatefulWidget {
  final String initialSurface;

  const FeedTab({super.key, this.initialSurface = 'earn'});

  @override
  ConsumerState<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends ConsumerState<FeedTab> {
  late String _surface;

  /// Server sort the currently-held feed was fetched with, so we only go back
  /// to the network when the sort actually changes — not on every chip tap.
  String _fetchedSort = '';

  @override
  void initState() {
    super.initState();
    _surface = widget.initialSurface;
    feedNeedsNotifier.addListener(_bump);
    feedRankerNotifier.addListener(_bump);
    unreadCountNotifier.addListener(_bump);
    earnFilterNotifier.addListener(_onFilterChanged);
    connectFilterNotifier.addListener(_onFilterChanged);
    feedLanguageNotifier.addListener(_onFeedLangChange);
    uiLanguageNotifier.addListener(_bump);
    Future.microtask(_fetchFeed);
  }

  @override
  void dispose() {
    feedNeedsNotifier.removeListener(_bump);
    feedRankerNotifier.removeListener(_bump);
    unreadCountNotifier.removeListener(_bump);
    earnFilterNotifier.removeListener(_onFilterChanged);
    connectFilterNotifier.removeListener(_onFilterChanged);
    feedLanguageNotifier.removeListener(_onFeedLangChange);
    uiLanguageNotifier.removeListener(_bump);
    super.dispose();
  }

  void _onFeedLangChange() {
    _bump();
    _batchTranslateFeed();
  }

  /// One Groq call to translate ALL need titles at once — eliminates the
  /// 20+ concurrent individual calls that were getting rate-limited.
  /// Only caches results that actually differ from the original (i.e. were
  /// translated); leaves the rest uncached so a retry can pick them up.
  Future<void> _batchTranslateFeed({int attempt = 0}) async {
    final lang = feedLanguageNotifier.value;
    if (lang == 'en') return;
    final needs = feedNeedsNotifier.value;
    final uncached = needs.where((n) => translationCache[n.id]?[lang] == null).toList();
    if (uncached.isEmpty) return;
    final titles = uncached.map((n) => n.title).toList();
    final translated = await translateBatch(titles, lang);
    bool anyTranslated = false;
    for (int i = 0; i < uncached.length; i++) {
      if (translated[i] != titles[i]) {
        translationCache.putIfAbsent(uncached[i].id, () => {})[lang] = translated[i];
        anyTranslated = true;
      }
    }
    if (mounted && anyTranslated) setState(() {});
    // If some titles still untranslated and we haven't retried yet, retry once after 4s
    final stillUntranslated = needs.where((n) => translationCache[n.id]?[lang] == null).length;
    if (stillUntranslated > 0 && attempt == 0) {
      await Future.delayed(const Duration(seconds: 4));
      if (mounted) _batchTranslateFeed(attempt: 1);
    }
  }

  void _bump() {
    if (mounted) setState(() {});
  }

  FeedFilter get _activeFilter => _surface == 'connect'
      ? connectFilterNotifier.value
      : earnFilterNotifier.value;

  /// The server-side query for the current filter.
  ///
  /// Distance, budget and gender are sent to the API rather than only applied
  /// locally. The server ranks the *whole* table and then truncates to `take`,
  /// so filtering a already-truncated page meant a narrow filter — or any two
  /// filters together — routinely showed nothing even when plenty of matching
  /// needs existed. Asking the server means the page is drawn from matching
  /// rows in the first place. Topic chips stay local on purpose: the API's
  /// `interests` param doubles as the personalization signal, so sending chips
  /// there would hijack the AI ranking.
  FeedQuery _queryFor(FeedFilter f) => FeedQuery(
        sort: serverSortFor(f.sortBy),
        // 50 is the slider's "Any" notch — not a real 50km cap.
        distanceKm: f.maxDistanceKm < 50 ? f.maxDistanceKm : null,
        minBudget: f.minBudget,
        maxBudget: f.maxBudget,
        genders: f.genders.toList(),
      );

  bool _sameQuery(FeedQuery a, FeedQuery b) =>
      a.sort == b.sort &&
      a.distanceKm == b.distanceKm &&
      a.minBudget == b.minBudget &&
      a.maxBudget == b.maxBudget &&
      a.genders.join(',') == b.genders.join(',');

  /// Chips are refined locally (no refetch needed), but any hard filter or
  /// sort change means the server must build a different page.
  void _onFilterChanged() {
    final next = _queryFor(_activeFilter);
    if (!_sameQuery(next, activeFeedQueryNotifier.value)) {
      _fetchFeed();
    }
    _bump();
  }

  /// Earn and Connect keep separate filters, so switching surface can also
  /// change the active sort and require a differently-sorted page.
  void _setSurface(String surface) {
    setState(() => _surface = surface);
    _onFilterChanged();
  }

  Future<void> _fetchFeed() async {
    final query = _queryFor(_activeFilter);
    _fetchedSort = query.sort;
    // Publish before awaiting so the background poller in main.dart uses the
    // same query for its next refresh instead of overwriting this one.
    activeFeedQueryNotifier.value = query;
    try {
      final api = ref.read(needsApiProvider);
      final result = await api.feed(
        sort: query.sort,
        distanceKm: query.distanceKm,
        minBudget: query.minBudget,
        maxBudget: query.maxBudget,
        genders: query.genders,
        take: 60,
      );
      if (!mounted) return;
      // An empty result is a legitimate answer once filters are involved —
      // keeping the previous list here would show needs that don't match.
      feedNeedsNotifier.value = result.needs;
      feedRankerNotifier.value = result.ranker;
    } catch (_) {}
    // Batch-translate all need titles in one Groq call after the feed loads.
    _batchTranslateFeed();
  }

  /// Pull-to-refresh: re-fetches whatever data backs the currently visible
  /// surface. ChitChat has its own status+roster fetch (mirrors the one
  /// _ChitChatFeedInline runs on first open); Earn/Connect share the same
  /// underlying feed fetch since they're just two client-side filtered views
  /// over feedNeedsNotifier.
  Future<void> _handlePullToRefresh() async {
    if (_surface == 'chitchat') {
      try {
        final api = ref.read(chitchatApiProvider);
        final status = await api.status();
        if (!mounted) return;
        chitChatAvailableNotifier.value = status.available;
        chitchatRosterNotifier.value = await api.availablePeople();
      } catch (_) {}
    } else {
      await _fetchFeed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;
    final feedNeeds = feedNeedsNotifier.value;
    final isAiRanked = feedRankerNotifier.value == 'embeddings';

    return Scaffold(
      backgroundColor: t.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Back button
                  if (Navigator.canPop(context))
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.arrow_back_rounded,
                          color: t.ink, size: 22),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NeedHub',
                          style: GoogleFonts.bricolageGrotesque(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            color: t.ink,
                            letterSpacing: -0.5,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _surface == 'earn'
                              ? '${feedNeeds.where((n) => n.category == 'earn').length} ${s.needsNearYou}'
                              : _surface == 'connect'
                                  ? '${mockPeople.length} ${s.peopleNearYou}'
                                  : s.casualChats,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: t.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // View on Map Button
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ViewOnMapScreen(),
                        ),
                      );
                    },
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: t.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: t.ink.withValues(alpha: 0.09),
                          width: 1,
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.map_rounded, size: 20, color: NeedHubTokens.clay),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Language picker button
                  GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (ctx) => _FeedLangSheet(t: t),
                      );
                    },
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: t.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: t.ink.withValues(alpha: 0.09),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          feedLanguageNotifier.value.toUpperCase(),
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: feedLanguageNotifier.value == 'en'
                                ? t.muted
                                : NeedHubTokens.clay,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Bell button — badge count is live from unreadCountNotifier.
                  GestureDetector(
                    onTap: () async {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _NotificationsSheet(),
                      );
                      // Marking-all-read happens explicitly from the sheet;
                      // opening it just refreshes the list.
                      try {
                        final api = ref.read(notificationsApiProvider);
                        notificationsListNotifier.value = await api.list();
                        unreadCountNotifier.value = await api.unreadCount();
                      } catch (_) {/* swallow */}
                    },
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: t.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: t.ink.withValues(alpha: 0.09),
                          width: 1,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Icon(Icons.notifications_outlined,
                                size: 20, color: t.ink),
                          ),
                          if (unreadCountNotifier.value > 0)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                constraints: const BoxConstraints(
                                    minWidth: 16, minHeight: 16),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: NeedHubTokens.clay,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: t.card, width: 2),
                                ),
                                child: Text(
                                  unreadCountNotifier.value > 99
                                      ? '99+'
                                      : '${unreadCountNotifier.value}',
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Surface toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: t.rail,
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    _SurfaceBtn(
                      label: s.connect,
                      active: _surface == 'connect',
                      onTap: () => _setSurface('connect'),
                      t: t,
                    ),
                    _SurfaceBtn(
                      label: s.earn,
                      active: _surface == 'earn',
                      onTap: () => _setSurface('earn'),
                      t: t,
                    ),
                    _SurfaceBtn(
                      label: s.chitchat,
                      active: _surface == 'chitchat',
                      onTap: () => _setSurface('chitchat'),
                      t: t,
                    ),
                  ],
                ),
              ),
            ),

            // Feed — Connect = connect category, Earn = earn category
            Expanded(
              child: RefreshIndicator(
                onRefresh: _handlePullToRefresh,
                color: NeedHubTokens.clay,
                child: _surface == 'connect'
                    ? _ConnectFeed(
                        needs: feedNeeds
                            .where((n) => n.category.toLowerCase() == 'connect')
                            .toList(),
                        t: t,
                        isAiRanked: isAiRanked)
                    : _surface == 'earn'
                        ? _EarnFeed(
                            needs: feedNeeds
                                .where((n) => n.category.toLowerCase() == 'earn')
                                .toList(),
                            t: t,
                            isAiRanked: isAiRanked)
                        : _ChitChatFeedInline(t: t),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Surface toggle button ─────────────────────────────────────────────────────

class _SurfaceBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final NeedHubTokens t;

  const _SurfaceBtn({
    required this.label,
    required this.active,
    required this.onTap,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: active ? t.card : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      offset: const Offset(0, 1),
                      blurRadius: 4,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Text(
              label,
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: active ? t.ink : t.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Connect feed ──────────────────────────────────────────────────────────────

class _ConnectFeed extends StatefulWidget {
  final NeedHubTokens t;
  final List<Need> needs;
  final bool isAiRanked;

  const _ConnectFeed({
    required this.t,
    required this.needs,
    this.isAiRanked = false,
  });

  @override
  State<_ConnectFeed> createState() => _ConnectFeedState();
}

class _ConnectFeedState extends State<_ConnectFeed> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    connectFilterNotifier.addListener(_bump);
    uiLanguageNotifier.addListener(_bump);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    connectFilterNotifier.removeListener(_bump);
    uiLanguageNotifier.removeListener(_bump);
    super.dispose();
  }

  void _bump() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final filter = connectFilterNotifier.value;
    // Same rules as needs: 50 means "any distance", explicit gender filters
    // exclude unknown-gender profiles, and topic chips combine as a strict
    // AND — a person must satisfy every selected chip.
    final chips = {...filter.interests, ...filter.skills};
    var filteredPeople = <Person>[];
    for (final p in mockPeople) {
      if (filter.maxDistanceKm < 50 && p.distanceKm > filter.maxDistanceKm) {
        continue;
      }
      if (filter.genders.isNotEmpty) {
        final g = p.gender;
        if (g == null) continue;
        if (!filter.genders
            .any((f) => normalizeTerm(f) == normalizeTerm(g))) {
          continue;
        }
      }
      if (chips.isNotEmpty &&
          chipHits([...p.interests, ...p.skills], chips) != chips.length) {
        continue;
      }
      filteredPeople.add(p);
    }
    filteredPeople.sort((a, b) {
      if (filter.sortBy == 'nearest') {
        return a.distanceKm.compareTo(b.distanceKm);
      }
      if (filter.sortBy == 'highest_points') {
        return b.points.compareTo(a.points);
      }
      return 0;
    });

    final needs = filterAndSortNeeds(widget.needs, filter);
    // Chips are a strict AND, so `needs` can be empty even when related needs
    // exist. These are shown below it, always labelled as inexact.
    final partialNeeds = partialMatchNeeds(widget.needs, filter);

    final activeCount = filter.filterCount;

    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
        children: const [
          NhPersonCardSkeleton(),
          SizedBox(height: 14),
          NhPersonCardSkeleton(),
          SizedBox(height: 14),
          NhPersonCardSkeleton(),
        ],
      );
    }

    if (filteredPeople.isEmpty && needs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
        children: [
          _ActiveFilterRibbon(filter: filter, surface: 'connect', t: t),
          SizedBox(height: activeCount > 0 ? 20 : 60),
          NhEmptyState(
            icon: Icons.people_outline_rounded,
            title: activeCount > 0
                ? S.current.noMatchesFilters
                : S.current.noOneNearby,
            subtitle: activeCount > 0
                ? S.current.tapEditFiltersHint
                : S.current.tryExpandingRadius,
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
      children: [
        _RankerBadge(isAi: widget.isAiRanked, t: t),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              S.current.nearYouRankedByInterests,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 13, fontWeight: FontWeight.w700, color: t.ink),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Container(
                    height: 1,
                    color: const Color(0xFF211E17).withValues(alpha: 0.10))),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => NhFilterSheet.open(context, surface: 'connect'),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: activeCount > 0
                      ? NeedHubTokens.clay.withValues(alpha: 0.10)
                      : t.card,
                  border: Border.all(
                      color: activeCount > 0
                          ? NeedHubTokens.clay.withValues(alpha: 0.40)
                          : const Color(0xFF211E17).withValues(alpha: 0.12),
                      width: 1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded,
                        size: 14,
                        color: activeCount > 0 ? NeedHubTokens.clay : t.ink),
                    const SizedBox(width: 6),
                    Text(activeCount > 0 ? '${S.current.filter} ($activeCount)' : S.current.filter,
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color:
                                activeCount > 0 ? NeedHubTokens.clay : t.ink)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ActiveFilterRibbon(filter: filter, surface: 'connect', t: t),
        ...filteredPeople.asMap().entries.map((e) {
          final i = e.key;
          final person = e.value;
          return Padding(
            padding:
                EdgeInsets.only(bottom: i < filteredPeople.length - 1 ? 14 : 0),
            child: _PersonCard(
              person: person,
              t: t,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => ConnectDetailScreen(person: person)),
              ),
            ),
          );
        }),
        if (needs.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              Text(S.current.freeNeedsNearYou,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 13, fontWeight: FontWeight.w700, color: t.ink)),
              const SizedBox(width: 8),
              Expanded(
                  child: Container(
                      height: 1,
                      color: const Color(0xFF211E17).withValues(alpha: 0.10))),
            ],
          ),
          const SizedBox(height: 12),
          ..._needCards(context, needs, t),
        ],
        if (partialNeeds.isNotEmpty) ...[
          const SizedBox(height: 24),
          _PartialMatchDivider(
              title: needs.isEmpty ? S.current.closestMatches : S.current.matchesSomeFilters,
              t: t),
          const SizedBox(height: 16),
          ..._needCards(context, partialNeeds, t),
        ],
      ],
    );
  }

  List<Widget> _needCards(
      BuildContext context, List<Need> list, NeedHubTokens t) {
    final cards = list.asMap().entries.map((e) {
      final need = e.value;
      return Padding(
        padding: EdgeInsets.only(bottom: e.key < list.length - 1 ? 14 : 0),
        child: _TranslatedEarnCard(
          need: need,
          t: t,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => NeedDetailScreen(need: need)),
          ),
        ),
      );
    }).toList();
    return _interleaveAds(cards, t);
  }
}

class _PersonCard extends StatelessWidget {
  final Person person;
  final NeedHubTokens t;
  final VoidCallback onTap;

  const _PersonCard({
    required this.person,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final shared = person.sharedInterests;
    final unique = person.uniqueInterests;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.card,
          border: Border.all(
            color: const Color(0xFF211E17).withValues(alpha: 0.08),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF281E0F).withValues(alpha: 0.4),
              offset: const Offset(0, 6),
              blurRadius: 16,
              spreadRadius: -12,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar + name + location chip
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: person.avatarColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    person.initials,
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: t.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // Location chip
                      Container(
                        padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
                        decoration: BoxDecoration(
                          color: t.chip,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: NeedHubTokens.forest,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${person.location} · ${person.distanceLabel}',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: t.muted4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Activity text
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                person.promptA1,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: t.ink2,
                  height: 1.35,
                ),
              ),
            ),

            // Shared interests
            if (shared.isNotEmpty || unique.isNotEmpty) ...[
              Text(
                S.current.youBothLike,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.08 * 11,
                  color: t.muted,
                ),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  ...shared.map((label) => _Chip(
                        label: label,
                        shared: true,
                      )),
                  ...unique.map((label) => _Chip(
                        label: label,
                        shared: false,
                      )),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool shared;

  const _Chip({required this.label, required this.shared});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: shared ? NeedHubTokens.clay : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: shared
            ? null
            : Border.all(
                color: const Color(0xFF211E17).withValues(alpha: 0.18),
                width: 1.5,
              ),
        boxShadow: shared
            ? [
                BoxShadow(
                  color: const Color(0xFFE1553B).withValues(alpha: 0.6),
                  offset: const Offset(0, 3),
                  blurRadius: 8,
                  spreadRadius: -3,
                ),
              ]
            : null,
      ),
      child: Text(
        label,
        style: GoogleFonts.hankenGrotesk(
          fontSize: 12.5,
          fontWeight: shared ? FontWeight.w700 : FontWeight.w600,
          color: shared
              ? Colors.white
              : const Color(0xFF211E17).withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

// ── Earn feed ─────────────────────────────────────────────────────────────────

class _EarnFeed extends StatefulWidget {
  final List<Need> needs;
  final NeedHubTokens t;
  final bool isAiRanked;

  const _EarnFeed({
    required this.needs,
    required this.t,
    this.isAiRanked = false,
  });

  @override
  State<_EarnFeed> createState() => _EarnFeedState();
}

class _EarnFeedState extends State<_EarnFeed> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    earnFilterNotifier.addListener(_bump);
    uiLanguageNotifier.addListener(_bump);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    earnFilterNotifier.removeListener(_bump);
    uiLanguageNotifier.removeListener(_bump);
    super.dispose();
  }

  void _bump() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final filter = earnFilterNotifier.value;
    final needs = filterAndSortNeeds(widget.needs, filter);
    // Chips are a strict AND, so `needs` can be empty even when related needs
    // exist. These are shown below it, always labelled as inexact.
    final partials = partialMatchNeeds(widget.needs, filter);

    final activeCount = filter.filterCount;

    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
        children: const [
          NhEarnCardSkeleton(),
          SizedBox(height: 14),
          NhEarnCardSkeleton(),
          SizedBox(height: 14),
          NhEarnCardSkeleton(),
        ],
      );
    }

    if (needs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
        children: [
          _ActiveFilterRibbon(filter: filter, surface: 'earn', t: t),
          SizedBox(height: activeCount > 0 ? 20 : 60),
          NhEmptyState(
            icon: Icons.search_off_rounded,
            title: activeCount > 0
                ? S.current.noNeedsMatchFilters
                : S.current.nothingNearby,
            subtitle: activeCount > 0
                ? S.current.tapEditFiltersHint
                : S.current.tryExpandingRadius,
          ),
          if (partials.isNotEmpty) ...[
            const SizedBox(height: 30),
            _PartialMatchDivider(title: S.current.closestMatches, t: t),
            const SizedBox(height: 16),
            ..._earnCards(context, partials, t),
          ],
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
      children: [
        _RankerBadge(isAi: widget.isAiRanked, t: t),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              '${needs.length} ${S.current.needsNearYou}',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 13, fontWeight: FontWeight.w700, color: t.ink),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: t.rail)),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => NhFilterSheet.open(context, surface: 'earn'),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: activeCount > 0
                      ? NeedHubTokens.clay.withValues(alpha: 0.10)
                      : t.card,
                  border: Border.all(
                      color: activeCount > 0
                          ? NeedHubTokens.clay.withValues(alpha: 0.40)
                          : const Color(0xFF211E17).withValues(alpha: 0.12),
                      width: 1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded,
                        size: 14,
                        color: activeCount > 0 ? NeedHubTokens.clay : t.ink),
                    const SizedBox(width: 6),
                    Text(activeCount > 0 ? '${S.current.filter} ($activeCount)' : S.current.filter,
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color:
                                activeCount > 0 ? NeedHubTokens.clay : t.ink)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ActiveFilterRibbon(filter: filter, surface: 'earn', t: t),
        ..._interleaveAds(
          needs.asMap().entries.map((e) {
            final i = e.key;
            final need = e.value;
            return Padding(
              padding: EdgeInsets.only(bottom: i < needs.length - 1 ? 14 : 0),
              child: _TranslatedEarnCard(
                need: need,
                t: t,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => NeedDetailScreen(need: need)),
                ),
              ),
            );
          }).toList(),
          t,
        ),
        if (partials.isNotEmpty) ...[
          const SizedBox(height: 26),
          _PartialMatchDivider(title: S.current.matchesSomeFilters, t: t),
          const SizedBox(height: 16),
          ..._interleaveAds(
            partials.asMap().entries.map((e) {
              final i = e.key;
              final need = e.value;
              return Padding(
                padding: EdgeInsets.only(bottom: i < partials.length - 1 ? 14 : 0),
                child: _TranslatedEarnCard(
                  need: need,
                  t: t,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => NeedDetailScreen(need: need)),
                  ),
                ),
              );
            }).toList(),
            t,
          ),
        ],
      ],
    );
  }

  List<Widget> _earnCards(
      BuildContext context, List<Need> list, NeedHubTokens t) {
    final cards = list.asMap().entries.map((e) {
      final need = e.value;
      return Padding(
        padding: EdgeInsets.only(bottom: e.key < list.length - 1 ? 14 : 0),
        child: _EarnCard(
          need: need,
          t: t,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => NeedDetailScreen(need: need)),
          ),
        ),
      );
    }).toList();
    return _interleaveAds(cards, t);
  }
}

class _FeedLangSheet extends StatelessWidget {
  final NeedHubTokens t;
  const _FeedLangSheet({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: t.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: t.rail,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Translate needs to',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: t.ink,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kSupportedLanguages.map((lang) {
              final isSelected = feedLanguageNotifier.value == lang['code'];
              return GestureDetector(
                onTap: () {
                  setFeedLanguage(lang['code']!);
                  translationCache.clear();
                  Navigator.pop(context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? NeedHubTokens.clay
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isSelected ? NeedHubTokens.clay : t.rail,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    lang['native']!,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : t.muted2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _TranslatedEarnCard extends StatefulWidget {
  final Need need;
  final NeedHubTokens t;
  final VoidCallback onTap;

  const _TranslatedEarnCard({required this.need, required this.t, required this.onTap});

  @override
  State<_TranslatedEarnCard> createState() => _TranslatedEarnCardState();
}

class _TranslatedEarnCardState extends State<_TranslatedEarnCard> {
  bool _showingOriginal = false;
  bool _translating = false;

  @override
  void initState() {
    super.initState();
    feedLanguageNotifier.addListener(_onLangChange);
    _translate();
  }

  @override
  void dispose() {
    feedLanguageNotifier.removeListener(_onLangChange);
    super.dispose();
  }

  void _onLangChange() {
    if (mounted) {
      setState(() { _showingOriginal = false; });
      _translate();
    }
  }

  Future<void> _translate({int attempt = 0, bool manual = false}) async {
    final lang = feedLanguageNotifier.value;
    if (lang == 'en') return;
    if (translationCache[widget.need.id]?[lang] != null) return;
    if (manual) setState(() { _translating = true; _showingOriginal = false; });
    final translated = await translateText(widget.need.title, lang);
    if (!mounted) return;
    if (translated != widget.need.title) {
      translationCache[widget.need.id] ??= {};
      translationCache[widget.need.id]![lang] = translated;
      setState(() { _translating = false; });
    } else {
      if (mounted) setState(() { _translating = false; });
      if (attempt == 0) {
        await Future.delayed(const Duration(seconds: 4));
        if (mounted) _translate(attempt: 1);
      }
    }
  }

  void _onToggle() {
    final lang = feedLanguageNotifier.value;
    final cached = translationCache[widget.need.id]?[lang];
    if (_showingOriginal) {
      setState(() => _showingOriginal = false);
    } else if (cached != null) {
      setState(() => _showingOriginal = true);
    } else {
      _translate(manual: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = feedLanguageNotifier.value;
    if (lang == 'en') {
      return _EarnCard(need: widget.need, t: widget.t, onTap: widget.onTap);
    }
    final cached = translationCache[widget.need.id]?[lang];
    final displayNeed = (!_showingOriginal && cached != null)
        ? widget.need.copyWith(title: cached)
        : widget.need;
    return _EarnCard(
      need: displayNeed,
      t: widget.t,
      onTap: widget.onTap,
      onTranslateTap: _onToggle,
      translating: _translating,
      showingOriginal: _showingOriginal,
      translated: cached != null,
    );
  }
}

class _EarnCard extends StatelessWidget {
  final Need need;
  final NeedHubTokens t;
  final VoidCallback onTap;
  // null = no translate UI; non-null = show the toggle
  final VoidCallback? onTranslateTap;
  final bool translating;
  final bool showingOriginal;
  final bool translated;

  const _EarnCard({
    required this.need,
    required this.t,
    required this.onTap,
    this.onTranslateTap,
    this.translating = false,
    this.showingOriginal = false,
    this.translated = false,
  });

  Color get _catTint {
    switch (need.category) {
      case 'earn':
        return NeedHubTokens.ochre;
      case 'connect':
        return NeedHubTokens.forest;
      default:
        return NeedHubTokens.clay;
    }
  }

  String get _catLabel {
    switch (need.category) {
      case 'earn':
        return S.current.earn.toUpperCase();
      case 'connect':
        return S.current.connect.toUpperCase();
      default:
        return S.current.chitchatLabel.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = _catTint;
    final hasBudget = need.budgetMin != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: t.card,
          border: Border.all(
            color: const Color(0xFF211E17).withValues(alpha: 0.10),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF281E0F).withValues(alpha: 0.4),
              offset: const Offset(0, 6),
              blurRadius: 16,
              spreadRadius: -12,
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            // Colored left bar
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              child: Container(width: 6, color: cat),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 15, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category badge + pay badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: cat,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    _catLabel,
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.06 * 10.5,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (need.peopleNeeded > 1 || need.acceptedCount > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: need.isFullyFrozen
                                          ? NeedHubTokens.forest.withValues(alpha: 0.15)
                                          : NeedHubTokens.clay.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      need.freezeProgressLabel,
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: need.isFullyFrozen
                                            ? NeedHubTokens.forest
                                            : NeedHubTokens.clay,
                                      ),
                                    ),
                                  ),
                                ],
                                if (need.isUrgent) ...[
                                  const SizedBox(width: 6),
                                  NhUrgentBadge(need: need, compact: true),
                                ],
                              ],
                            ),
                            const SizedBox(height: 9),
                            Text(
                              need.title,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: t.ink,
                                height: 1.2,
                              ),
                            ),
                            if (onTranslateTap != null) ...[
                              const SizedBox(height: 5),
                              GestureDetector(
                                onTap: translating ? null : onTranslateTap,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (translating)
                                      SizedBox(width: 11, height: 11,
                                          child: CircularProgressIndicator(strokeWidth: 1.4, color: t.muted))
                                    else
                                      Icon(Icons.translate_rounded, size: 12, color: t.muted),
                                    const SizedBox(width: 3),
                                    Text(
                                      translating
                                          ? S.current.translating
                                          : (showingOriginal ? S.current.translate : S.current.showOriginal),
                                      style: GoogleFonts.hankenGrotesk(
                                          fontSize: 11, color: t.muted, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (hasBudget) ...[
                        const SizedBox(width: 12),
                        Transform.rotate(
                          angle: 0.0524, // ~3 degrees in radians
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              border: Border.all(color: cat, width: 2),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '₹${need.budgetMin}',
                                  style: GoogleFonts.bricolageGrotesque(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: cat,
                                    height: 1,
                                  ),
                                ),
                                Text(
                                  'per job',
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: t.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Footer
                  Padding(
                    padding: const EdgeInsets.only(top: 13),
                    child: Container(
                      padding: const EdgeInsets.only(top: 11),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color:
                                const Color(0xFF211E17).withValues(alpha: 0.14),
                            width: 1,
                            style: BorderStyle.solid,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Builder(builder: (_) {
                            final url = need.posterAvatarUrl;
                            if (url != null && url.isNotEmpty) {
                              return ClipOval(
                                child: Image.network(
                                  url,
                                  width: 24,
                                  height: 24,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: t.rail2,
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      need.authorInitials,
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: t.muted4,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }
                            return Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: t.rail2,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                need.authorInitials,
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: t.muted4,
                                ),
                              ),
                            );
                          }),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${need.authorName} · ${need.location}',
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: t.muted2,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (need.posterPlus) ...[
                                  const SizedBox(width: 4),
                                  const NhPlusBadge(compact: true),
                                ],
                                if (need.posterTrustScore > 0 && need.category == 'connect') ...[
                                  const SizedBox(width: 4),
                                  _TrustBadge(score: need.posterTrustScore),
                                ],
                                if (need.category == 'connect') ...[
                                  const SizedBox(width: 6),
                                  _MatchBadge(need: need, t: t),
                                ],
                              ],
                            ),
                          ),
                          ValueListenableBuilder<int>(
                            valueListenable: offersNotifier,
                            builder: (_, __, ___) {
                              final count = need.totalOfferCount;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: cat.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$count ${count == 1 ? 'offer' : 'offers'}',
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cat,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Keep PersonCard as a public export for home_tab.dart compatibility
class PersonCard extends StatelessWidget {
  final Person person;
  final VoidCallback onTap;

  const PersonCard({super.key, required this.person, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _PersonCard(person: person, t: t, onTap: onTap);
  }
}

// ── Chit-chat inline feed ─────────────────────────────────────────────────────

class _ChitChatFeedInline extends ConsumerStatefulWidget {
  final NeedHubTokens t;

  const _ChitChatFeedInline({required this.t});

  @override
  ConsumerState<_ChitChatFeedInline> createState() =>
      _ChitChatFeedInlineState();
}

class _ChitChatFeedInlineState extends ConsumerState<_ChitChatFeedInline> {
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    chitChatAvailableNotifier.addListener(_bump);
    chitchatRosterNotifier.addListener(_bump);
    friendUserIdsNotifier.addListener(_bump);
    outgoingRequestUserIdsNotifier.addListener(_bump);
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _loading = false);
    });
    // Refresh chitchat state on open.
    Future.microtask(() async {
      final api = ref.read(chitchatApiProvider);
      try {
        final status = await api.status();
        chitChatAvailableNotifier.value = status.available;
        chitchatRosterNotifier.value = await api.availablePeople();
      } catch (_) {/* swallow */}
    });
  }

  @override
  void dispose() {
    chitChatAvailableNotifier.removeListener(_bump);
    chitchatRosterNotifier.removeListener(_bump);
    friendUserIdsNotifier.removeListener(_bump);
    outgoingRequestUserIdsNotifier.removeListener(_bump);
    super.dispose();
  }

  void _bump() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleAvailability(bool currentlyAvailable) async {
    if (_busy) return;
    setState(() => _busy = true);
    final api = ref.read(chitchatApiProvider);
    try {
      if (currentlyAvailable) {
        await api.clearAvailability();
        chitChatAvailableNotifier.value = false;
      } else {
        await api.setAvailability(4);
        chitChatAvailableNotifier.value = true;
      }
      chitchatRosterNotifier.value = await api.availablePeople();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static final _people = <({String initials, String name, String area, String interest, Color color})>[];

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final available = chitChatAvailableNotifier.value;

    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
        children: [
          const NhSkeleton(width: double.infinity, height: 52, radius: 14),
          const SizedBox(height: 22),
          const NhSkeleton(width: 180, height: 13, radius: 5),
          const SizedBox(height: 12),
          ...List.generate(
              3,
              (_) => const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: NhSkeleton(
                        width: double.infinity, height: 80, radius: 16),
                  )),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
      children: [
        // Availability toggle
        GestureDetector(
          onTap: _busy ? null : () => _toggleAvailability(available),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: available ? NeedHubTokens.clay : t.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: available ? NeedHubTokens.clay : t.rail,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  available
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: available ? Colors.white : t.muted,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    available
                        ? S.current.youreAvailableForChat
                        : S.current.markYourselfAvailableChat,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: available ? Colors.white : t.muted2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Friends' DMs & Messages Section
        _ChitChatFriendsDmsHeader(t: t),

        if (available) ...[
          Text(
            S.current.upForAChatRightNow,
            style: GoogleFonts.hankenGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: t.muted2,
            ),
          ),
          const SizedBox(height: 12),
          _SelfChitChatTile(t: t),
          const SizedBox(height: 10),
          SizedBox(
            height: 68,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...chitchatRosterNotifier.value.map(
                  (p) => _ChitChatRealCuboidalTile(person: p, t: t),
                ),
                if (chitchatRosterNotifier.value.isEmpty)
                  ..._people
                      .map((p) => _ChitChatPersonCuboidalTile(person: p, t: t)),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Footer info card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.chip,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: t.muted2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Chit-chat is casual hellos only. Each session is visible for 24 hours. You can turn it off anytime.',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 12.5,
                    color: t.muted2,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChitChatPersonCuboidalTile extends StatelessWidget {
  final ({
    String initials,
    String name,
    String area,
    String interest,
    Color color,
  }) person;
  final NeedHubTokens t;

  const _ChitChatPersonCuboidalTile({required this.person, required this.t});

  @override
  Widget build(BuildContext context) {
    final p = person;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _ChitChatProfileSheet(person: p, t: t),
        ),
        child: Container(
          width: 195,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.rail, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: p.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Text(
                  p.initials,
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: p.color,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      p.name,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.area,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 11,
                        color: t.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chat_bubble_outline_rounded,
                  size: 16, color: NeedHubTokens.clay),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChitChatProfileSheet extends StatefulWidget {
  final ({
    String initials,
    String name,
    String area,
    String interest,
    Color color
  }) person;
  final NeedHubTokens t;

  const _ChitChatProfileSheet({required this.person, required this.t});

  @override
  State<_ChitChatProfileSheet> createState() => _ChitChatProfileSheetState();
}

class _ChitChatProfileSheetState extends State<_ChitChatProfileSheet> {
  bool _friendRequested = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final p = widget.person;

    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 60),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).padding.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: t.rail, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 24),

          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: p.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Text(p.initials,
                style: GoogleFonts.bricolageGrotesque(
                    fontSize: 28, fontWeight: FontWeight.w700, color: p.color)),
          ),
          const SizedBox(height: 12),

          Text(p.name,
              style: GoogleFonts.bricolageGrotesque(
                  fontSize: 22, fontWeight: FontWeight.w800, color: t.ink)),
          const SizedBox(height: 4),
          Text(p.area,
              style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted)),
          const SizedBox(height: 28),

          // Chat button — stays in ChitChat, not added to main Chats
          GestureDetector(
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(MaterialPageRoute(
                builder: (_) => ConversationScreen(
                  name: p.name,
                  initials: p.initials,
                  avatarColor: p.color,
                ),
              ));
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                  color: NeedHubTokens.clay,
                  borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: Text(S.current.startChitchat,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ),
          const SizedBox(height: 10),

          // Add Friend — optional, to connect outside ChitChat
          GestureDetector(
            onTap: _friendRequested
                ? null
                : () => setState(() => _friendRequested = true),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: _friendRequested ? t.chip : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color:
                      _friendRequested ? t.rail : t.ink.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                _friendRequested ? 'Friend Request Sent' : 'Add Friend',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _friendRequested ? t.muted : t.ink,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              NhReportSheet.open(context, targetName: p.name);
            },
            icon:
                Icon(Icons.flag_outlined, size: 16, color: Colors.red.shade400),
            label: Text(
              'Report',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Notifications sheet ───────────────────────────────────────────────────────

class _NotificationsSheet extends ConsumerStatefulWidget {
  const _NotificationsSheet();

  @override
  ConsumerState<_NotificationsSheet> createState() =>
      _NotificationsSheetState();
}

class _NotificationsSheetState extends ConsumerState<_NotificationsSheet> {
  @override
  void initState() {
    super.initState();
    notificationsListNotifier.addListener(_bump);
    unreadCountNotifier.addListener(_bump);
  }

  @override
  void dispose() {
    notificationsListNotifier.removeListener(_bump);
    unreadCountNotifier.removeListener(_bump);
    super.dispose();
  }

  void _bump() {
    if (mounted) setState(() {});
  }

  Future<void> _markAllRead() async {
    final api = ref.read(notificationsApiProvider);
    try {
      await api.markAllRead();
      final now = DateTime.now();
      notificationsListNotifier.value = notificationsListNotifier.value
          .map((n) => NhNotification(
                id: n.id,
                type: n.type,
                title: n.title,
                body: n.body,
                refType: n.refType,
                refId: n.refId,
                createdAt: n.createdAt,
                readAt: n.readAt ?? now,
              ))
          .toList();
      unreadCountNotifier.value = 0;
    } catch (_) {/* silent */}
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'FRIEND_REQUEST_RECEIVED':
        return Icons.person_add_alt_rounded;
      case 'FRIEND_REQUEST_ACCEPTED':
        return Icons.handshake_outlined;
      case 'NEED_RESPONSE_RECEIVED':
        return Icons.currency_rupee_rounded;
      case 'MESSAGE_RECEIVED':
        return Icons.chat_bubble_outline_rounded;
      case 'REVIEW_RECEIVED':
        return Icons.star_outline_rounded;
      case 'POINTS_AWARDED':
        return Icons.stars_rounded;
      case 'CERT_APPROVED':
        return Icons.verified_rounded;
      case 'CERT_REJECTED':
        return Icons.cancel_outlined;
      case 'REDEMPTION_READY':
        return Icons.card_giftcard_rounded;
      case 'REPORT_ACTIONED':
        return Icons.warning_amber_rounded;
      case 'VOUCH_RECEIVED':
        return Icons.thumb_up_alt_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'FRIEND_REQUEST_RECEIVED':
      case 'FRIEND_REQUEST_ACCEPTED':
      case 'CERT_APPROVED':
      case 'VOUCH_RECEIVED':
        return NeedHubTokens.forest;
      case 'NEED_RESPONSE_RECEIVED':
      case 'REVIEW_RECEIVED':
      case 'POINTS_AWARDED':
        return NeedHubTokens.ochre;
      default:
        return NeedHubTokens.clay;
    }
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return S.current.timeAgoNow;
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final list = notificationsListNotifier.value;
    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 60),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: t.rail, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(S.current.notificationsLabel,
                  style: GoogleFonts.bricolageGrotesque(
                      fontSize: 20, fontWeight: FontWeight.w800, color: t.ink)),
              const Spacer(),
              if (unreadCountNotifier.value > 0)
                TextButton(
                  onPressed: _markAllRead,
                  child: Text(S.current.markAllRead,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: NeedHubTokens.clay)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<List<NhNotification>>(
            valueListenable: notificationsListNotifier,
            builder: (context, list, _) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: NhEmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: S.current.allQuietForNow,
                    subtitle: S.current.notifyWhenResponds,
                  ),
                );
              }
              return Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      Divider(color: t.rail, height: 1, indent: 56),
                  itemBuilder: (_, i) {
                    final n = list[i];
                    final color = _colorFor(n.type);
                    return InkWell(
                      onTap: () => NotificationNavigator.handleTap(
                        context: context,
                        notif: n,
                        ref: ref,
                        isBottomSheet: true,
                      ),
                      child: Container(
                        color: n.isUnread
                            ? color.withValues(alpha: 0.04)
                            : Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Icon(_iconFor(n.type),
                                  color: color, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          n.title,
                                          style: GoogleFonts.hankenGrotesk(
                                            fontSize: 13.5,
                                            fontWeight: n.isUnread
                                                ? FontWeight.w800
                                                : FontWeight.w700,
                                            color: t.ink,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _timeAgo(n.createdAt),
                                        style: GoogleFonts.hankenGrotesk(
                                          fontSize: 11,
                                          color: t.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    n.body,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 12.5,
                                      color: t.muted2,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SelfChitChatTile extends StatelessWidget {
  final NeedHubTokens t;

  const _SelfChitChatTile({required this.t});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NeedHubTokens.clay.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: NeedHubTokens.clay.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: NeedHubTokens.clay,
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: Text(
                'YOU',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.current.visibleFor24h,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: t.ink)),
                  const SizedBox(height: 3),
                  Text(S.current.nearbyWillSeeYouFirst,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 12, color: t.muted)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: NeedHubTokens.forest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(S.current.live,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Real ChitChat tile (hydrated from API) ───────────────────────────────────

class _ChitChatRealCuboidalTile extends ConsumerWidget {
  final ChitchatPerson person;
  final NeedHubTokens t;

  const _ChitChatRealCuboidalTile({required this.person, required this.t});

  String get _initials {
    final parts = person.displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ConversationScreen(
                name: person.displayName,
                initials: _initials,
                avatarColor: NeedHubTokens.forest,
                avatarUrl: person.avatarUrl,
                userId: person.userId,
              ),
            ),
          );
        },
        child: Container(
          width: 195,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.rail, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: NeedHubTokens.forest.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: person.avatarUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.network(
                          person.avatarUrl!,
                          width: 38,
                          height: 38,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Text(
                            _initials,
                            style: GoogleFonts.bricolageGrotesque(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: NeedHubTokens.forest,
                            ),
                          ),
                        ),
                      )
                    : Text(
                        _initials,
                        style: GoogleFonts.bricolageGrotesque(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: NeedHubTokens.forest,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      person.displayName,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      person.distanceLabel.isNotEmpty
                          ? person.distanceLabel
                          : S.current.nearby,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 11,
                        color: t.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chat_bubble_outline_rounded,
                  size: 16, color: NeedHubTokens.clay),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Ranker badge — visually reinforces "AI-ranked" vs "Ranked" heuristic ─────

class _RankerBadge extends StatelessWidget {
  final bool isAi;
  final NeedHubTokens t;

  const _RankerBadge({required this.isAi, required this.t});

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isAi ? NeedHubTokens.forest.withValues(alpha: 0.12) : t.chip,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  isAi ? NeedHubTokens.forest.withValues(alpha: 0.35) : t.rail,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAi ? Icons.auto_awesome_rounded : Icons.tune_rounded,
                size: 12,
                color: isAi ? NeedHubTokens.forest : t.muted2,
              ),
              const SizedBox(width: 6),
              Text(
                isAi ? '${s.aiRanked} feed' : 'Ranked feed',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isAi ? NeedHubTokens.forest : t.muted2,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChitChatFriendsDmsHeader extends ConsumerWidget {
  final NeedHubTokens t;

  const _ChitChatFriendsDmsHeader({required this.t});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final realChats = chatsListNotifier.value;
    final hasReal = realChats.isNotEmpty;

    final mockFriends = <({String name, String initials, Color color, String message})>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              "FRIENDS' DMs",
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: t.muted2,
              ),
            ),
            const Spacer(),
            Text(
              "Direct Messages",
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: NeedHubTokens.clay,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (hasReal)
          ...realChats.map((c) {
            final initials = _initialsFor(c.otherDisplayName);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ConversationScreen(
                        name: c.otherDisplayName,
                        initials: initials,
                        avatarColor: NeedHubTokens.forest,
                        avatarUrl: c.otherAvatarUrl,
                        userId: c.otherUserId,
                        threadId: c.threadId,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.rail, width: 1),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: NeedHubTokens.forest.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        alignment: Alignment.center,
                        child: c.otherAvatarUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(13),
                                child: Image.network(c.otherAvatarUrl!,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Text(initials,
                                        style: GoogleFonts.bricolageGrotesque(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: NeedHubTokens.forest))),
                              )
                            : Text(initials,
                                style: GoogleFonts.bricolageGrotesque(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: NeedHubTokens.forest)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.otherDisplayName,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: t.ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              c.lastMessageBody ?? 'Tap to chat',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 12,
                                color: t.muted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chat_bubble_outline_rounded,
                          size: 20, color: NeedHubTokens.clay),
                    ],
                  ),
                ),
              ),
            );
          })
        else
          ...mockFriends.map((f) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ConversationScreen(
                        name: f.name,
                        initials: f.initials,
                        avatarColor: f.color,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.rail, width: 1),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: f.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          f.initials,
                          style: GoogleFonts.bricolageGrotesque(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: f.color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.name,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: t.ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              f.message,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 12,
                                color: t.muted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chat_bubble_outline_rounded,
                          size: 20, color: NeedHubTokens.clay),
                    ],
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: 14),
      ],
    );
  }

  static String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

class _ActiveFilterRibbon extends StatelessWidget {
  final FeedFilter filter;
  final String surface;
  final NeedHubTokens t;

  const _ActiveFilterRibbon({
    required this.filter,
    required this.surface,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final badges = filter.activeBadges;
    if (badges.isEmpty) return const SizedBox.shrink();

    final notifier =
        surface == 'earn' ? earnFilterNotifier : connectFilterNotifier;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NeedHubTokens.clay.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: NeedHubTokens.clay.withValues(alpha: 0.20),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_alt_rounded,
                  size: 14, color: NeedHubTokens.clay),
              const SizedBox(width: 6),
              Text(
                'ACTIVE FILTERS (${badges.length})',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: NeedHubTokens.clay,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => NhFilterSheet.open(context, surface: surface),
                child: Text(
                  'Edit filters',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: NeedHubTokens.forest,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => notifier.value = const FeedFilter(),
                child: Text(
                  'Clear all',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: NeedHubTokens.clay,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: badges.map((badge) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: NeedHubTokens.clay.withValues(alpha: 0.30),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      badge.label,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        notifier.value = filter.removeBadge(badge);
                      },
                      child: const Icon(
                        Icons.cancel_rounded,
                        size: 15,
                        color: NeedHubTokens.clay,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// Small badge showing the compatibility % between the current user and the
/// need's poster. Uses personality traits when both users have taken the
/// quiz; otherwise falls back to interest-overlap + bio heuristic. Tapping
/// jumps into the personality test when I haven't taken it yet — a nudge
/// toward the deeper match signal.
/// Trust Score badge — email + phone + face verification plus track record
/// (approved certificates, fulfilled needs, review rating). Connect-only:
/// this is the safety signal for people meeting strangers in person.
class _TrustBadge extends StatelessWidget {
  final int score; // 0-100
  const _TrustBadge({required this.score});

  Color get _color {
    if (score >= 70) return const Color(0xFF2563EB); // strong trust — blue
    if (score >= 40) return const Color(0xFFB85D19); // partial — clay/amber
    return const Color(0xFF9CA3AF); // just getting started — grey
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_rounded, size: 10, color: _color),
          const SizedBox(width: 3),
          Text(
            '$score trust',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchBadge extends StatelessWidget {
  final Need need;
  final NeedHubTokens t;
  const _MatchBadge({required this.need, required this.t});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileMe?>(
      valueListenable: myProfileNotifier,
      builder: (_, me, __) {
        if (me == null || me.id == need.posterId) return const SizedBox.shrink();
        final myTraits = me.personalityTraits;
        final theirTraitsRaw = need.posterPersonalityTraits;
        int percent;
        bool aiBadge;
        if (myTraits != null && theirTraitsRaw != null) {
          final theirTraits = PersonalityTraits.fromJson(theirTraitsRaw);
          percent = personalityMatchPercent(myTraits, theirTraits);
          aiBadge = true;
        } else {
          percent = interestOverlapPercent(
            myInterests: me.interestLabels,
            theirInterests: need.posterInterests,
            theirBio: need.posterBio,
          );
          aiBadge = false;
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: NeedHubTokens.clay.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: NeedHubTokens.clay.withValues(alpha: 0.35),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                aiBadge ? Icons.psychology_alt_rounded : Icons.hub_rounded,
                size: 10,
                color: NeedHubTokens.clay,
              ),
              const SizedBox(width: 3),
              Text(
                '$percent%',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: NeedHubTokens.clay,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
