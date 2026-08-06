import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/admin_api.dart';
import '../../theme/tokens.dart';
import 'admin_shared.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  List<AdminReport> _reports = [];
  bool _loading = true;
  String _error = '';

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
      final r = await AdminApi.instance.reports();
      if (mounted) {
        setState(() {
        _reports = r;
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

  Future<void> _resolve(AdminReport report) async {
    final t = context.tokens;
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: t.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ResolveSheet(report: report, t: t),
    );
    if (result == null) return;
    final action = result['action']!;
    final message = result['message'];
    try {
      await AdminApi.instance.resolveReport(report.id, action, message: message);
      setState(() => _reports.removeWhere((r) => r.id == report.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report resolved: $action')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
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
          'Reports',
          style: GoogleFonts.bricolageGrotesque(
              fontSize: 18, fontWeight: FontWeight.w700, color: t.onDark),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: t.onDarkMuted),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? AdminErrorView(error: _error, onRetry: _load)
              : _reports.isEmpty
                  ? const AdminEmptyView(message: 'No open reports 🎉')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                      itemCount: _reports.length,
                      itemBuilder: (_, i) => _ReportTile(
                        report: _reports[i],
                        t: t,
                        onResolve: () => _resolve(_reports[i]),
                      ),
                    ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final AdminReport report;
  final NeedHubTokens t;
  final VoidCallback onResolve;

  const _ReportTile(
      {required this.report, required this.t, required this.onResolve});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: NeedHubTokens.clay.withValues(alpha: 0.25), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: NeedHubTokens.clay.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    report.targetType,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: NeedHubTokens.clay,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  report.createdAt.length >= 10
                      ? report.createdAt.substring(0, 10)
                      : report.createdAt,
                  style:
                      GoogleFonts.hankenGrotesk(fontSize: 11, color: t.muted),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // The reason (why it was flagged) — this is the reporter's message
            // or the moderation category.
            Text(
              report.reason,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 14, color: t.ink, height: 1.4),
            ),
            const SizedBox(height: 10),
            // What was actually reported: title/body of the need or the
            // message that got flagged. This is the "evidence" panel.
            if (report.targetTitle != null || report.targetBody != null)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: t.paper,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: NeedHubTokens.clay.withValues(alpha: 0.15),
                      width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('REPORTED CONTENT',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: t.muted2,
                            letterSpacing: 0.6)),
                    if (report.targetTitle != null) ...[
                      const SizedBox(height: 4),
                      Text(report.targetTitle!,
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: t.ink)),
                    ],
                    if (report.targetBody != null &&
                        report.targetBody!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(report.targetBody!,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 12.5,
                              color: t.muted2,
                              height: 1.35)),
                    ],
                    if (report.targetAuthorName != null) ...[
                      const SizedBox(height: 6),
                      Text('— by ${report.targetAuthorName}',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 11,
                              color: t.muted,
                              fontStyle: FontStyle.italic)),
                    ],
                  ],
                ),
              ),
            // Message history (for MESSAGE and USER-with-thread reports)
            if (report.contextMessages.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: t.paper,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: t.rail, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                      child: Text('MESSAGE HISTORY',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: t.muted2,
                              letterSpacing: 0.6)),
                    ),
                    const Divider(height: 1),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: report.contextMessages.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 2),
                        itemBuilder: (_, i) {
                          final msg = report.contextMessages[i];
                          final isReported = report.targetType == 'MESSAGE' &&
                              msg.id == report.targetId;
                          return Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isReported
                                  ? NeedHubTokens.clay.withValues(alpha: 0.10)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: isReported
                                  ? Border.all(
                                      color: NeedHubTokens.clay
                                          .withValues(alpha: 0.35),
                                      width: 1)
                                  : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      msg.senderName,
                                      style: GoogleFonts.hankenGrotesk(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: isReported
                                              ? NeedHubTokens.clay
                                              : t.ink),
                                    ),
                                    if (isReported) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: NeedHubTokens.clay
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text('REPORTED',
                                            style: GoogleFonts.hankenGrotesk(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                color: NeedHubTokens.clay)),
                                      ),
                                    ],
                                    const Spacer(),
                                    Text(
                                      msg.createdAt.length >= 16
                                          ? msg.createdAt.substring(11, 16)
                                          : '',
                                      style: GoogleFonts.hankenGrotesk(
                                          fontSize: 10, color: t.muted),
                                    ),
                                  ],
                                ),
                                if (msg.body.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    msg.body,
                                    style: GoogleFonts.hankenGrotesk(
                                        fontSize: 12.5,
                                        color: t.ink,
                                        height: 1.3),
                                  ),
                                ],
                                if (msg.imageUrl != null) ...[
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      msg.imageUrl!,
                                      height: 80,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              report.source == 'user'
                  ? 'Reported by ${report.reporterName}'
                  : report.source == 'moderation_hard'
                      ? 'Auto-blocked by moderation'
                      : report.source == 'moderation_soft'
                          ? 'AI-flagged for review'
                          : 'Reported by ${report.reporterName}',
              style: GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onResolve,
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.surfaceDark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: GoogleFonts.hankenGrotesk(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
                child: const Text('Resolve →'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResolveSheet extends StatefulWidget {
  final AdminReport report;
  final NeedHubTokens t;

  const _ResolveSheet({required this.report, required this.t});

  @override
  State<_ResolveSheet> createState() => _ResolveSheetState();
}

class _ResolveSheetState extends State<_ResolveSheet> {
  bool _warnMode = false;
  final _msgController = TextEditingController();

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  void _pop(String action, {String? message}) =>
      Navigator.pop(context, {'action': action, if (message != null) 'message': message});

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_warnMode) ...[
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _warnMode = false),
                      child: Icon(Icons.arrow_back_rounded, color: t.ink, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Warn user',
                      style: GoogleFonts.bricolageGrotesque(
                          fontSize: 18, fontWeight: FontWeight.w700, color: t.ink),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Type the warning message that will appear in the user\'s notifications:',
                  style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted, height: 1.4),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _msgController,
                  autofocus: true,
                  maxLines: 3,
                  style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
                  decoration: InputDecoration(
                    hintText: 'e.g. Your post violated our community guidelines…',
                    hintStyle: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted),
                    filled: true,
                    fillColor: t.paper,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: t.rail),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: t.rail),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: NeedHubTokens.ochre, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _pop('warn', message: _msgController.text.trim().isEmpty ? null : _msgController.text.trim()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NeedHubTokens.ochre,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Send warning', style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ] else ...[
                Text(
                  'Resolve report',
                  style: GoogleFonts.bricolageGrotesque(
                      fontSize: 18, fontWeight: FontWeight.w700, color: t.ink),
                ),
                const SizedBox(height: 16),
                _ActionTile(
                  icon: Icons.close_rounded, color: t.muted2,
                  label: 'Dismiss', desc: 'Close without action',
                  onTap: () => _pop('dismiss'), t: t,
                ),
                _ActionTile(
                  icon: Icons.warning_amber_rounded, color: NeedHubTokens.ochre,
                  label: 'Warn user', desc: 'Send a warning message to the poster',
                  onTap: () => setState(() => _warnMode = true), t: t,
                ),
                if (widget.report.targetType == 'NEED')
                  _ActionTile(
                    icon: Icons.delete_outline_rounded, color: NeedHubTokens.clay,
                    label: 'Remove post', desc: 'Delete the flagged need',
                    onTap: () => _pop('remove_need'), t: t,
                  ),
                if (widget.report.targetType == 'USER')
                  _ActionTile(
                    icon: Icons.block_rounded, color: NeedHubTokens.clay,
                    label: 'Ban user', desc: 'Permanently delete this account',
                    onTap: () => _pop('ban_user'), t: t,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String desc;
  final VoidCallback onTap;
  final NeedHubTokens t;

  const _ActionTile({
    required this.icon, required this.color, required this.label,
    required this.desc, required this.onTap, required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.paper,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: t.rail, width: 1),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: GoogleFonts.hankenGrotesk(
                        fontSize: 14, fontWeight: FontWeight.w600, color: color)),
                    Text(desc, style: GoogleFonts.hankenGrotesk(
                        fontSize: 12, color: t.muted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.muted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
