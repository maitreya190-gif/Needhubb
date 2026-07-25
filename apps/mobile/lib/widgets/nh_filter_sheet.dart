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

  @override
  void initState() {
    super.initState();
    _draft = _notifier.value;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final showBudget = widget.surface == 'earn';
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SingleChildScrollView(
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
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    'Filter',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: t.ink,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() => _draft = const FeedFilter());
                    },
                    child: Text('Reset',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: NeedHubTokens.clay)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Distance
              _SectionLabel(label: 'MAX DISTANCE', t: t),
              Row(
                children: [
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: NeedHubTokens.clay,
                        inactiveTrackColor: t.rail,
                        thumbColor: NeedHubTokens.clay,
                        overlayColor:
                            NeedHubTokens.clay.withValues(alpha: 0.15),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _draft.maxDistanceKm,
                        min: 1,
                        max: 25,
                        divisions: 24,
                        onChanged: (v) => setState(() =>
                            _draft = _draft.copyWith(maxDistanceKm: v)),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${_draft.maxDistanceKm.toInt()} km',
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: NeedHubTokens.clay,
                      ),
                    ),
                  ),
                ],
              ),

              if (showBudget) ...[
                const SizedBox(height: 16),
                _SectionLabel(label: 'BUDGET RANGE (₹)', t: t),
                Row(
                  children: [
                    Expanded(
                      child: _BudgetField(
                        label: 'Min',
                        value: _draft.minBudget,
                        onChanged: (v) => setState(
                            () => _draft = _draft.copyWith(minBudget: v)),
                        t: t,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _BudgetField(
                        label: 'Max',
                        value: _draft.maxBudget,
                        onChanged: (v) => setState(
                            () => _draft = _draft.copyWith(maxBudget: v)),
                        t: t,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 20),
              _SectionLabel(label: 'GENDER (POSTER)', t: t),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const ['Female', 'Male', 'Non-binary'].map((g) {
                  final selected = _draft.genders.contains(g);
                  return _GChip(
                    label: g,
                    selected: selected,
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

              const SizedBox(height: 20),
              _SectionLabel(
                label: showBudget ? 'SKILL / CATEGORY' : 'SHARED INTERESTS',
                t: t,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: (showBudget
                    ? const [
                        'Design', 'Dev', 'Photography', 'Tutoring',
                        'Moving', 'Events', 'Music', 'Writing',
                      ]
                    : const [
                        'Flutter', 'DSA', 'Coffee', 'Startups', 'Trekking',
                        'Photography', 'Chess', 'Anime', 'Guitar', 'Lifting',
                      ])
                    .map((i) {
                  final selected = _draft.interests.contains(i);
                  return _GChip(
                    label: i,
                    selected: selected,
                    onTap: () {
                      setState(() {
                        final next = {..._draft.interests};
                        if (selected) {
                          next.remove(i);
                        } else {
                          next.add(i);
                        }
                        _draft = _draft.copyWith(interests: next);
                      });
                    },
                    t: t,
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),
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
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Apply filters',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final NeedHubTokens t;
  const _SectionLabel({required this.label, required this.t});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label,
        style: GoogleFonts.hankenGrotesk(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: t.muted2,
          letterSpacing: 0.7,
        ),
      ),
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
        text: widget.value == null ? '' : widget.value.toString());
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
              GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
          prefixIcon: Icon(Icons.currency_rupee_rounded,
              size: 16, color: t.muted),
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

class _GChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final NeedHubTokens t;

  const _GChip({
    required this.label,
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
        child: Text(
          label,
          style: GoogleFonts.hankenGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? NeedHubTokens.clay : t.muted2,
          ),
        ),
      ),
    );
  }
}
