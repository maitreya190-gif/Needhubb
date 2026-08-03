import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/admin_api.dart';
import '../../theme/tokens.dart';
import 'admin_shared.dart';

class AdminRewardClaimsScreen extends StatefulWidget {
  const AdminRewardClaimsScreen({super.key});

  @override
  State<AdminRewardClaimsScreen> createState() => _AdminRewardClaimsScreenState();
}

class _AdminRewardClaimsScreenState extends State<AdminRewardClaimsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<AdminRewardClaim> _claims = [];
  bool _loading = true;
  String _error = '';

  final List<String> _tabs = ['Pending', 'Approved', 'Paid', 'Rejected'];
  final List<String> _statusFilters = ['PENDING', 'APPROVED', 'PAID', 'REJECTED'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await AdminApi.instance.rewardClaims(status: _statusFilters[_tabController.index]);
      if (mounted) {
        setState(() {
          _claims = res;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _reject(AdminRewardClaim claim) async {
    try {
      await AdminApi.instance.updateRewardClaim(claim.id, status: 'REJECTED');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rejected')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _markPaid(AdminRewardClaim claim) async {
    final controller = TextEditingController();
    final t = context.tokens;
    final ref = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Mark as Paid', style: GoogleFonts.bricolageGrotesque(fontSize: 17, fontWeight: FontWeight.w800, color: t.ink)),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Payment reference / voucher code'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: NeedHubTokens.forest, foregroundColor: Colors.white),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ref == null) return;
    try {
      await AdminApi.instance.updateRewardClaim(claim.id, status: 'PAID', payoutRef: ref.isEmpty ? null : ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as paid — user notified')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        backgroundColor: t.surfaceDark,
        elevation: 0,
        iconTheme: IconThemeData(color: t.onDark),
        title: Text('Reward Claims', style: GoogleFonts.bricolageGrotesque(fontSize: 18, fontWeight: FontWeight.w700, color: t.onDark)),
        actions: [IconButton(icon: Icon(Icons.refresh_rounded, color: t.onDarkMuted), onPressed: _load)],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: t.onDark,
          labelColor: t.onDark,
          unselectedLabelColor: t.onDarkMuted,
          labelStyle: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700),
          unselectedLabelStyle: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w500),
          tabs: _tabs.map((tab) => Tab(text: tab)).toList(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? AdminErrorView(error: _error, onRetry: _load)
              : _claims.isEmpty
                  ? const AdminEmptyView(message: 'No claims here 🎉')
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: NeedHubTokens.ochre,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                        itemCount: _claims.length,
                        itemBuilder: (_, i) => _ClaimTile(
                          claim: _claims[i],
                          t: t,
                          onReject: () => _reject(_claims[i]),
                          onMarkPaid: () => _markPaid(_claims[i]),
                        ),
                      ),
                    ),
    );
  }
}

class _ClaimTile extends StatelessWidget {
  final AdminRewardClaim claim;
  final NeedHubTokens t;
  final VoidCallback onReject;
  final VoidCallback onMarkPaid;

  const _ClaimTile({required this.claim, required this.t, required this.onReject, required this.onMarkPaid});

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
    String formattedDate = claim.createdAt;
    try {
      final date = DateTime.parse(claim.createdAt).toLocal();
      formattedDate = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.rail, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(claim.userName,
                      style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: t.ink)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor().withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _statusColor().withValues(alpha: 0.3)),
                  ),
                  child: Text(claim.status,
                      style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor())),
                ),
              ],
            ),
            Text(claim.userEmail, style: GoogleFonts.hankenGrotesk(fontSize: 12.5, color: t.muted)),
            if (claim.userPhone != null && claim.userPhone!.isNotEmpty)
              Text(claim.userPhone!, style: GoogleFonts.hankenGrotesk(fontSize: 12.5, color: t.muted)),
            const SizedBox(height: 10),
            Text('${claim.offerTitle} (${claim.offerKind})',
                style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w600, color: t.ink2)),
            const SizedBox(height: 4),
            Text('${claim.pointsSpent} pts spent · ₹${(claim.rewardValuePaise / 100).toStringAsFixed(0)} value · ${claim.verifiedPointsAtClaim} verified pts at claim',
                style: GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted)),
            const SizedBox(height: 10),
            // Payout details — collected from the user, shown for the admin to fulfil.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: t.chip, borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: claim.payoutDetails.entries
                    .map((e) => Text('${e.key}: ${e.value}',
                        style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.ink, fontWeight: FontWeight.w600)))
                    .toList(),
              ),
            ),
            if (claim.duplicatePayoutCount > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: NeedHubTokens.clay),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${claim.duplicatePayoutCount} other claim${claim.duplicatePayoutCount == 1 ? '' : 's'} use this payout ID — review before approving',
                      style: GoogleFonts.hankenGrotesk(fontSize: 11.5, color: NeedHubTokens.clay, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
            if (claim.payoutRef != null) ...[
              const SizedBox(height: 8),
              Text('Paid via: ${claim.payoutRef}', style: GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted)),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 12, color: t.muted2),
                const SizedBox(width: 4),
                Text(formattedDate, style: GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted2)),
              ],
            ),
            if (claim.status == 'PENDING') ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: onMarkPaid,
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Mark Paid'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NeedHubTokens.forest,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.thumb_down_outlined, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NeedHubTokens.clay,
                      side: BorderSide(color: NeedHubTokens.clay.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
