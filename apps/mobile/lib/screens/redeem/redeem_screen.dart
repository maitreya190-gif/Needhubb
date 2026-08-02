import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/need.dart';
import '../../models/user_state.dart';
import '../../services/needs_api.dart' show feedNeedsNotifier;
import '../../services/profiles_api.dart';
import '../../services/redemptions_api.dart';
import '../../services/social_providers.dart';
import '../../l10n/app_strings.dart';
import '../../theme/tokens.dart';

/// Need-boost tiers — mirrors BOOST_TIERS in needs.router.ts exactly.
const _kNeedBoostTiers = [
  (id: '6h', label: '6 Hours', cost: 50, icon: Icons.flash_on_rounded),
  (id: '24h', label: '24 Hours', cost: 100, icon: Icons.rocket_launch_outlined),
  (id: '72h', label: '3 Days', cost: 200, icon: Icons.star_rounded),
];

/// ChitChat-boost tiers — mirrors CHITCHAT_BOOST_TIERS in
/// lib/visibility-boost.ts exactly. Capped at 12h, matching how long
/// ChitChat availability itself can ever last.
const _kChitBoostTiers = [
  (id: '3h', label: '3 Hours', cost: 40, icon: Icons.flash_on_rounded),
  (id: '6h', label: '6 Hours', cost: 70, icon: Icons.rocket_launch_outlined),
  (id: '12h', label: '12 Hours', cost: 120, icon: Icons.star_rounded),
];

class RedeemScreen extends ConsumerStatefulWidget {
  final int balance;

  const RedeemScreen({super.key, this.balance = 340});

  @override
  ConsumerState<RedeemScreen> createState() => _RedeemScreenState();
}

class _RedeemScreenState extends ConsumerState<RedeemScreen> {
  List<RedemptionItem> _catalog = const [];
  bool _loading = true;
  String? _error;
  int _currentBalance = 0;
  String? _redeemingId;

  // Need visibility boost
  String _needBoostTier = '24h';
  bool _boostingNeed = false;

  // ChitChat visibility boost
  String _chitBoostTier = '6h';
  bool _boostingChit = false;
  bool _chitBoosted = false;
  DateTime? _chitBoostExpiresAt;

  @override
  void initState() {
    super.initState();
    _currentBalance = myProfileNotifier.value?.pointsTotal ?? pointsNotifier.value;
    myProfileNotifier.addListener(_syncBalance);
    _load();
    _loadChitBoostStatus();
  }

  @override
  void dispose() {
    myProfileNotifier.removeListener(_syncBalance);
    super.dispose();
  }

  Future<void> _loadChitBoostStatus() async {
    try {
      final res = await ref.read(chitchatApiProvider).getBoostStatus();
      if (!mounted) return;
      final boosted = res['boosted'] as bool? ?? false;
      final expiresAtStr = res['expiresAt'] as String?;
      setState(() {
        _chitBoosted = boosted;
        _chitBoostExpiresAt = expiresAtStr != null ? DateTime.tryParse(expiresAtStr) : null;
      });
    } catch (_) {
      // Status just won't show as boosted; the boost button itself still works.
    }
  }

  void _syncBalance() {
    if (!mounted) return;
    final me = myProfileNotifier.value;
    if (me != null) {
      setState(() => _currentBalance = me.pointsTotal);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(redemptionsApiProvider);
      final items = await api.catalog();
      if (!mounted) return;
      setState(() {
        _catalog = items;
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

  Future<void> _redeem(RedemptionItem item) async {
    if (_redeemingId != null) return;
    setState(() => _redeemingId = item.id);
    try {
      final result = await ref.read(redemptionsApiProvider).redeem(item.id);
      if (!mounted) return;
      // Sync local balances.
      pointsNotifier.value = result.newBalance;
      final me = myProfileNotifier.value;
      if (me != null) {
        myProfileNotifier.value = ProfileMe(
          id: me.id, displayName: me.displayName, email: me.email,
          bio: me.bio, gender: me.gender, locationText: me.locationText,
          lat: me.lat, lng: me.lng, avatarUrl: me.avatarUrl,
          promptSkill: me.promptSkill, promptCollab: me.promptCollab,
          promptNeed: me.promptNeed, pointsTotal: result.newBalance,
          interestLabels: me.interestLabels, skillLabels: me.skillLabels,
          faceVerifiedAt: me.faceVerifiedAt,
          personalityTraits: me.personalityTraits,
          personalityNickname: me.personalityNickname,
          personalitySummary: me.personalitySummary,
          personalityVibeTags: me.personalityVibeTags,
        );
      }
      setState(() {
        _currentBalance = result.newBalance;
        _redeemingId = null;
      });
      showModalBottomSheet(
        context: context,
        isDismissible: false,
        backgroundColor: Colors.transparent,
        builder: (_) => _RedeemSuccessSheet(
          code: result.code,
          itemTitle: item.title,
          remaining: result.newBalance,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _redeemingId = null);
      final msg = e.toString().contains('402') || e.toString().contains('INSUFFICIENT')
          ? S.current.error
          : S.current.error;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  int get _needBoostCost =>
      _kNeedBoostTiers.firstWhere((t) => t.id == _needBoostTier).cost;

  int get _chitBoostCost =>
      _kChitBoostTiers.firstWhere((t) => t.id == _chitBoostTier).cost;

  Future<void> _showBoostNeedSheet() async {
    final t = context.tokens;
    final myNeeds = feedNeedsNotifier.value
        .where((n) => n.authorInitials == 'ME' || n.authorName == 'You')
        .where((n) => !n.isFrozen)
        .toList();

    if (myNeeds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You don't have any open needs to boost.")),
        );
      }
      return;
    }

    final selected = await showModalBottomSheet<Need>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _NeedPickerSheet(needs: myNeeds, t: t),
    );
    if (selected == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _BoostConfirmDialog(
        title: 'Boost "${selected.title}"',
        subtitle: 'Pins this need at the top of the feed so more helpers see it.',
        tier: _needBoostTier,
        cost: _needBoostCost,
        balance: _currentBalance,
        t: t,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _boostingNeed = true);
    try {
      final res = await ref.read(needsApiProvider).boostNeed(selected.id, _needBoostTier);
      final newBalance = (res['newBalance'] as num?)?.toInt() ?? (_currentBalance - _needBoostCost);
      if (!mounted) return;
      pointsNotifier.value = newBalance;
      setState(() => _currentBalance = newBalance);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('🚀 "${selected.title}" is boosted for $_needBoostTier!'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _boostingNeed = false);
    }
  }

  Future<void> _showBoostChitSheet() async {
    final t = context.tokens;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _BoostConfirmDialog(
        title: 'Boost your ChitChat visibility',
        subtitle: 'You appear first for nearby people looking to ChitChat.',
        tier: _chitBoostTier,
        cost: _chitBoostCost,
        balance: _currentBalance,
        t: t,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _boostingChit = true);
    try {
      final res = await ref.read(chitchatApiProvider).boost(_chitBoostTier);
      final newBalance = (res['newBalance'] as num?)?.toInt() ?? (_currentBalance - _chitBoostCost);
      final expiresAtStr = (res['boost'] as Map?)?['expiresAt']?.toString();
      if (!mounted) return;
      pointsNotifier.value = newBalance;
      setState(() {
        _currentBalance = newBalance;
        _chitBoosted = true;
        _chitBoostExpiresAt = expiresAtStr != null ? DateTime.tryParse(expiresAtStr) : null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('🚀 Your ChitChat visibility is boosted for $_chitBoostTier!'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _boostingChit = false);
    }
  }

  String _timeLeft(DateTime expiresAt) {
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return 'expired';
    if (diff.inHours >= 1) return 'in ${diff.inHours}h';
    return 'in ${diff.inMinutes}m';
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
        title: Text(S.current.redeemPoints,
            style: GoogleFonts.bricolageGrotesque(
                fontSize: 18, fontWeight: FontWeight.w700, color: t.ink)),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, MediaQuery.of(context).padding.bottom + 24),
        children: [
          // Balance card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: t.surfaceDark,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.current.yourBalance,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: t.onDarkMuted,
                    )),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$_currentBalance',
                        style: GoogleFonts.bricolageGrotesque(
                          fontSize: 56,
                          fontWeight: FontWeight.w800,
                          color: NeedHubTokens.clay,
                          height: 1,
                        )),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(S.current.reliabilityPoints.toLowerCase(),
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 14, color: t.onDarkMuted, height: 1.3)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Boost a Need ──────────────────────────────────────────────
          _BoostSection(
            title: 'Boost a Need',
            description: 'Spend points to pin your need at the top of the feed so more helpers see it.',
            tiers: _kNeedBoostTiers,
            selectedTier: _needBoostTier,
            balance: _currentBalance,
            boosting: _boostingNeed,
            onSelectTier: (id) => setState(() => _needBoostTier = id),
            onBoost: _showBoostNeedSheet,
            activeBanner: null,
            t: t,
          ),
          const SizedBox(height: 24),

          // ── Boost ChitChat visibility ─────────────────────────────────
          _BoostSection(
            title: 'Boost ChitChat Visibility',
            description: 'Spend points to appear first for nearby people looking to ChitChat.',
            tiers: _kChitBoostTiers,
            selectedTier: _chitBoostTier,
            balance: _currentBalance,
            boosting: _boostingChit,
            onSelectTier: (id) => setState(() => _chitBoostTier = id),
            onBoost: _showBoostChitSheet,
            activeBanner: _chitBoosted && _chitBoostExpiresAt != null
                ? 'ChitChat boost active! Expires ${_timeLeft(_chitBoostExpiresAt!)}'
                : null,
            t: t,
          ),
          const SizedBox(height: 28),

          Text(S.current.availableRewards,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.muted2,
                letterSpacing: 0.7,
              )),
          const SizedBox(height: 12),

          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(30),
              child: CircularProgressIndicator(),
            ))
          else if (_error != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: NeedHubTokens.clay.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: NeedHubTokens.clay),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 13, color: t.ink))),
                  TextButton(onPressed: _load, child: Text(S.current.retry)),
                ],
              ),
            )
          else if (_catalog.isEmpty)
            Text(S.current.noRewardsAvailable,
                style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted))
          else
            ..._catalog.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RewardCard(
                item: item,
                canRedeem: _currentBalance >= item.pointsCost && item.stock != 0,
                redeeming: _redeemingId == item.id,
                onRedeem: () => _redeem(item),
                t: t,
              ),
            )),

          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.chip,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: t.muted2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    S.current.pointsEarnedInfo,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 12.5, color: t.muted2, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  final RedemptionItem item;
  final bool canRedeem;
  final bool redeeming;
  final VoidCallback onRedeem;
  final NeedHubTokens t;

  const _RewardCard({
    required this.item,
    required this.canRedeem,
    required this.redeeming,
    required this.onRedeem,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.rail, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: NeedHubTokens.clay,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.card_giftcard_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.ink)),
                const SizedBox(height: 3),
                Text(item.description,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 12, color: t.muted, height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Text('${item.pointsCost} pts',
                    style: GoogleFonts.bricolageGrotesque(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: NeedHubTokens.clay)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: ElevatedButton(
              onPressed: canRedeem && !redeeming ? onRedeem : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: NeedHubTokens.clay,
                foregroundColor: Colors.white,
                disabledBackgroundColor: t.rail,
                disabledForegroundColor: t.muted,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
                textStyle: GoogleFonts.hankenGrotesk(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
              child: redeeming
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(item.stock == 0
                      ? S.current.soldOut
                      : (canRedeem ? S.current.redeemPoints : S.current.locked)),
            ),
          ),
        ],
      ),
    );
  }
}

class _RedeemSuccessSheet extends StatelessWidget {
  final String code;
  final String itemTitle;
  final int remaining;

  const _RedeemSuccessSheet({
    required this.code,
    required this.itemTitle,
    required this.remaining,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 28, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: NeedHubTokens.forest.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: NeedHubTokens.forest, size: 42),
          ),
          const SizedBox(height: 18),
          Text(S.current.redeemed,
              style: GoogleFonts.bricolageGrotesque(
                  fontSize: 24, fontWeight: FontWeight.w800, color: t.ink)),
          const SizedBox(height: 6),
          Text(itemTitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 14, color: t.muted, height: 1.4)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: t.chip,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: NeedHubTokens.clay, width: 1.5),
            ),
            child: Column(
              children: [
                Text(S.current.yourCode,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: t.muted2,
                        letterSpacing: 1)),
                const SizedBox(height: 6),
                SelectableText(code,
                    style: GoogleFonts.bricolageGrotesque(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: NeedHubTokens.clay,
                        letterSpacing: 3)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text('${S.current.balanceAfter}: $remaining ${S.current.points}',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 13, color: t.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: NeedHubTokens.clay,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(S.current.done,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card showing a set of boost tiers to spend, a Boost button, and an
/// optional "already active" banner. Reused for both Need-boost and
/// ChitChat-boost — only the tier table, copy, and callback differ.
class _BoostSection extends StatelessWidget {
  final String title;
  final String description;
  final List<({String id, String label, int cost, IconData icon})> tiers;
  final String selectedTier;
  final int balance;
  final bool boosting;
  final ValueChanged<String> onSelectTier;
  final Future<void> Function() onBoost;
  final String? activeBanner;
  final NeedHubTokens t;

  const _BoostSection({
    required this.title,
    required this.description,
    required this.tiers,
    required this.selectedTier,
    required this.balance,
    required this.boosting,
    required this.onSelectTier,
    required this.onBoost,
    required this.activeBanner,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final selected = tiers.firstWhere((tier) => tier.id == selectedTier);
    final canAfford = balance >= selected.cost;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.rail),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rocket_launch_rounded, color: NeedHubTokens.clay, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: GoogleFonts.bricolageGrotesque(
                        fontSize: 15, fontWeight: FontWeight.w800, color: t.ink)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(description,
              style: GoogleFonts.hankenGrotesk(fontSize: 12.5, color: t.muted, height: 1.4)),
          if (activeBanner != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: NeedHubTokens.forest.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, size: 15, color: NeedHubTokens.forest),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(activeBanner!,
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 12, fontWeight: FontWeight.w700, color: NeedHubTokens.forest)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: tiers.map((tier) {
              final isSelected = tier.id == selectedTier;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onSelectTier(tier.id),
                  child: Container(
                    margin: EdgeInsets.only(right: tier == tiers.last ? 0 : 8),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? NeedHubTokens.clay.withValues(alpha: 0.12) : t.paper,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? NeedHubTokens.clay : t.rail,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(tier.icon,
                            size: 18, color: isSelected ? NeedHubTokens.clay : t.muted2),
                        const SizedBox(height: 4),
                        Text(tier.label,
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? NeedHubTokens.clay : t.ink)),
                        const SizedBox(height: 2),
                        Text('${tier.cost} pts',
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? NeedHubTokens.clay : t.muted3)),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (boosting || !canAfford) ? null : () => onBoost(),
              style: ElevatedButton.styleFrom(
                backgroundColor: NeedHubTokens.clay,
                foregroundColor: Colors.white,
                disabledBackgroundColor: t.rail,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: boosting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      canAfford ? 'Boost — ${selected.cost} pts' : 'Not enough points',
                      style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet letting the user pick one of their own open needs to boost.
class _NeedPickerSheet extends StatelessWidget {
  final List<Need> needs;
  final NeedHubTokens t;

  const _NeedPickerSheet({required this.needs, required this.t});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: t.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: t.rail, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Text('Select a need to boost',
                style: GoogleFonts.bricolageGrotesque(
                    fontSize: 16, fontWeight: FontWeight.w800, color: t.ink)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: needs.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text('You have no open needs to boost right now.',
                          style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted)),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: needs.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: t.rail),
                      itemBuilder: (context, i) {
                        final need = needs[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(need.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.hankenGrotesk(
                                  fontSize: 14, fontWeight: FontWeight.w700, color: t.ink)),
                          subtitle: Text(need.status,
                              style: GoogleFonts.hankenGrotesk(fontSize: 11.5, color: t.muted)),
                          trailing: Icon(Icons.chevron_right_rounded, color: t.muted3),
                          onTap: () => Navigator.of(context).pop(need),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmation dialog shown before spending points on either boost type.
class _BoostConfirmDialog extends StatelessWidget {
  final String title;
  final String subtitle;
  final String tier;
  final int cost;
  final int balance;
  final NeedHubTokens t;

  const _BoostConfirmDialog({
    required this.title,
    required this.subtitle,
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
      title: Text(title,
          style: GoogleFonts.bricolageGrotesque(
              fontSize: 17, fontWeight: FontWeight.w800, color: t.ink)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle,
              style: GoogleFonts.hankenGrotesk(fontSize: 13.5, color: t.muted, height: 1.4)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Duration',
                  style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted2)),
              Text(tier,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 13, fontWeight: FontWeight.w700, color: t.ink)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Cost',
                  style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted2)),
              Text('$cost pts',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 13, fontWeight: FontWeight.w700, color: NeedHubTokens.clay)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Balance after',
                  style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted2)),
              Text('${balance - cost} pts',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 13, fontWeight: FontWeight.w700, color: t.ink)),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(S.current.cancel,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w700, color: t.muted)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: NeedHubTokens.clay,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text('Boost now',
              style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
