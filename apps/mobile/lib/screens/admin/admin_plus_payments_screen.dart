import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/admin_api.dart';
import '../../theme/tokens.dart';
import 'admin_shared.dart';

class AdminPlusPaymentsScreen extends StatefulWidget {
  const AdminPlusPaymentsScreen({super.key});

  @override
  State<AdminPlusPaymentsScreen> createState() => _AdminPlusPaymentsScreenState();
}

class _AdminPlusPaymentsScreenState extends State<AdminPlusPaymentsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<AdminPlusPayment> _payments = [];
  bool _loading = true;
  String _error = '';

  final List<String> _tabs = ['Awaiting', 'Paid', 'Failed'];
  final List<String> _statusFilters = ['AWAITING_CONFIRMATION', 'PAID', 'FAILED'];

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
      final res = await AdminApi.instance.plusPayments(status: _statusFilters[_tabController.index]);
      if (mounted) {
        setState(() {
          _payments = res;
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

  Future<void> _confirmPaid(AdminPlusPayment payment) async {
    final t = context.tokens;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Confirm payment received?', style: GoogleFonts.bricolageGrotesque(fontSize: 17, fontWeight: FontWeight.w800, color: t.ink)),
        content: Text(
          'This activates NeedHub Plus for ${payment.userName} for 30 days.'
          '${payment.userReference != null ? '\n\nUser-provided reference: ${payment.userReference}' : ''}',
          style: GoogleFonts.hankenGrotesk(fontSize: 13.5, color: t.muted, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: NeedHubTokens.forest, foregroundColor: Colors.white),
            child: const Text('Confirm & Activate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AdminApi.instance.updatePlusPayment(payment.id, status: 'PAID');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Activated')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _markFailed(AdminPlusPayment payment) async {
    try {
      await AdminApi.instance.updatePlusPayment(payment.id, status: 'FAILED');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as failed')));
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
        title: Text('Plus Payments', style: GoogleFonts.bricolageGrotesque(fontSize: 18, fontWeight: FontWeight.w700, color: t.onDark)),
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
              : _payments.isEmpty
                  ? const AdminEmptyView(message: 'Nothing here 🎉')
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: NeedHubTokens.ochre,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                        itemCount: _payments.length,
                        itemBuilder: (_, i) => _PaymentTile(
                          payment: _payments[i],
                          t: t,
                          onConfirm: () => _confirmPaid(_payments[i]),
                          onMarkFailed: () => _markFailed(_payments[i]),
                        ),
                      ),
                    ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final AdminPlusPayment payment;
  final NeedHubTokens t;
  final VoidCallback onConfirm;
  final VoidCallback onMarkFailed;

  const _PaymentTile({required this.payment, required this.t, required this.onConfirm, required this.onMarkFailed});

  @override
  Widget build(BuildContext context) {
    String formattedDate = payment.createdAt;
    try {
      final date = DateTime.parse(payment.createdAt).toLocal();
      formattedDate = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: payment.selfReported ? NeedHubTokens.ochre.withValues(alpha: 0.5) : t.rail, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(payment.userName,
                      style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: t.ink)),
                ),
                if (payment.selfReported)
                  const AdminMiniChip(label: '⚠ self-reported'),
              ],
            ),
            Text(payment.userEmail, style: GoogleFonts.hankenGrotesk(fontSize: 12.5, color: t.muted)),
            const SizedBox(height: 10),
            Text('₹${(payment.amountPaise / 100).toStringAsFixed(2)} ${payment.currency} — ${payment.status}',
                style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w600, color: t.ink2)),
            if (payment.userReference != null && payment.userReference!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: t.chip, borderRadius: BorderRadius.circular(8)),
                child: Text('Reference: ${payment.userReference}',
                    style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.ink)),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 12, color: t.muted2),
                const SizedBox(width: 4),
                Text(formattedDate, style: GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted2)),
              ],
            ),
            if (payment.status == 'AWAITING_CONFIRMATION') ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: onConfirm,
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Confirm & Activate'),
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
                    onPressed: onMarkFailed,
                    icon: const Icon(Icons.thumb_down_outlined, size: 16),
                    label: const Text('Mark Failed'),
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
