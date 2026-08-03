import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_strings.dart';
import '../../services/plus_api.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/nh_plus_badge.dart';
import 'plus_payment_screen.dart';
import 'plus_analytics_screen.dart';
import 'plus_reward_claim_screen.dart';

class PlusScreen extends ConsumerStatefulWidget {
  const PlusScreen({super.key});

  @override
  ConsumerState<PlusScreen> createState() => _PlusScreenState();
}

class _PlusScreenState extends ConsumerState<PlusScreen> {
  PlusStatus? _status;
  PlusRewardsCatalog? _rewards;
  List<PlusRewardClaim> _history = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(plusApiProvider);
      final results = await Future.wait([api.status(), api.rewards(), api.myRewards()]);
      if (!mounted) return;
      setState(() {
        _status = results[0] as PlusStatus;
        _rewards = results[1] as PlusRewardsCatalog;
        _history = results[2] as List<PlusRewardClaim>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = S.current.error;
        _loading = false;
      });
    }
  }

  Future<void> _openSubscribe() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PlusPaymentScreen()),
    );
    if (result == true) _load();
  }

  Future<void> _confirmCancel() async {
    final t = context.tokens;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(S.current.cancelNeedHubPlus,
            style: GoogleFonts.bricolageGrotesque(fontSize: 17, fontWeight: FontWeight.w800, color: t.ink)),
        content: Text(
          "You'll keep every Plus benefit until ${_status?.currentPeriodEnd != null ? _formatDate(_status!.currentPeriodEnd!) : 'your period ends'} — it just won't renew after that.",
          style: GoogleFonts.hankenGrotesk(fontSize: 13.5, color: t.muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.current.keepPlus, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700, color: t.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.current.cancelRenewal,
                style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700, color: NeedHubTokens.clay)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(plusApiProvider).cancel();
        if (mounted) _load();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.current.error)));
        }
      }
    }
  }

  static String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final active = _status?.active ?? false;

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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('NeedHub Plus',
                style: GoogleFonts.bricolageGrotesque(fontSize: 18, fontWeight: FontWeight.w700, color: t.ink)),
            if (active) ...[const SizedBox(width: 8), const NhPlusBadge()],
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: NeedHubTokens.ochre,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: NeedHubTokens.clay.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: NeedHubTokens.clay),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_error!, style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.ink))),
                          TextButton(onPressed: _load, child: Text(S.current.retry)),
                        ],
                      ),
                    ),

                  // ── Status card ──────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment(-0.9, -0.5),
                        end: Alignment(0.9, 0.5),
                        colors: [Color(0xFFE0971C), Color(0xFFC46A1E)],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE0971C).withValues(alpha: 0.4),
                          offset: const Offset(0, 10),
                          blurRadius: 24,
                          spreadRadius: -10,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.white, size: 22),
                            const SizedBox(width: 8),
                            Text(active ? S.current.youreAPlusMember : S.current.goNeedHubPlus,
                                style: GoogleFonts.bricolageGrotesque(
                                    fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          active
                              ? (_status?.cancelAtPeriodEnd ?? false)
                                  ? S.current.activeUntilDate(_status?.currentPeriodEnd != null ? _formatDate(_status!.currentPeriodEnd!) : '—')
                                  : S.current.renewsOnDate(_status?.currentPeriodEnd != null ? _formatDate(_status!.currentPeriodEnd!) : '—')
                              : S.current.plusSubtitleInactive(((_status?.priceMonthlyPaise ?? 5000) / 100).toStringAsFixed(0)),
                          style: GoogleFonts.hankenGrotesk(fontSize: 13, color: Colors.white.withValues(alpha: 0.92), height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: active ? _confirmCancel : _openSubscribe,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFFC46A1E),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(
                              active ? (_status?.cancelAtPeriodEnd == true ? S.current.renewalCancelled : S.current.manageSubscription) : S.current.subscribePer(((_status?.priceMonthlyPaise ?? 5000) / 100).toStringAsFixed(0)),
                              style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Benefits ─────────────────────────────────────────────
                  Text(S.current.plusBenefitsHeader,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 11, fontWeight: FontWeight.w700, color: t.muted2, letterSpacing: 0.7)),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: t.rail, width: 1),
                    ),
                    child: Column(
                      children: [
                        _BenefitRow(icon: Icons.trending_up_rounded, label: S.current.plusBenefit1, t: t),
                        Divider(color: t.rail, height: 1, indent: 50),
                        _BenefitRow(icon: Icons.forum_rounded, label: S.current.plusBenefit2, t: t),
                        Divider(color: t.rail, height: 1, indent: 50),
                        _BenefitRow(icon: Icons.workspace_premium_rounded, label: S.current.plusBenefit3, t: t),
                        Divider(color: t.rail, height: 1, indent: 50),
                        _BenefitRow(
                          icon: Icons.bar_chart_rounded,
                          label: S.current.plusBenefit4,
                          t: t,
                          onTap: active ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlusAnalyticsScreen())) : null,
                        ),
                        Divider(color: t.rail, height: 1, indent: 50),
                        _BenefitRow(icon: Icons.rocket_launch_rounded, label: S.current.plusBenefit5, t: t),
                        Divider(color: t.rail, height: 1, indent: 50),
                        _BenefitRow(icon: Icons.support_agent_rounded, label: S.current.plusBenefit6, t: t),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Launch reward ────────────────────────────────────────
                  if (_rewards != null && _rewards!.offers.isNotEmpty) ...[
                    Text(S.current.plusRewardsHeader,
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 11, fontWeight: FontWeight.w700, color: t.muted2, letterSpacing: 0.7)),
                    const SizedBox(height: 10),
                    ..._rewards!.offers.map((offer) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RewardOfferCard(
                            offer: offer,
                            t: t,
                            onTap: () async {
                              final claimed = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(builder: (_) => PlusRewardClaimScreen(offer: offer)),
                              );
                              if (claimed == true) _load();
                            },
                          ),
                        )),
                    const SizedBox(height: 14),
                  ],

                  // ── History ──────────────────────────────────────────────
                  if (_history.isNotEmpty) ...[
                    Text(S.current.plusRedemptionHeader,
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 11, fontWeight: FontWeight.w700, color: t.muted2, letterSpacing: 0.7)),
                    const SizedBox(height: 10),
                    ..._history.map((c) => _HistoryTile(claim: c, t: t)),
                  ],
                ],
              ),
            ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final NeedHubTokens t;
  final VoidCallback? onTap;

  const _BenefitRow({required this.icon, required this.label, required this.t, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: NeedHubTokens.ochre.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: NeedHubTokens.ochre),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w600, color: t.ink)),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, size: 18, color: t.muted3),
          ],
        ),
      ),
    );
  }
}

class _RewardOfferCard extends StatelessWidget {
  final PlusRewardOffer offer;
  final NeedHubTokens t;
  final VoidCallback onTap;

  const _RewardOfferCard({required this.offer, required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = offer.alreadyClaimed || !offer.eligible;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: offer.eligible && !offer.alreadyClaimed ? NeedHubTokens.forest : t.rail, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: NeedHubTokens.forest.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.card_giftcard_rounded, color: NeedHubTokens.forest, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(offer.title,
                      style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w700, color: t.ink)),
                  const SizedBox(height: 2),
                  Text(
                    offer.alreadyClaimed
                        ? 'Already claimed'
                        : '₹${offer.rewardValueRupees.toStringAsFixed(0)} cashback — costs ${offer.pointsCost} points',
                    style: GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted),
                  ),
                ],
              ),
            ),
            if (!disabled) Icon(Icons.chevron_right_rounded, color: t.muted3),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final PlusRewardClaim claim;
  final NeedHubTokens t;

  const _HistoryTile({required this.claim, required this.t});

  Color _statusColor() {
    switch (claim.status) {
      case 'PAID':
        return NeedHubTokens.forest;
      case 'REJECTED':
        return NeedHubTokens.clay;
      default:
        return NeedHubTokens.ochre;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.rail, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(claim.offerTitle,
                    style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w700, color: t.ink)),
                Text('${claim.pointsSpent} pts spent', style: GoogleFonts.hankenGrotesk(fontSize: 11, color: t.muted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor().withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(claim.status,
                style: GoogleFonts.hankenGrotesk(fontSize: 10.5, fontWeight: FontWeight.w700, color: _statusColor())),
          ),
        ],
      ),
    );
  }
}
