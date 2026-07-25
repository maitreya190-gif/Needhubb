import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
                  '120 pts redeemable for a 24h boost',
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

class _RedeemTab extends StatefulWidget {
  final NeedHubTokens t;

  const _RedeemTab({required this.t});

  @override
  State<_RedeemTab> createState() => _RedeemTabState();
}

class _RedeemTabState extends State<_RedeemTab> {
  bool _redeemed = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    const balance = 240;
    const cost = 120;
    final canRedeem = balance >= cost && !_redeemed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Balance
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
                  '$balance',
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
          const SizedBox(height: 24),
          Text(
            'AVAILABLE REWARDS',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: t.muted2,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 12),

          // Reward card
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
                  child: const Icon(Icons.rocket_launch_outlined,
                      color: NeedHubTokens.clay, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '24-Hour Boost',
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
                            '$cost pts',
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
                _redeemed
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
                        onPressed: canRedeem
                            ? () => setState(() => _redeemed = true)
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

          if (_redeemed) ...[
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
      ),
    );
  }
}
