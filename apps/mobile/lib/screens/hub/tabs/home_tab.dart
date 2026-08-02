import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../l10n/app_strings.dart';
import '../../../models/need.dart';
import '../../../models/user_state.dart';
import '../../../providers/language_provider.dart';
import '../../../services/needs_api.dart';
import '../../../services/social_providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/nh_urgent_badge.dart';
import '../../needs/need_detail_screen.dart';

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  String _selectedCategory = 'all';
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'newest';
  int? _maxBudget;

  @override
  void initState() {
    super.initState();
    needsNotifier.addListener(_onNeedsChanged);
    feedNeedsNotifier.addListener(_onNeedsChanged);
    uiLanguageNotifier.addListener(_bump);
  }

  void _bump() {
    if (mounted) setState(() {});
  }

  void _onNeedsChanged() => setState(() {});

  @override
  void dispose() {
    needsNotifier.removeListener(_onNeedsChanged);
    feedNeedsNotifier.removeListener(_onNeedsChanged);
    uiLanguageNotifier.removeListener(_bump);
    _searchController.dispose();
    super.dispose();
  }

  List<Need> get _filtered {
    var needs = List<Need>.from(feedNeedsNotifier.value)
        .where((n) => n.authorName != 'You' && n.authorInitials != 'ME')
        .toList();
    if (_selectedCategory != 'all') {
      needs = needs.where((n) => n.category == _selectedCategory).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      needs = needs.where((n) =>
        n.title.toLowerCase().contains(q) ||
        n.description.toLowerCase().contains(q) ||
        n.tags.any((t) => t.toLowerCase().contains(q)),
      ).toList();
    }
    if (_maxBudget != null) {
      needs = needs.where((n) =>
        n.budgetMin == null || (n.budgetMin! <= _maxBudget!),
      ).toList();
    }
    switch (_sortBy) {
      case 'budget':
        needs.sort((a, b) => (b.budgetMax ?? 0).compareTo(a.budgetMax ?? 0));
        break;
      case 'oldest':
        needs = needs.reversed.toList();
        break;
      default: // newest — already in insertion order (newest appended last)
        needs = needs.reversed.toList();
    }
    return needs;
  }

  Future<void> _showFilter() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        sortBy: _sortBy,
        maxBudget: _maxBudget,
        onApply: (sort, budget) {
          setState(() {
            _sortBy = sort;
            _maxBudget = budget;
          });
        },
      ),
    );
  }

  bool get _hasActiveFilter => _sortBy != 'newest' || _maxBudget != null;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;

    return Scaffold(
      backgroundColor: t.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 20, 0),
              child: Row(
                children: [
                  if (Navigator.canPop(context))
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.arrow_back_rounded, color: t.ink, size: 22),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  Expanded(
                    child: Text(
                      'NeedHub',
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: t.ink,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _showFilter,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _hasActiveFilter
                            ? NeedHubTokens.clay
                            : t.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _hasActiveFilter ? NeedHubTokens.clay : t.rail,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        size: 18,
                        color: _hasActiveFilter ? Colors.white : t.muted2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: t.rail, width: 1.5),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(Icons.search_rounded, size: 18, color: t.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 14,
                          color: t.ink,
                        ),
                        decoration: InputDecoration(
                          hintText: s.searchNeedsNearYou,
                          hintStyle: GoogleFonts.hankenGrotesk(
                            fontSize: 14,
                            color: t.muted,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          filled: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Category chips
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _CategoryChip(
                    label: s.allCategory,
                    value: 'all',
                    selected: _selectedCategory == 'all',
                    onTap: () => setState(() => _selectedCategory = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _CategoryChip(
                    label: s.connect,
                    value: 'connect',
                    selected: _selectedCategory == 'connect',
                    onTap: () => setState(() => _selectedCategory = 'connect'),
                    color: NeedHubTokens.forest,
                  ),
                  const SizedBox(width: 8),
                  _CategoryChip(
                    label: s.earn,
                    value: 'earn',
                    selected: _selectedCategory == 'earn',
                    onTap: () => setState(() => _selectedCategory = 'earn'),
                    color: NeedHubTokens.ochre,
                  ),
                  const SizedBox(width: 8),
                  _CategoryChip(
                    label: s.chitchatLabel,
                    value: 'chitchat',
                    selected: _selectedCategory == 'chitchat',
                    onTap: () => setState(() => _selectedCategory = 'chitchat'),
                    color: NeedHubTokens.clay,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_selectedCategory == 'chitchat') _HomeChitChatControlCard(t: t),

            // Feed
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded, size: 40, color: t.muted),
                          const SizedBox(height: 12),
                          Text(
                            s.noNeedsFound,
                            style: GoogleFonts.bricolageGrotesque(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: t.ink,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            s.tryDifferentFilter,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 14,
                              color: t.muted,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => NeedCard(
                        need: _filtered[i],
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => NeedDetailScreen(need: _filtered[i]),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Category chip ─────────────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _CategoryChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final activeColor = color ?? NeedHubTokens.clay;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? activeColor : t.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? activeColor : t.rail,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.hankenGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : t.muted2,
          ),
        ),
      ),
    );
  }
}

// ── Need card ─────────────────────────────────────────────────────────────────

class NeedCard extends StatelessWidget {
  final Need need;
  final VoidCallback onTap;

  const NeedCard({super.key, required this.need, required this.onTap});

  Color _categoryColor() {
    switch (need.category) {
      case 'earn': return NeedHubTokens.ochre;
      case 'chitchat': return NeedHubTokens.clay;
      default: return NeedHubTokens.forest;
    }
  }

  String _categoryLabel(S s) {
    switch (need.category) {
      case 'earn': return s.earn;
      case 'chitchat': return s.chitchatLabel;
      default: return s.connect;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;
    final cat = _categoryColor();
    final catLabel = _categoryLabel(s);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.rail, width: 1),
          boxShadow: NeedHubThemes.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category badge + time
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cat.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    catLabel,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cat,
                    ),
                  ),
                ),
                if (need.isUrgent) ...[
                  const SizedBox(width: 6),
                  NhUrgentBadge(need: need, compact: true),
                ],
                const Spacer(),
                Text(
                  need.timeAgo,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 12,
                    color: t.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Title
            Text(
              need.title,
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),

            // Description
            Text(
              need.description,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 13,
                color: t.muted2,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            if (need.budgetMin != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.currency_rupee_rounded, size: 14, color: NeedHubTokens.ochre),
                  const SizedBox(width: 2),
                  Text(
                    '₹${need.budgetMin}–₹${need.budgetMax}',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: NeedHubTokens.ochre,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Footer: author + location
            Row(
              children: [
                // Avatar
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: cat.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    need.authorInitials,
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cat,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    need.authorName,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.location_on_outlined, size: 13, color: t.muted),
                const SizedBox(width: 2),
                Text(
                  need.distanceLabel,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 12,
                    color: t.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Filter sheet ──────────────────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  final String sortBy;
  final int? maxBudget;
  final void Function(String sort, int? budget) onApply;

  const _FilterSheet({
    required this.sortBy,
    required this.maxBudget,
    required this.onApply,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _sortBy;
  late double _budgetSlider;
  bool _budgetFilterOn = false;

  @override
  void initState() {
    super.initState();
    _sortBy = widget.sortBy;
    _budgetFilterOn = widget.maxBudget != null;
    _budgetSlider = (widget.maxBudget ?? 1000).toDouble();
    uiLanguageNotifier.addListener(_bump);
  }

  void _bump() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    uiLanguageNotifier.removeListener(_bump);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
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
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                s.filterAndSort,
                style: GoogleFonts.bricolageGrotesque(
                    fontSize: 20, fontWeight: FontWeight.w800, color: t.ink),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  widget.onApply('newest', null);
                  Navigator.pop(context);
                },
                child: Text(
                  s.reset,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: NeedHubTokens.clay),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Text(s.sortByUpper,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: t.muted2,
                  letterSpacing: 0.7)),
          const SizedBox(height: 10),
          ...[
            ('newest', s.newestFirst, Icons.access_time_rounded),
            ('oldest', s.oldestFirst, Icons.history_rounded),
            ('budget', s.highestBudget, Icons.currency_rupee_rounded),
          ].map((opt) => GestureDetector(
                onTap: () => setState(() => _sortBy = opt.$1),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _sortBy == opt.$1
                        ? NeedHubTokens.clay.withValues(alpha: 0.08)
                        : t.paper,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: _sortBy == opt.$1
                          ? NeedHubTokens.clay.withValues(alpha: 0.4)
                          : t.rail,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(opt.$3,
                          size: 17,
                          color: _sortBy == opt.$1
                              ? NeedHubTokens.clay
                              : t.muted2),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(opt.$2,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _sortBy == opt.$1
                                  ? NeedHubTokens.clay
                                  : t.ink,
                            )),
                      ),
                      if (_sortBy == opt.$1)
                        const Icon(Icons.check_circle_rounded,
                            color: NeedHubTokens.clay, size: 17),
                    ],
                  ),
                ),
              )),

          const SizedBox(height: 16),
          Row(
            children: [
              Text(s.maxBudgetUpper,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: t.muted2,
                      letterSpacing: 0.7)),
              const Spacer(),
              Switch(
                value: _budgetFilterOn,
                onChanged: (v) => setState(() => _budgetFilterOn = v),
                activeThumbColor: NeedHubTokens.clay,
              ),
            ],
          ),
          if (_budgetFilterOn) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(s.upTo,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 13, color: t.muted)),
                Text('₹${_budgetSlider.toInt()}',
                    style: GoogleFonts.bricolageGrotesque(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: NeedHubTokens.ochre)),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: NeedHubTokens.ochre,
                inactiveTrackColor: t.rail,
                thumbColor: NeedHubTokens.ochre,
                overlayColor: NeedHubTokens.ochre.withValues(alpha: 0.15),
                trackHeight: 4,
              ),
              child: Slider(
                value: _budgetSlider,
                min: 100,
                max: 5000,
                divisions: 49,
                onChanged: (v) => setState(() => _budgetSlider = v),
              ),
            ),
          ],

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                widget.onApply(
                  _sortBy,
                  _budgetFilterOn ? _budgetSlider.toInt() : null,
                );
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: NeedHubTokens.clay,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle: GoogleFonts.hankenGrotesk(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              child: Text(s.applyFilters),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeChitChatControlCard extends ConsumerStatefulWidget {
  final NeedHubTokens t;
  const _HomeChitChatControlCard({required this.t});

  @override
  ConsumerState<_HomeChitChatControlCard> createState() =>
      _HomeChitChatControlCardState();
}

class _HomeChitChatControlCardState
    extends ConsumerState<_HomeChitChatControlCard> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    chitChatAvailableNotifier.addListener(_bump);
    uiLanguageNotifier.addListener(_bump);
  }

  @override
  void dispose() {
    chitChatAvailableNotifier.removeListener(_bump);
    uiLanguageNotifier.removeListener(_bump);
    super.dispose();
  }

  void _bump() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final s = S.current;
    final available = chitChatAvailableNotifier.value;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                final api = ref.read(chitchatApiProvider);
                try {
                  if (available) {
                    await api.clearAvailability();
                    chitChatAvailableNotifier.value = false;
                  } else {
                    await api.setAvailability(4);
                    chitChatAvailableNotifier.value = true;
                  }
                  chitchatRosterNotifier.value = await api.availablePeople();
                } catch (_) {}
                if (mounted) setState(() => _busy = false);
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      ? s.youreAvailableForChat
                      : s.markYourselfAvailableChat,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: available ? Colors.white : t.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
