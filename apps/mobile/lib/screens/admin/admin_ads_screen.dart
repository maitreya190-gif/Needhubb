import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/admin_api.dart';
import '../../theme/tokens.dart';
import 'admin_shared.dart';

class AdminAdsScreen extends StatefulWidget {
  const AdminAdsScreen({super.key});

  @override
  State<AdminAdsScreen> createState() => _AdminAdsScreenState();
}

class _AdminAdsScreenState extends State<AdminAdsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<AdminAdInquiry> _inquiries = [];
  bool _loading = true;
  String _error = '';

  final List<String> _tabs = [
    'All',
    'Pending',
    'Contacted',
    'Approved',
    'Rejected'
  ];
  final List<String?> _statusFilters = [
    null,
    'PENDING',
    'CONTACTED',
    'APPROVED',
    'REJECTED'
  ];

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
    if (!_tabController.indexIsChanging) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final status = _statusFilters[_tabController.index];
      final res = await AdminApi.instance.adInquiries(status: status);
      if (mounted) {
        setState(() {
          _inquiries = res;
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

  Future<void> _updateStatus(AdminAdInquiry inquiry, String status) async {
    try {
      await AdminApi.instance.updateAdInquiry(inquiry.id, status: status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marked as $status')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _delete(AdminAdInquiry inquiry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.tokens.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete Inquiry',
            style: GoogleFonts.bricolageGrotesque(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.tokens.ink)),
        content: Text('Are you sure you want to delete this ad inquiry?',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 15, color: context.tokens.ink)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style:
                      GoogleFonts.hankenGrotesk(color: context.tokens.muted2))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: NeedHubTokens.clay,
                foregroundColor: Colors.white,
                elevation: 0),
            child: Text('Delete',
                style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await AdminApi.instance.deleteAdInquiry(inquiry.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Deleted successfully')));
          _load();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
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
        title: Text(
          'Ad Inquiries',
          style: GoogleFonts.bricolageGrotesque(
              fontSize: 18, fontWeight: FontWeight.w700, color: t.onDark),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: t.onDarkMuted),
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: t.onDark,
          labelColor: t.onDark,
          unselectedLabelColor: t.onDarkMuted,
          labelStyle: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w500),
          tabs: _tabs.map((tab) => Tab(text: tab)).toList(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? AdminErrorView(error: _error, onRetry: _load)
              : _inquiries.isEmpty
                  ? const AdminEmptyView(message: 'No ad inquiries found 🎉')
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: NeedHubTokens.forest,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                        itemCount: _inquiries.length,
                        itemBuilder: (_, i) => _AdInquiryTile(
                          inquiry: _inquiries[i],
                          t: t,
                          onStatusUpdate: (status) =>
                              _updateStatus(_inquiries[i], status),
                          onDelete: () => _delete(_inquiries[i]),
                        ),
                      ),
                    ),
    );
  }
}

class _AdInquiryTile extends StatelessWidget {
  final AdminAdInquiry inquiry;
  final NeedHubTokens t;
  final Function(String) onStatusUpdate;
  final VoidCallback onDelete;

  const _AdInquiryTile({
    required this.inquiry,
    required this.t,
    required this.onStatusUpdate,
    required this.onDelete,
  });

  Color _getStatusColor() {
    switch (inquiry.status) {
      case 'PENDING':
        return NeedHubTokens.ochre;
      case 'CONTACTED':
        return const Color(0xFF3B82F6);
      case 'APPROVED':
        return NeedHubTokens.forest;
      case 'REJECTED':
        return NeedHubTokens.clay;
      default:
        return t.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Format date string (fallback to basic substring if parsing fails)
    String formattedDate = inquiry.createdAt;
    try {
      final date = DateTime.parse(inquiry.createdAt).toLocal();
      formattedDate =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    inquiry.name,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: t.ink),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor().withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _getStatusColor().withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    inquiry.status,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _getStatusColor()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (inquiry.email != null && inquiry.email!.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.email_outlined, size: 14, color: t.muted),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(inquiry.email!,
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 13, color: t.muted))),
                ],
              ),
            if (inquiry.phone != null && inquiry.phone!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.phone_outlined, size: 14, color: t.muted),
                    const SizedBox(width: 4),
                    Expanded(
                        child: Text(inquiry.phone!,
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 13, color: t.muted))),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Product: ${inquiry.product}',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w600, color: t.ink2),
            ),
            if (inquiry.message != null && inquiry.message!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: t.chip,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  inquiry.message!,
                  style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.ink),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 12, color: t.muted2),
                const SizedBox(width: 4),
                Text(
                  formattedDate,
                  style:
                      GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted2),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (inquiry.status == 'PENDING')
                  ElevatedButton.icon(
                    onPressed: () => onStatusUpdate('CONTACTED'),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Mark Contacted'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: GoogleFonts.hankenGrotesk(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                if (inquiry.status == 'PENDING' ||
                    inquiry.status == 'CONTACTED') ...[
                  OutlinedButton.icon(
                    onPressed: () => onStatusUpdate('APPROVED'),
                    icon: const Icon(Icons.thumb_up_outlined, size: 16),
                    label: const Text('Approve'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NeedHubTokens.forest,
                      side: BorderSide(
                          color: NeedHubTokens.forest.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: GoogleFonts.hankenGrotesk(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => onStatusUpdate('REJECTED'),
                    icon: const Icon(Icons.thumb_down_outlined, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NeedHubTokens.clay,
                      side: BorderSide(
                          color: NeedHubTokens.clay.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: GoogleFonts.hankenGrotesk(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  color: t.muted2,
                  iconSize: 20,
                  tooltip: 'Delete Inquiry',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
