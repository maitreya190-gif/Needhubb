import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_strings.dart';
import '../services/profiles_api.dart';
import '../services/vouches_api.dart';
import '../theme/tokens.dart';

/// Skills + vouch counts + verified badge + testimonials, for a profile.
///
/// Everything shown here is exactly what the server sent — no credibility
/// weight, no AI reasoning, no suspicious flag; those never leave the API
/// (see lib/vouching.ts on the backend). This widget only renders and, when
/// [onVouch] is supplied, lets the viewer act — it never decides on its own
/// whether an endorsement is warranted.
class NhSkillVouchSection extends StatelessWidget {
  final List<SkillEntry> skills;
  final Map<String, SkillVouchSummary> skillVouches;
  final NeedHubTokens t;

  /// Vouch ids the viewer has already given for this profile's skills,
  /// keyed by skillId — lets each row switch from "Vouch" to "Edit".
  /// Omitted (or empty) on your own profile, where vouching is disabled.
  final Map<String, String> myVouchIdsBySkill;

  /// Called when the viewer taps to vouch or edit their vouch for a skill.
  /// Null on your own profile — you cannot vouch for yourself.
  final void Function(SkillEntry skill, String? existingVouchId)? onVouch;

  const NhSkillVouchSection({
    super.key,
    required this.skills,
    required this.skillVouches,
    required this.t,
    this.myVouchIdsBySkill = const {},
    this.onVouch,
  });

  @override
  Widget build(BuildContext context) {
    if (skills.isEmpty) {
      return Text(
        S.current.noSkillsListedYet,
        style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted2),
      );
    }
    // Vouched-for skills first — a stable partition (not .sort, which isn't
    // guaranteed stable) so skills within each group keep their original order.
    bool hasVouches(SkillEntry s) => (skillVouches[s.id]?.vouchCount ?? 0) > 0;
    final ordered = [
      ...skills.where(hasVouches),
      ...skills.where((s) => !hasVouches(s)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: ordered
          .map((skill) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SkillVouchRow(
                  skill: skill,
                  summary: skillVouches[skill.id],
                  t: t,
                  existingVouchId: myVouchIdsBySkill[skill.id],
                  onVouch: onVouch == null
                      ? null
                      : () => onVouch!(skill, myVouchIdsBySkill[skill.id]),
                ),
              ))
          .toList(),
    );
  }
}

class _SkillVouchRow extends StatefulWidget {
  final SkillEntry skill;
  final SkillVouchSummary? summary;
  final NeedHubTokens t;
  final String? existingVouchId;
  final VoidCallback? onVouch;

  const _SkillVouchRow({
    required this.skill,
    required this.summary,
    required this.t,
    required this.existingVouchId,
    required this.onVouch,
  });

  @override
  State<_SkillVouchRow> createState() => _SkillVouchRowState();
}

class _SkillVouchRowState extends State<_SkillVouchRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final summary = widget.summary;
    final vouchCount = summary?.vouchCount ?? 0;
    final verifiedCount = summary?.verifiedVouchCount ?? 0;
    final hasTestimonials =
        summary != null && summary.recentVouchers.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.rail, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: hasTestimonials
                      ? () => setState(() => _expanded = !_expanded)
                      : null,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.skill.label,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: t.ink,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (verifiedCount > 0) ...[
                        const SizedBox(width: 6),
                        _VerifiedChip(t: t),
                      ],
                    ],
                  ),
                ),
              ),
              Text(
                vouchCount == 0
                    ? S.current.noVouchesYet
                    : '$vouchCount ${S.current.vouchCountUnit}${vouchCount == 1 ? '' : 'es'}',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: vouchCount == 0 ? t.muted : t.muted2,
                ),
              ),
              if (widget.onVouch != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onVouch,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: widget.existingVouchId != null
                          ? t.rail
                          : NeedHubTokens.forest.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.existingVouchId != null ? S.current.edit : S.current.vouch,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: widget.existingVouchId != null
                            ? t.ink
                            : NeedHubTokens.forest,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_expanded && hasTestimonials) ...[
            const SizedBox(height: 8),
            Divider(color: t.rail, height: 1),
            const SizedBox(height: 8),
            ...summary.recentVouchers.map((v) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            v.voucherName,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: t.ink,
                            ),
                          ),
                          if (v.verified) ...[
                            const SizedBox(width: 5),
                            _VerifiedChip(t: t, compact: true),
                          ],
                        ],
                      ),
                      if (v.testimonial != null &&
                          v.testimonial!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '"${v.testimonial}"',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: t.muted2,
                          ),
                        ),
                      ],
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _VerifiedChip extends StatelessWidget {
  final NeedHubTokens t;
  final bool compact;
  const _VerifiedChip({required this.t, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 6, vertical: compact ? 1 : 2),
      decoration: BoxDecoration(
        color: NeedHubTokens.forest.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded,
              size: compact ? 10 : 11, color: NeedHubTokens.forest),
          const SizedBox(width: 2),
          Text(
            S.current.verified,
            style: GoogleFonts.hankenGrotesk(
              fontSize: compact ? 9.5 : 10,
              fontWeight: FontWeight.w700,
              color: NeedHubTokens.forest,
            ),
          ),
        ],
      ),
    );
  }
}
