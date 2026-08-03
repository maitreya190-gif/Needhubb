import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_strings.dart';
import '../../services/plus_api.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';

/// Honest metrics only — every number here is labeled for exactly what it
/// measures (see lib/plus-analytics.ts on the server). No feed impressions,
/// no confirmed-send share counts, no fake trend line before there's 14
/// days of real data — those are all things this screen deliberately does
/// not claim to show.
class PlusAnalyticsScreen extends ConsumerStatefulWidget {
  const PlusAnalyticsScreen({super.key});

  @override
  ConsumerState<PlusAnalyticsScreen> createState() => _PlusAnalyticsScreenState();
}

class _PlusAnalyticsScreenState extends ConsumerState<PlusAnalyticsScreen> {
  String _window = '7d';
  PlusAnalytics? _analytics;
  PlusInsights? _insights;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _setWindow(String window) {
    if (_window == window) return;
    setState(() => _window = window);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(plusApiProvider);
      final results = await Future.wait([api.analytics(window: _window), api.insights()]);
      if (!mounted) return;
      setState(() {
        _analytics = results[0] as PlusAnalytics;
        _insights = results[1] as PlusInsights;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = S.current.plusAnalyticsLoadFailed;
        _loading = false;
      });
    }
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
        title: Text(S.current.plusAnalyticsTitle,
            style: GoogleFonts.bricolageGrotesque(fontSize: 18, fontWeight: FontWeight.w700, color: t.ink)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: GoogleFonts.hankenGrotesk(color: t.muted)))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: NeedHubTokens.ochre,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    children: [
                      // Window toggle
                      Container(
                        height: 40,
                        decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.all(3),
                        child: Row(
                          children: [
                            Expanded(child: _WindowChip(label: S.current.plusWindow7Days, selected: _window == '7d', onTap: () => _setWindow('7d'), t: t)),
                            Expanded(child: _WindowChip(label: S.current.plusWindow30Days, selected: _window == '30d', onTap: () => _setWindow('30d'), t: t)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Metric grid
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.5,
                        children: [
                          _MetricTile(label: S.current.plusProfileViews, value: '${_analytics?.profileViews ?? 0}', icon: Icons.visibility_rounded, t: t),
                          _MetricTile(label: S.current.plusNeedViews, value: '${_analytics?.needViews ?? 0}', icon: Icons.remove_red_eye_rounded, t: t),
                          _MetricTile(label: S.current.plusReach, value: '${_analytics?.reach ?? 0}', icon: Icons.groups_rounded, t: t, sublabel: S.current.plusReachSub),
                          _MetricTile(label: S.current.plusShares, value: '${_analytics?.shares ?? 0}', icon: Icons.share_rounded, t: t, sublabel: S.current.plusSharesSub),
                          _MetricTile(label: S.current.plusOffersReceived, value: '${_analytics?.offersReceived ?? 0}', icon: Icons.handshake_rounded, t: t),
                          _MetricTile(
                            label: S.current.plusResponseRate,
                            value: _analytics?.responseRate != null ? '${(_analytics!.responseRate! * 100).toStringAsFixed(0)}%' : '—',
                            icon: Icons.forum_rounded,
                            t: t,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Trend
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: t.rail)),
                        child: Row(
                          children: [
                            Icon(Icons.show_chart_rounded, color: t.muted2, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                (_analytics?.insufficientTrendData ?? true)
                                    ? S.current.plusTrendInsufficient
                                    : (_analytics!.trendDirection! >= 0
                                        ? S.current.plusTrendUp((_analytics!.trendDirection! * 100).toStringAsFixed(0))
                                        : S.current.plusTrendDown((_analytics!.trendDirection!.abs() * 100).toStringAsFixed(0))),
                                style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.ink, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // AI insights
                      Text(S.current.plusAiInsightsHeader,
                          style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: t.muted2, letterSpacing: 0.7)),
                      const SizedBox(height: 10),
                      if (_insights != null)
                        ...List.generate(_insights!.insights.length, (i) {
                          final tip = _insights!.insights[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: NeedHubTokens.ochre.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: NeedHubTokens.ochre.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.auto_awesome_rounded, size: 16, color: NeedHubTokens.ochre),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(tip, style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.ink, height: 1.4)),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

class _WindowChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final NeedHubTokens t;

  const _WindowChip({required this.label, required this.selected, required this.onTap, required this.t});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? t.card : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected ? NeedHubThemes.cardShadow : null,
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? t.ink : t.muted2)),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final NeedHubTokens t;
  final String? sublabel;

  const _MetricTile({required this.label, required this.value, required this.icon, required this.t, this.sublabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: t.rail)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: t.muted2),
          const Spacer(),
          Text(value, style: GoogleFonts.bricolageGrotesque(fontSize: 22, fontWeight: FontWeight.w800, color: t.ink)),
          Text(sublabel ?? label, style: GoogleFonts.hankenGrotesk(fontSize: 11, color: t.muted)),
        ],
      ),
    );
  }
}
