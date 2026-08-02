import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_strings.dart';
import '../../services/league_api.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/nh_motivation_hint.dart';

/// Full Impact League surface: the live leaderboard (global/friends), the
/// permanent Hall of Impact, and a browser for previous seasons' final
/// standings. Reached from a card on the You screen — there is no room for
/// a sixth bottom-nav tab in this app.
class ImpactLeagueScreen extends ConsumerStatefulWidget {
  const ImpactLeagueScreen({super.key});

  @override
  ConsumerState<ImpactLeagueScreen> createState() => _ImpactLeagueScreenState();
}

class _ImpactLeagueScreenState extends ConsumerState<ImpactLeagueScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  SeasonInfo? _season;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSeason());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadSeason() async {
    try {
      final season = await ref.read(leagueApiProvider).season();
      if (mounted) setState(() => _season = season);
    } catch (_) {
      // Header degrades to no countdown — the tabs below still work.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;

    return Scaffold(
      backgroundColor: t.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: t.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: t.rail, width: 1),
                      ),
                      child: Icon(Icons.arrow_back_rounded, color: t.ink, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.impactLeague,
                          style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.w800, color: t.ink),
                        ),
                        if (_season != null)
                          Text(
                            '${s.season} ${_season!.seasonNumber} · ${_seasonCountdownLabel(_season!, s)}',
                            style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: t.muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabs,
              labelColor: NeedHubTokens.forest,
              unselectedLabelColor: t.muted,
              indicatorColor: NeedHubTokens.forest,
              labelStyle: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w700),
              tabs: [Tab(text: s.leaderboard), Tab(text: s.hallOfImpact), Tab(text: s.previousSeasons)],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: const [_LeaderboardTab(), _HallOfImpactTab(), _PreviousSeasonsTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _seasonCountdownLabel(SeasonInfo season, S s) {
  final days = season.remaining.inDays;
  if (days <= 0) return s.endingSoon;
  return days == 1 ? '1 ${s.dayLeft}' : '$days ${s.daysLeft}';
}

// ── Leaderboard tab ────────────────────────────────────────────────────────

class _LeaderboardTab extends ConsumerStatefulWidget {
  const _LeaderboardTab();

  @override
  ConsumerState<_LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends ConsumerState<_LeaderboardTab> {
  String _scope = 'global';
  bool _loading = true;
  String? _error;
  List<LeaderboardEntry> _rows = const [];
  MyRank? _myRank;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(leagueApiProvider);
      final results = await Future.wait([api.leaderboard(scope: _scope), api.myRank()]);
      if (!mounted) return;
      setState(() {
        _rows = results[0] as List<LeaderboardEntry>;
        _myRank = results[1] as MyRank;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = S.current.somethingWentWrong;
      });
    }
  }

  void _setScope(String scope) {
    if (scope == _scope) return;
    setState(() => _scope = scope);
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Row(
            children: [
              Expanded(child: _ScopeChip(label: s.global, selected: _scope == 'global', onTap: () => _setScope('global'), t: t)),
              const SizedBox(width: 8),
              Expanded(child: _ScopeChip(label: s.friends, selected: _scope == 'friends', onTap: () => _setScope('friends'), t: t)),
            ],
          ),
          const SizedBox(height: 14),
          if (_myRank != null) _MyRankCard(rank: _myRank!, t: t, s: s),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Text(_error!, style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted)),
              ),
            )
          else if (_rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  _scope == 'friends' ? s.noFriendsOnLeaderboardYet : s.noSeasonActivityYet,
                  style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ..._rows.map((row) => _LeaderboardRow(entry: row, t: t)),
        ],
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final NeedHubTokens t;

  const _ScopeChip({required this.label, required this.selected, required this.onTap, required this.t});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? NeedHubTokens.forest.withValues(alpha: 0.12) : t.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? NeedHubTokens.forest : t.rail, width: 1.2),
        ),
        child: Text(
          label,
          style: GoogleFonts.hankenGrotesk(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? NeedHubTokens.forest : t.ink,
          ),
        ),
      ),
    );
  }
}

class _MyRankCard extends StatelessWidget {
  final MyRank rank;
  final NeedHubTokens t;
  final S s;

  const _MyRankCard({required this.rank, required this.t, required this.s});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.rail, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.myRank, style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: t.muted)),
                const SizedBox(height: 4),
                Text(
                  rank.rank != null ? '#${rank.rank}' : s.notRankedYet,
                  style: GoogleFonts.hankenGrotesk(fontSize: 20, fontWeight: FontWeight.w800, color: t.ink),
                ),
                Text(
                  '${rank.seasonPoints} ${s.impactPointsThisSeason}',
                  style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w600, color: t.muted),
                ),
              ],
            ),
          ),
          if (rank.nearestMilestone != null) NhMotivationHint(hint: rank.nearestMilestone, t: t),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final NeedHubTokens t;

  const _LeaderboardRow({required this.entry, required this.t});

  @override
  Widget build(BuildContext context) {
    final initial = entry.displayName.isNotEmpty ? entry.displayName[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${entry.rank}',
              style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w700, color: t.muted),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: t.card, shape: BoxShape.circle, border: Border.all(color: t.rail)),
            child: Text(initial, style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w700, color: t.ink)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.displayName,
              style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w700, color: t.ink),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (entry.badgeId != null) ...[
            Icon(Icons.emoji_events_rounded, size: 16, color: _medalColorForRank(entry.rank)),
            const SizedBox(width: 6),
          ],
          Text(
            '${entry.seasonPoints}',
            style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w800, color: t.ink),
          ),
        ],
      ),
    );
  }
}

Color _medalColorForRank(int rank) {
  switch (rank) {
    case 1:
      return const Color(0xFFC9971A);
    case 2:
      return const Color(0xFF8A94A6);
    case 3:
      return const Color(0xFFAD6A3A);
    default:
      return const Color(0xFF6B3FA0);
  }
}

// ── Hall of Impact tab ─────────────────────────────────────────────────────

class _HallOfImpactTab extends ConsumerStatefulWidget {
  const _HallOfImpactTab();

  @override
  ConsumerState<_HallOfImpactTab> createState() => _HallOfImpactTabState();
}

class _HallOfImpactTabState extends ConsumerState<_HallOfImpactTab> {
  bool _loading = true;
  List<HallOfImpactEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final entries = await ref.read(leagueApiProvider).hallOfImpact();
      if (mounted) setState(() { _entries = entries; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            s.hallOfImpactEmpty,
            style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final bySeasons = <String, List<HallOfImpactEntry>>{};
    for (final e in _entries) {
      final key = '${e.seasonNumber}·${e.year}';
      bySeasons.putIfAbsent(key, () => []).add(e);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: bySeasons.entries.map((group) {
          final rows = group.value..sort((a, b) => a.rank.compareTo(b.rank));
          final first = rows.first;
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s.season} ${first.seasonNumber} · ${first.year}',
                  style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w800, color: t.ink),
                ),
                const SizedBox(height: 8),
                ...rows.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.emoji_events_rounded, size: 18, color: _medalColorForRank(e.rank)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              e.displayName,
                              style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w700, color: t.ink),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text('#${e.rank}', style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w700, color: t.muted)),
                        ],
                      ),
                    )),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Previous Seasons (archive browser) ─────────────────────────────────────

class _PreviousSeasonsTab extends ConsumerStatefulWidget {
  const _PreviousSeasonsTab();

  @override
  ConsumerState<_PreviousSeasonsTab> createState() => _PreviousSeasonsTabState();
}

class _PreviousSeasonsTabState extends ConsumerState<_PreviousSeasonsTab> {
  bool _loading = true;
  List<SeasonInfo> _seasons = const [];
  // When set, shows that season's final leaderboard instead of the list.
  SeasonArchive? _selected;
  bool _loadingDetail = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final seasons = await ref.read(leagueApiProvider).seasons();
      if (mounted) setState(() { _seasons = seasons; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(SeasonInfo season) async {
    if (season.status != 'ARCHIVED') return; // current season has no archive yet
    setState(() => _loadingDetail = true);
    try {
      final archive = await ref.read(leagueApiProvider).archive(season.seasonNumber);
      if (mounted) setState(() { _selected = archive; _loadingDetail = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final selected = _selected;
    if (selected != null) {
      return _SeasonArchiveDetail(
        archive: selected,
        t: t,
        s: s,
        onBack: () => setState(() => _selected = null),
      );
    }

    if (_seasons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            s.noPreviousSeasonsYet,
            style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: _seasons.map((season) {
          final isArchived = season.status == 'ARCHIVED';
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: isArchived ? () => _open(season) : null,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.rail, width: 1),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${s.season} ${season.seasonNumber} · ${season.year}',
                        style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w700, color: t.ink),
                      ),
                    ),
                    if (!isArchived)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: NeedHubTokens.forest.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          s.currentSeasonBadge,
                          style: GoogleFonts.hankenGrotesk(fontSize: 10.5, fontWeight: FontWeight.w700, color: NeedHubTokens.forest),
                        ),
                      )
                    else if (_loadingDetail)
                      const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      Icon(Icons.chevron_right_rounded, color: t.muted),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SeasonArchiveDetail extends StatelessWidget {
  final SeasonArchive archive;
  final NeedHubTokens t;
  final S s;
  final VoidCallback onBack;

  const _SeasonArchiveDetail({required this.archive, required this.t, required this.s, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final season = archive.season;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: GestureDetector(
            onTap: onBack,
            child: Row(
              children: [
                Icon(Icons.arrow_back_rounded, size: 18, color: t.muted),
                const SizedBox(width: 6),
                Text(
                  season != null ? '${s.season} ${season.seasonNumber} · ${season.year}' : s.previousSeasons,
                  style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w800, color: t.ink),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: archive.rows.map((row) => _LeaderboardRow(entry: row, t: t)).toList(),
          ),
        ),
      ],
    );
  }
}
