import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/user_state.dart';
import '../../services/profiles_api.dart';
import '../../services/redemptions_api.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';

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

  @override
  void initState() {
    super.initState();
    _currentBalance = myProfileNotifier.value?.pointsTotal ?? pointsNotifier.value;
    myProfileNotifier.addListener(_syncBalance);
    _load();
  }

  @override
  void dispose() {
    myProfileNotifier.removeListener(_syncBalance);
    super.dispose();
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
        _error = 'Could not load catalog';
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
          ? 'Not enough points yet'
          : 'Redemption failed';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
        title: Text('Redeem points',
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
                Text('YOUR BALANCE',
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
                      child: Text('reliability\npoints',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 14, color: t.onDarkMuted, height: 1.3)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          Text('AVAILABLE REWARDS',
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
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          else if (_catalog.isEmpty)
            Text('No rewards available right now',
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
                    'Points are earned by completing needs, receiving 4★+ reviews, and getting certificates approved.',
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
                      ? 'Sold out'
                      : (canRedeem ? 'Redeem' : 'Locked')),
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
          Text('Redeemed!',
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
                Text('YOUR CODE',
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
          Text('Balance: $remaining pts',
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
              child: Text('Done',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
