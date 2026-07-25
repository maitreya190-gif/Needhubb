import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_state.dart';
import '../theme/tokens.dart';

class NhFilterSheet extends StatefulWidget {
  final String surface; // 'earn' | 'connect'

  const NhFilterSheet({super.key, required this.surface});

  static Future<void> open(BuildContext context, {required String surface}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NhFilterSheet(surface: surface),
    );
  }

  @override
  State<NhFilterSheet> createState() => _NhFilterSheetState();
}

class _NhFilterSheetState extends State<NhFilterSheet> {
  late FeedFilter _draft;

  ValueNotifier<FeedFilter> get _notifier =>
      widget.surface == 'earn' ? earnFilterNotifier : connectFilterNotifier;

  static const _availableInterests = [
    'Flutter',
    'DSA',
    'Coffee',
    'Startups',
    'Trekking',
    'Photography',
    'Chess',
    'Anime',
    'Guitar',
    'Lifting',
    'Movies',
    'Cooking',
    'Art',
    'Gaming',
    'Science',
  ];

  static const _availableSkills = [
    'Tutoring',
    'UI Design',
    'Flutter',
    'Java',
    'Python',
    'Video editing',
    'Writing',
    'Math',
    'Music',
    'Repair',
    'Note-taking',
    'Proofreading',
    'Design',
    'Dev',
  ];

  @override
  void initState() {
    super.initState();
    // Copy the current active filter values into draft state so user can edit them!
    _draft = _notifier.value;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isEarn = widget.surface == 'earn';
    final activeCount = _draft.filterCount;

    final allInterests = {
      ..._availableInterests,
      ...customInterestsNotifier.value,
    }.toList();

    final allSkills = {
      ..._availableSkills,
      ...customSkillsNotifier.value,
    }.toList();

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: t.rail, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: t.rail,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filter & Sort',
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Adjust feasibility, interests, skills & gender',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 12,
                        color: t.muted2,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (activeCount > 0)
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _draft = const FeedFilter());
                    },
                    icon: const Icon(Icons.refresh_rounded,
                        size: 15, color: NeedHubTokens.clay),
                    label: Text(
                      'Reset All',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: NeedHubTokens.clay,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: t.rail, height: 1),
            const SizedBox(height: 14),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 1. FEASIBILITY & DISTANCE ───────────────────────────
                    _SectionHeader(
                      title: 'FEASIBILITY & LOCATION',
                      subtitle: 'Set maximum distance radius and budget limits',
                      icon: Icons.location_on_outlined,
                      t: t,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: NeedHubTokens.forest,
                              inactiveTrackColor: t.rail,
                              thumbColor: NeedHubTokens.forest,
                              overlayColor: NeedHubTokens.forest
                                  .withValues(alpha: 0.15),
                              trackHeight: 4,
                            ),
                            child: Slider(
                              value: _draft.maxDistanceKm.clamp(1, 50),
                              min: 1,
                              max: 50,
                              divisions: 49,
                              onChanged: (v) => setState(() =>
                                  _draft = _draft.copyWith(maxDistanceKm: v)),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: NeedHubTokens.forest.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  NeedHubTokens.forest.withValues(alpha: 0.30),
                            ),
                          ),
                          child: Text(
                            _draft.maxDistanceKm >= 50
                                ? '50+ km (Any)'
                                : '${_draft.maxDistanceKm.toInt()} km',
                            style: GoogleFonts.bricolageGrotesque(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: NeedHubTokens.forest,
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (isEarn) ...[
                      const SizedBox(height: 14),
                      Text(
                        'BUDGET RANGE (₹)',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: t.muted2,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _BudgetField(
                              label: 'Min budget',
                              value: _draft.minBudget,
                              onChanged: (v) => setState(() =>
                                  _draft = _draft.copyWith(minBudget: v)),
                              t: t,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _BudgetField(
                              label: 'Max budget',
                              value: _draft.maxBudget,
                              onChanged: (v) => setState(() =>
                                  _draft = _draft.copyWith(maxBudget: v)),
                              t: t,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 22),
                    Divider(color: t.rail, height: 1),
                    const SizedBox(height: 18),

                    // ── 2. INTERESTS ─────────────────────────────────────────
                    _SectionHeader(
                      title: 'INTERESTS',
                      subtitle: 'Filter profiles and needs matching topics you care about',
                      icon: Icons.interests_outlined,
                      t: t,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: allInterests.map((interest) {
                        final selected = _draft.interests.contains(interest);
                        return _FilterChip(
                          label: interest,
                          selected: selected,
                          color: NeedHubTokens.forest,
                          onTap: () {
                            setState(() {
                              final next = {..._draft.interests};
                              if (selected) {
                                next.remove(interest);
                              } else {
                                next.add(interest);
                              }
                              _draft = _draft.copyWith(interests: next);
                            });
                          },
                          t: t,
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 22),
                    Divider(color: t.rail, height: 1),
                    const SizedBox(height: 18),

                    // ── 3. SKILLS ────────────────────────────────────────────
                    _SectionHeader(
                      title: 'SKILLS',
                      subtitle: 'Filter by specific expertise and practical skills',
                      icon: Icons.psychology_outlined,
                      t: t,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: allSkills.map((skill) {
                        final selected = _draft.skills.contains(skill);
                        return _FilterChip(
                          label: skill,
                          selected: selected,
                          color: NeedHubTokens.ochre,
                          onTap: () {
                            setState(() {
                              final next = {..._draft.skills};
                              if (selected) {
                                next.remove(skill);
                              } else {
                                next.add(skill);
                              }
                              _draft = _draft.copyWith(skills: next);
                            });
                          },
                          t: t,
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 22),
                    Divider(color: t.rail, height: 1),
                    const SizedBox(height: 18),

                    // ── 4. GENDER ────────────────────────────────────────────
                    _SectionHeader(
                      title: 'GENDER PREFERENCE',
                      subtitle: 'Show profiles or posters of specific gender',
                      icon: Icons.people_outline_rounded,
                      t: t,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['Female', 'Male', 'Non-binary'].map((g) {
                        final selected = _draft.genders.contains(g);
                        return _FilterChip(
                          label: g,
                          selected: selected,
                          color: NeedHubTokens.clay,
                          onTap: () {
                            setState(() {
                              final next = {..._draft.genders};
                              if (selected) {
                                next.remove(g);
                              } else {
                                next.add(g);
                              }
                              _draft = _draft.copyWith(genders: next);
                            });
                          },
                          t: t,
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 22),
                    Divider(color: t.rail, height: 1),
                    const SizedBox(height: 18),

                    // ── 5. SORT BY ───────────────────────────────────────────
                    _SectionHeader(
                      title: 'SORT ORDER',
                      subtitle: 'Arrange items by recency, distance, or reward',
                      icon: Icons.sort_rounded,
                      t: t,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SortOption(
                          label: 'Newest first',
                          value: 'newest',
                          selected: _draft.sortBy == 'newest',
                          onTap: () => setState(
                              () => _draft = _draft.copyWith(sortBy: 'newest')),
                          t: t,
                        ),
                        _SortOption(
                          label: 'Nearest first',
                          value: 'nearest',
                          selected: _draft.sortBy == 'nearest',
                          onTap: () => setState(() =>
                              _draft = _draft.copyWith(sortBy: 'nearest')),
                          t: t,
                        ),
                        _SortOption(
                          label: 'Highest reward/points',
                          value: 'highest_points',
                          selected: _draft.sortBy == 'highest_points',
                          onTap: () => setState(() => _draft =
                              _draft.copyWith(sortBy: 'highest_points')),
                          t: t,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  _notifier.value = _draft;
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: NeedHubTokens.forest,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  activeCount > 0
                      ? 'Apply Filters ($activeCount)'
                      : 'Apply Filters',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final NeedHubTokens t;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: t.ink),
            const SizedBox(width: 6),
            Text(
              title,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: t.ink,
                letterSpacing: 0.7,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: GoogleFonts.hankenGrotesk(
            fontSize: 11.5,
            color: t.muted2,
          ),
        ),
      ],
    );
  }
}

class _BudgetField extends StatefulWidget {
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  final NeedHubTokens t;

  const _BudgetField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.t,
  });

  @override
  State<_BudgetField> createState() => _BudgetFieldState();
}

class _BudgetFieldState extends State<_BudgetField> {
  late TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(
      text: widget.value == null ? '' : widget.value.toString(),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Container(
      decoration: BoxDecoration(
        color: t.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.rail, width: 1.5),
      ),
      child: TextField(
        controller: _c,
        keyboardType: TextInputType.number,
        onChanged: (v) {
          final parsed = int.tryParse(v.trim());
          widget.onChanged(parsed);
        },
        style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
        decoration: InputDecoration(
          hintText: widget.label,
          hintStyle:
              GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted),
          prefixIcon: Icon(Icons.currency_rupee_rounded,
              size: 15, color: t.muted),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 30, minHeight: 30),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          filled: false,
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final NeedHubTokens t;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7.5),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? color : t.rail,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: 14, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? color : t.muted2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;
  final NeedHubTokens t;

  const _SortOption({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? NeedHubTokens.clay.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? NeedHubTokens.clay : t.rail,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 15,
              color: selected ? NeedHubTokens.clay : t.muted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? NeedHubTokens.clay : t.muted2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
