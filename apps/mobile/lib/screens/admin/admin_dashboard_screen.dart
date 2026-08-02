import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/admin_api.dart';
import '../../theme/tokens.dart';
import 'admin_users_screen.dart';
import 'admin_needs_screen.dart';
import 'admin_certs_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_ads_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  AdminStats? _stats;
  String _error = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final s = await AdminApi.instance.stats();
      if (mounted) setState(() {
        _stats = s;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.paper,
      body: CustomScrollView(
        slivers: [
          // Dark header
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Container(
                color: t.surfaceDark,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Icon(Icons.arrow_back_rounded,
                              color: t.onDarkMuted, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.shield_outlined,
                            color: t.onDarkMuted, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'NeedHub Admin',
                            style: GoogleFonts.bricolageGrotesque(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: t.onDark,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _load,
                          icon: Icon(Icons.refresh_rounded,
                              color: t.onDarkMuted, size: 20),
                        ),
                        GestureDetector(
                          onTap: () {
                            AdminApi.instance.setSecret('');
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Sign out',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: t.onDarkMuted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Stats row — monochrome
                    if (_loading)
                      Center(
                        child: SizedBox(
                          height: 40,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white.withValues(alpha: 0.4)),
                        ),
                      )
                    else if (_error.isNotEmpty)
                      Text(
                        'Failed to load stats',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.5)),
                      )
                    else if (_stats != null)
                      Row(
                        children: [
                          _StatChip(label: 'Users', value: _stats!.users),
                          const SizedBox(width: 8),
                          _StatChip(label: 'Needs', value: _stats!.needs),
                          const SizedBox(width: 8),
                          _StatChip(
                              label: 'Certs',
                              value: _stats!.pendingCerts),
                          const SizedBox(width: 8),
                          _StatChip(
                              label: 'Reports',
                              value: _stats!.openReports),
                          const SizedBox(width: 8),
                          _StatChip(label: 'Ads', value: _stats!.pendingAdInquiries),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  'SECTIONS',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: t.muted2,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 12),
                _NavCard(
                  icon: Icons.people_outline_rounded,
                  title: 'Users',
                  desc: _stats != null
                      ? '${_stats!.users} total users'
                      : 'Search, view & remove users',
                  t: t,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AdminUsersScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.list_alt_rounded,
                  title: 'Needs / Posts',
                  desc: _stats != null
                      ? '${_stats!.needs} total needs'
                      : 'Review and moderate posted needs',
                  t: t,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AdminNeedsScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.verified_outlined,
                  title: 'Certificate Queue',
                  desc: _stats != null
                      ? '${_stats!.pendingCerts} awaiting review'
                      : 'Approve or reject certificates',
                  t: t,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AdminCertsScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.flag_outlined,
                  title: 'Reports',
                  desc: _stats != null
                      ? '${_stats!.openReports} open reports'
                      : 'Resolve flagged content',
                  t: t,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AdminReportsScreen())),
                ),
                const SizedBox(height: 10),
                _NavCard(
                  icon: Icons.campaign_outlined,
                  title: 'Ad Inquiries',
                  desc: _stats != null
                      ? '${_stats!.pendingAdInquiries} pending inquiries'
                      : 'Review advertising requests',
                  t: t,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AdminAdsScreen())),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// Monochrome stat chip — white text on translucent white bg
class _StatChip extends StatelessWidget {
  final String label;
  final int value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 10.5,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Monochrome nav card
class _NavCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final NeedHubTokens t;
  final VoidCallback onTap;

  const _NavCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: t.chip,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: t.ink, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style:
                        GoogleFonts.hankenGrotesk(fontSize: 12.5, color: t.muted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: t.muted, size: 20),
          ],
        ),
      ),
    );
  }
}
