import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/profiles_api.dart';
import '../services/social_providers.dart';
import '../services/vouches_api.dart';
import '../theme/tokens.dart';
import 'nh_vouch_sheet.dart';

/// Opened from a completed Need — lets the poster/helper pick which of the
/// counterparty's skills to vouch for, with AI-suggested ones surfaced
/// first (requirement 3: assistance only). Picking a skill hands off to
/// [NhVouchSheet]; nothing is ever submitted from this screen directly.
class NhVouchPickerSheet extends ConsumerStatefulWidget {
  final String needId;
  final String voucheeId;
  final String voucheeName;

  const NhVouchPickerSheet({
    super.key,
    required this.needId,
    required this.voucheeId,
    required this.voucheeName,
  });

  static Future<void> open(
    BuildContext context, {
    required String needId,
    required String voucheeId,
    required String voucheeName,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NhVouchPickerSheet(
        needId: needId,
        voucheeId: voucheeId,
        voucheeName: voucheeName,
      ),
    );
  }

  @override
  ConsumerState<NhVouchPickerSheet> createState() => _NhVouchPickerSheetState();
}

class _NhVouchPickerSheetState extends ConsumerState<NhVouchPickerSheet> {
  bool _loading = true;
  String? _error;
  List<SkillEntry> _allSkills = const [];
  Set<String> _suggestedIds = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profilesApi = ref.read(profilesApiProvider);
      final vouchesApi = ref.read(vouchesApiProvider);

      final profile = await profilesApi.getById(widget.voucheeId);
      // Suggestions are best-effort — a completed need with no embedding
      // service configured, or one the caller wasn't actually part of,
      // simply yields no suggestions rather than blocking the picker.
      List<SuggestedSkill> suggested = const [];
      try {
        suggested = await vouchesApi.suggest(
          needId: widget.needId,
          voucheeId: widget.voucheeId,
        );
      } catch (_) {/* fall back to the plain skill list, unranked */}

      if (!mounted) return;
      setState(() {
        _allSkills = profile.skillEntries;
        _suggestedIds = suggested.map((s) => s.id).toSet();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load ${widget.voucheeName}\'s skills right now.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final suggested =
        _allSkills.where((s) => _suggestedIds.contains(s.id)).toList();
    final rest =
        _allSkills.where((s) => !_suggestedIds.contains(s.id)).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                    color: t.rail, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Vouch for ${widget.voucheeName}',
              style: GoogleFonts.bricolageGrotesque(
                  fontSize: 19, fontWeight: FontWeight.w800, color: t.ink),
            ),
            const SizedBox(height: 4),
            Text(
              'Which skill did they actually demonstrate on this need?',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 13, color: t.muted2),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 13, color: Colors.orange.shade800))
            else if (_allSkills.isEmpty)
              Text(
                '${widget.voucheeName} hasn\'t listed any skills yet.',
                style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted2),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (suggested.isNotEmpty) ...[
                        _SectionLabel(
                            text: 'AI-SUGGESTED FOR THIS NEED', t: t),
                        const SizedBox(height: 8),
                        ...suggested.map((s) => _SkillOption(
                              skill: s,
                              highlighted: true,
                              t: t,
                              onTap: () => _pick(s),
                            )),
                        if (rest.isNotEmpty) const SizedBox(height: 14),
                      ],
                      if (rest.isNotEmpty) ...[
                        if (suggested.isNotEmpty)
                          _SectionLabel(text: 'OTHER SKILLS', t: t),
                        if (suggested.isNotEmpty) const SizedBox(height: 8),
                        ...rest.map((s) => _SkillOption(
                              skill: s,
                              highlighted: false,
                              t: t,
                              onTap: () => _pick(s),
                            )),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(SkillEntry skill) async {
    Navigator.of(context).pop();
    await NhVouchSheet.open(
      context,
      voucheeId: widget.voucheeId,
      voucheeName: widget.voucheeName,
      skillId: skill.id,
      skillLabel: skill.label,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final NeedHubTokens t;
  const _SectionLabel({required this.text, required this.t});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.hankenGrotesk(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: t.muted2,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _SkillOption extends StatelessWidget {
  final SkillEntry skill;
  final bool highlighted;
  final NeedHubTokens t;
  final VoidCallback onTap;

  const _SkillOption({
    required this.skill,
    required this.highlighted,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: highlighted
                ? NeedHubTokens.forest.withValues(alpha: 0.08)
                : t.paper,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlighted
                  ? NeedHubTokens.forest.withValues(alpha: 0.30)
                  : t.rail,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              if (highlighted) ...[
                const Icon(Icons.auto_awesome_rounded,
                    size: 15, color: NeedHubTokens.forest),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  skill.label,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: t.muted),
            ],
          ),
        ),
      ),
    );
  }
}
