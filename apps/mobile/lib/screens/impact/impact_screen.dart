import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/need.dart';
import '../../services/needs_api.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';

class ImpactScreen extends StatefulWidget {
  const ImpactScreen({super.key});

  @override
  State<ImpactScreen> createState() => _ImpactScreenState();
}

class _ImpactScreenState extends State<ImpactScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        backgroundColor: t.paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Impact',
          style: GoogleFonts.bricolageGrotesque(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: t.ink,
          ),
        ),
        bottom: TabBar(
          controller: _tab,
          labelStyle: GoogleFonts.hankenGrotesk(
              fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle:
              GoogleFonts.hankenGrotesk(fontSize: 13),
          labelColor: NeedHubTokens.clay,
          unselectedLabelColor: t.muted,
          indicatorColor: NeedHubTokens.clay,
          indicatorWeight: 2,
          tabs: const [
            Tab(text: 'Certificates'),
            Tab(text: 'Achievements'),
            Tab(text: 'Redeem'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _CertificatesTab(t: t),
          _AchievementsTab(t: t),
          _RedeemTab(t: t),
        ],
      ),
    );
  }
}

// ── Certificates tab ──────────────────────────────────────────────────────────

class _CertificatesTab extends StatelessWidget {
  final NeedHubTokens t;

  const _CertificatesTab({required this.t});

  static const _certs = [
    (
      title: 'Community Volunteer',
      org: 'NeedHub × Teach India',
      status: 'verified',
      points: 80,
      date: 'Jun 2026',
    ),
    (
      title: 'Hackathon Mentor',
      org: 'InovaHack 2026',
      status: 'pending',
      points: 60,
      date: 'Jul 2026',
    ),
    (
      title: 'Skill Trainer',
      org: 'NeedHub Impact',
      status: 'upload',
      points: 40,
      date: null,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        // Points balance banner
        _PointsBanner(points: 240, t: t),
        const SizedBox(height: 20),
        ..._certs.map((c) => _CertCard(cert: c, t: t)),
      ],
    );
  }
}

class _PointsBanner extends StatelessWidget {
  final int points;
  final NeedHubTokens t;

  const _PointsBanner({required this.points, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            NeedHubTokens.ochre.withValues(alpha: 0.15),
            NeedHubTokens.clay.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: NeedHubTokens.ochre.withValues(alpha: 0.25), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: NeedHubTokens.ochre.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.stars_rounded,
                color: NeedHubTokens.ochre, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$points Impact Points',
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: t.ink,
                  ),
                ),
                Text(
                  '50 pts = 6h boost · 100 pts = 24h · 200 pts = 72h',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 12, color: t.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CertCard extends StatelessWidget {
  final ({
    String title,
    String org,
    String status,
    int points,
    String? date
  }) cert;
  final NeedHubTokens t;

  const _CertCard({required this.cert, required this.t});

  @override
  Widget build(BuildContext context) {
    final isVerified = cert.status == 'verified';
    final isPending = cert.status == 'pending';
    final isUpload = cert.status == 'upload';

    final statusColor = isVerified
        ? NeedHubTokens.forest
        : isPending
            ? NeedHubTokens.ochre
            : t.muted;

    final statusLabel = isVerified
        ? 'Verified'
        : isPending
            ? 'In Review'
            : 'Upload required';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
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
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isVerified
                    ? Icons.verified_rounded
                    : isPending
                        ? Icons.hourglass_top_rounded
                        : Icons.upload_file_outlined,
                color: statusColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cert.title,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cert.org,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 12, color: t.muted),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          statusLabel,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '+${cert.points} pts',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: NeedHubTokens.ochre,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isUpload)
              TextButton(
                onPressed: () {},
                child: Text(
                  'Upload',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: NeedHubTokens.clay,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Achievements tab ──────────────────────────────────────────────────────────

class _AchievementsTab extends StatelessWidget {
  final NeedHubTokens t;

  const _AchievementsTab({required this.t});

  static const _achievements = [
    (
      icon: Icons.handshake_outlined,
      label: 'First Help',
      desc: 'Helped someone for the first time',
      earned: true,
      color: NeedHubTokens.forest,
      pts: 20,
    ),
    (
      icon: Icons.star_rounded,
      label: '5-Star',
      desc: 'Received your first 5-star review',
      earned: true,
      color: NeedHubTokens.ochre,
      pts: 30,
    ),
    (
      icon: Icons.bolt_rounded,
      label: 'Quick Reply',
      desc: 'Responded to a need within 5 minutes',
      earned: true,
      color: NeedHubTokens.ochre,
      pts: 15,
    ),
    (
      icon: Icons.emoji_events_outlined,
      label: 'Top Helper',
      desc: 'Help 10 people in a month',
      earned: false,
      color: NeedHubTokens.clay,
      pts: 100,
    ),
    (
      icon: Icons.diversity_3_outlined,
      label: 'Connector',
      desc: 'Send 5 connect requests that get accepted',
      earned: false,
      color: NeedHubTokens.forest,
      pts: 50,
    ),
    (
      icon: Icons.military_tech_outlined,
      label: 'Impact Pro',
      desc: 'Upload 3 verified certificates',
      earned: false,
      color: NeedHubTokens.clay,
      pts: 150,
    ),
    (
      icon: Icons.local_fire_department_outlined,
      label: '7-Day Streak',
      desc: 'Be active on NeedHub for 7 days in a row',
      earned: false,
      color: NeedHubTokens.clay,
      pts: 70,
    ),
    (
      icon: Icons.groups_outlined,
      label: 'Community Pillar',
      desc: 'Help 25 different people',
      earned: false,
      color: NeedHubTokens.forest,
      pts: 200,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Row(
          children: [
            Text(
              '3 / 8 earned',
              style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ..._achievements
            .map((a) => _AchievementTile(achievement: a, t: t)),
      ],
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final ({
    IconData icon,
    String label,
    String desc,
    bool earned,
    Color color,
    int pts
  }) achievement;
  final NeedHubTokens t;

  const _AchievementTile({required this.achievement, required this.t});

  @override
  Widget build(BuildContext context) {
    final a = achievement;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: a.earned ? a.color.withValues(alpha: 0.07) : t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: a.earned ? a.color.withValues(alpha: 0.20) : t.rail,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: a.earned
                    ? a.color.withValues(alpha: 0.15)
                    : t.paper,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(a.icon,
                  color: a.earned ? a.color : t.muted, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.label,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: a.earned ? t.ink : t.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    a.desc,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 12, color: t.muted),
                  ),
                ],
              ),
            ),
            Text(
              '+${a.pts}',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: a.earned ? NeedHubTokens.ochre : t.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Redeem tab ────────────────────────────────────────────────────────────────

class _RedeemTab extends ConsumerStatefulWidget {
  final NeedHubTokens t;

  const _RedeemTab({required this.t});

  @override
  ConsumerState<_RedeemTab> createState() => _RedeemTabState();
}

class _RedeemTabState extends ConsumerState<_RedeemTab> {
  // Profile boost state
  bool _profileBoosted = false;

  // Need boost state
  String _selectedTier = '24h'; // '6h' | '24h' | '72h'
  bool _boosting = false;
  String? _boostedNeedId;
  DateTime? _boostExpiresAt;

  static const _tiers = [
    (id: '6h',  label: '6 Hours',  cost: 50,  icon: Icons.flash_on_rounded),
    (id: '24h', label: '24 Hours', cost: 100, icon: Icons.rocket_launch_outlined),
    (id: '72h', label: '3 Days',   cost: 200, icon: Icons.star_rounded),
  ];

  // Points balance (mock — real: fetch from profile API)
  int _balance = 240;

  int get _tierCost =>
      _tiers.firstWhere((t) => t.id == _selectedTier).cost;

  bool get _canBoost => _balance >= _tierCost && !_boosting;

  Future<void> _showBoostNeedSheet() async {
    final t = widget.t;
    // Get my posted needs from the feed notifier (open ones only)
    final myNeeds = feedNeedsNotifier.value
        .where((n) => n.authorInitials == 'ME' || n.authorName == 'You')
        .where((n) => !n.isFrozen)
        .toList();

    if (myNeeds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You don't have any open needs to boost."),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final selected = await showModalBottomSheet<Need>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _NeedPickerSheet(needs: myNeeds, t: t),
    );

    if (selected == null || !mounted) return;

    // Confirm dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _BoostConfirmDialog(
        need: selected,
        tier: _selectedTier,
        cost: _tierCost,
        balance: _balance,
        t: t,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _boosting = true);
    try {
      final api = ref.read(needsApiProvider);
      final res = await api.boostNeed(selected.id, _selectedTier);
      if (mounted) {
        setState(() {
          _boostedNeedId = selected.id;
          _boostExpiresAt = DateTime.tryParse(
            (res['boost'] as Map?)?['expiresAt']?.toString() ?? '',
          );
          _balance = (res['newBalance'] as int?) ?? (_balance - _tierCost);
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '🚀 "${selected.title}" is now boosted for $_selectedTier!',
          ),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _boosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    const profileBoostCost = 120;
    final canProfileBoost = _balance >= profileBoostCost && !_profileBoosted;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 60),
      children: [
        // ── Points balance ────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: NeedHubTokens.ochre.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: NeedHubTokens.ochre.withValues(alpha: 0.25),
                width: 1.5),
          ),
          child: Column(
            children: [
              const Icon(Icons.stars_rounded,
                  color: NeedHubTokens.ochre, size: 36),
              const SizedBox(height: 10),
              Text(
                '$_balance',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  color: NeedHubTokens.ochre,
                ),
              ),
              Text(
                'Impact Points',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 15, color: t.muted),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        // ── Boost a Need ──────────────────────────────────────────────────
        _SectionLabel(label: 'BOOST A NEED', t: t),
        const SizedBox(height: 4),
        Text(
          'Spend points to pin your need at the top of the feed so more helpers see it.',
          style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted, height: 1.4),
        ),
        const SizedBox(height: 16),

        // Tier selector
        Row(
          children: _tiers.map((tier) {
            final isSelected = _selectedTier == tier.id;
            final affordable = _balance >= tier.cost;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: tier.id != '72h' ? 8 : 0,
                ),
                child: GestureDetector(
                  onTap: affordable
                      ? () => setState(() => _selectedTier = tier.id)
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? NeedHubTokens.clay.withValues(alpha: 0.12)
                          : t.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? NeedHubTokens.clay
                            : (affordable ? t.rail : t.rail),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(tier.icon,
                            size: 22,
                            color: isSelected
                                ? NeedHubTokens.clay
                                : (affordable ? t.muted : t.muted3)),
                        const SizedBox(height: 6),
                        Text(tier.label,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? NeedHubTokens.clay
                                  : (affordable ? t.ink : t.muted3),
                            )),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.stars_rounded,
                                size: 11,
                                color: affordable
                                    ? NeedHubTokens.ochre
                                    : t.muted3),
                            const SizedBox(width: 2),
                            Text('${tier.cost} pts',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: affordable
                                      ? NeedHubTokens.ochre
                                      : t.muted3,
                                )),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        // Active boost status
        if (_boostedNeedId != null && _boostExpiresAt != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NeedHubTokens.forest.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: NeedHubTokens.forest.withValues(alpha: 0.20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.rocket_launch_rounded,
                    color: NeedHubTokens.forest, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Boost active! Expires ${_timeLeft(_boostExpiresAt!)}',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        color: NeedHubTokens.forest,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Boost button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _canBoost ? _showBoostNeedSheet : null,
            icon: _boosting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.rocket_launch_rounded, size: 18),
            label: Text(
              _boosting
                  ? 'Boosting…'
                  : 'Boost a Need — $_tierCost pts',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: NeedHubTokens.clay,
              foregroundColor: Colors.white,
              disabledBackgroundColor: t.rail,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              textStyle: GoogleFonts.hankenGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ),

        const SizedBox(height: 28),

        // ── Profile boost (existing) ──────────────────────────────────────
        _SectionLabel(label: 'PROFILE BOOST', t: t),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.rail, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: NeedHubTokens.clay.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.person_pin_rounded,
                    color: NeedHubTokens.clay, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '24-Hour Profile Boost',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Your profile appears at top of search for 24h',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 12, color: t.muted, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.stars_rounded,
                            size: 14, color: NeedHubTokens.ochre),
                        const SizedBox(width: 4),
                        Text(
                          '$profileBoostCost pts',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: NeedHubTokens.ochre,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _profileBoosted
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: NeedHubTokens.forest.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Active',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: NeedHubTokens.forest,
                        ),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: canProfileBoost
                          ? () => setState(() {
                                _profileBoosted = true;
                                _balance -= profileBoostCost;
                              })
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NeedHubTokens.clay,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: t.rail,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        textStyle: GoogleFonts.hankenGrotesk(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Redeem'),
                    ),
            ],
          ),
        ),

        if (_profileBoosted) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: NeedHubTokens.forest.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: NeedHubTokens.forest, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Boost active! Your profile is featured until tomorrow.',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        color: NeedHubTokens.forest,
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _timeLeft(DateTime expiresAt) {
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return 'expired';
    if (diff.inHours >= 24) return 'in ${diff.inDays}d';
    if (diff.inHours >= 1) return 'in ${diff.inHours}h';
    return 'in ${diff.inMinutes}m';
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final NeedHubTokens t;
  const _SectionLabel({required this.label, required this.t});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.hankenGrotesk(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: t.muted2,
        letterSpacing: 0.7,
      ),
    );
  }
}

// ── Need picker bottom sheet ───────────────────────────────────────────────────

class _NeedPickerSheet extends StatelessWidget {
  final List<Need> needs;
  final NeedHubTokens t;
  const _NeedPickerSheet({required this.needs, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: t.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: t.rail,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text('Select a Need to Boost',
              style: GoogleFonts.bricolageGrotesque(
                  fontSize: 17, fontWeight: FontWeight.w700, color: t.ink)),
          const SizedBox(height: 4),
          Text('Pick one of your open needs',
              style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted)),
          const SizedBox(height: 16),
          ...needs.map((n) => ListTile(
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 4),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: NeedHubTokens.clay.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.article_outlined,
                      color: NeedHubTokens.clay, size: 20),
                ),
                title: Text(n.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.ink)),
                subtitle: Text(n.category.toUpperCase(),
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 11, color: t.muted)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, n),
              )),
        ],
      ),
    );
  }
}

// ── Boost confirm dialog ──────────────────────────────────────────────────────

class _BoostConfirmDialog extends StatelessWidget {
  final Need need;
  final String tier;
  final int cost;
  final int balance;
  final NeedHubTokens t;

  const _BoostConfirmDialog({
    required this.need,
    required this.tier,
    required this.cost,
    required this.balance,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: t.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: [
          const Icon(Icons.rocket_launch_rounded,
              color: NeedHubTokens.clay, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Confirm Boost',
                style: GoogleFonts.bricolageGrotesque(
                    fontSize: 17, fontWeight: FontWeight.w800, color: t.ink)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            '"${need.title}"',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.hankenGrotesk(
                fontSize: 14, fontWeight: FontWeight.w700, color: t.ink),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NeedHubTokens.ochre.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: NeedHubTokens.ochre.withValues(alpha: 0.20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Boost duration',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 12, color: t.muted)),
                    Text(tier,
                        style: GoogleFonts.bricolageGrotesque(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: t.ink)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Cost',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 12, color: t.muted)),
                    Row(
                      children: [
                        const Icon(Icons.stars_rounded,
                            size: 14, color: NeedHubTokens.ochre),
                        const SizedBox(width: 3),
                        Text('$cost pts',
                            style: GoogleFonts.bricolageGrotesque(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: NeedHubTokens.ochre)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Remaining after: ${balance - cost} pts',
            style: GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted),
          ),
          const SizedBox(height: 4),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w600, color: t.muted)),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.rocket_launch_rounded, size: 16),
          label: Text('Boost Now',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w700)),
          style: FilledButton.styleFrom(
            backgroundColor: NeedHubTokens.clay,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
        ),
      ],
    );
  }
}
