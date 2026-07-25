import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../services/notification_navigator.dart';
import '../../../services/notifications_api.dart';
import '../../../services/social_providers.dart';
import '../../../theme/tokens.dart';

class AlertsTab extends ConsumerStatefulWidget {
  const AlertsTab({super.key});

  @override
  ConsumerState<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends ConsumerState<AlertsTab> {
  bool _busy = false;
  bool _selectMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    notificationsListNotifier.addListener(_bump);
    unreadCountNotifier.addListener(_bump);
    // Immediate refresh on tab open.
    Future.microtask(() async {
      final api = ref.read(notificationsApiProvider);
      try {
        notificationsListNotifier.value = await api.list();
      } catch (_) {/* swallow */}
      try {
        unreadCountNotifier.value = await api.unreadCount();
      } catch (_) {/* swallow */}
    });
  }

  @override
  void dispose() {
    notificationsListNotifier.removeListener(_bump);
    unreadCountNotifier.removeListener(_bump);
    super.dispose();
  }

  void _bump() {
    if (mounted) setState(() {});
  }

  Future<void> _markAllRead() async {
    if (_busy) return;
    setState(() => _busy = true);
    final api = ref.read(notificationsApiProvider);
    try {
      await api.markAllRead();
      final now = DateTime.now();
      notificationsListNotifier.value = notificationsListNotifier.value
          .map((n) => NhNotification(
                id: n.id,
                type: n.type,
                title: n.title,
                body: n.body,
                refType: n.refType,
                refId: n.refId,
                createdAt: n.createdAt,
                readAt: n.readAt ?? now,
              ))
          .toList();
      unreadCountNotifier.value = 0;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Clear options bottom sheet ─────────────────────────────────────────
  void _showClearSheet() {
    final t = context.tokens;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: t.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: t.rail,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Clear Notifications',
                style: GoogleFonts.bricolageGrotesque(
                    fontSize: 18, fontWeight: FontWeight.w700, color: t.ink)),
            const SizedBox(height: 4),
            Text('Choose which notifications to remove',
                style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted)),
            const SizedBox(height: 20),
            _ClearOption(
              icon: Icons.today_rounded,
              label: 'Last 24 hours',
              subtitle: 'Clear notifications from today',
              color: NeedHubTokens.forest,
              t: t,
              onTap: () {
                Navigator.pop(ctx);
                _clearByRange('day');
              },
            ),
            const SizedBox(height: 8),
            _ClearOption(
              icon: Icons.date_range_rounded,
              label: 'Last 7 days',
              subtitle: 'Clear notifications from this week',
              color: NeedHubTokens.ochre,
              t: t,
              onTap: () {
                Navigator.pop(ctx);
                _clearByRange('week');
              },
            ),
            const SizedBox(height: 8),
            _ClearOption(
              icon: Icons.delete_sweep_rounded,
              label: 'All time',
              subtitle: 'Clear all notifications permanently',
              color: NeedHubTokens.clay,
              t: t,
              onTap: () {
                Navigator.pop(ctx);
                _confirmClearAll();
              },
            ),
            const SizedBox(height: 8),
            _ClearOption(
              icon: Icons.checklist_rounded,
              label: 'Select manually',
              subtitle: 'Pick specific notifications to clear',
              color: t.ink,
              t: t,
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _selectMode = true;
                  _selectedIds.clear();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClearAll() {
    final t = context.tokens;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Clear all notifications?',
            style: GoogleFonts.bricolageGrotesque(
                fontSize: 17, fontWeight: FontWeight.w700, color: t.ink)),
        content: Text(
            'This will permanently delete all your notifications. This action cannot be undone.',
            style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.hankenGrotesk(
                    fontWeight: FontWeight.w600, color: t.muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearByRange('all');
            },
            child: Text('Clear all',
                style: GoogleFonts.hankenGrotesk(
                    fontWeight: FontWeight.w700, color: NeedHubTokens.clay)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearByRange(String range) async {
    if (_busy) return;
    setState(() => _busy = true);
    final api = ref.read(notificationsApiProvider);
    try {
      final deleted = await api.clearByRange(range);
      // Optimistic: filter out from local list
      final now = DateTime.now();
      Duration? cutoff;
      if (range == 'day') cutoff = const Duration(hours: 24);
      if (range == 'week') cutoff = const Duration(days: 7);

      if (cutoff != null) {
        final threshold = now.subtract(cutoff);
        notificationsListNotifier.value = notificationsListNotifier.value
            .where((n) => n.createdAt.isBefore(threshold))
            .toList();
      } else {
        // 'all'
        notificationsListNotifier.value = [];
      }

      // Refresh unread count
      try {
        unreadCountNotifier.value = await api.unreadCount();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$deleted notification${deleted == 1 ? '' : 's'} cleared'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected() async {
    if (_busy || _selectedIds.isEmpty) return;
    setState(() => _busy = true);
    final api = ref.read(notificationsApiProvider);
    try {
      final deleted = await api.clearSelected(_selectedIds.toList());
      notificationsListNotifier.value = notificationsListNotifier.value
          .where((n) => !_selectedIds.contains(n.id))
          .toList();
      try {
        unreadCountNotifier.value = await api.unreadCount();
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$deleted notification${deleted == 1 ? '' : 's'} cleared'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _selectMode = false;
          _selectedIds.clear();
        });
      }
    }
  }

  Future<void> _deleteSingle(NhNotification notif) async {
    final api = ref.read(notificationsApiProvider);
    // Optimistic removal
    notificationsListNotifier.value =
        notificationsListNotifier.value.where((n) => n.id != notif.id).toList();
    if (notif.isUnread) {
      unreadCountNotifier.value =
          (unreadCountNotifier.value - 1).clamp(0, 9999);
    }
    try {
      await api.deleteOne(notif.id);
    } catch (_) {/* best-effort */}
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final list = notificationsListNotifier.value;

    // Group by our own bucket derived from the backend `type`.
    final groups = <String, List<NhNotification>>{};
    for (final n in list) {
      groups.putIfAbsent(_groupFor(n.type), () => []).add(n);
    }

    // ── Coalesce chat notifications per sender on the client side ──────
    if (groups.containsKey('Chat')) {
      final chatNotifs = groups['Chat']!;
      final bySender = <String, List<NhNotification>>{};
      for (final n in chatNotifs) {
        final key = n.refId ?? n.id;
        bySender.putIfAbsent(key, () => []).add(n);
      }
      final coalesced = <NhNotification>[];
      for (final entry in bySender.entries) {
        final senderNotifs = entry.value;
        senderNotifs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final newest = senderNotifs.first;
        final count = senderNotifs.length;
        final hasUnread = senderNotifs.any((n) => n.isUnread);
        final cleanTitle =
            newest.title.replaceAll(RegExp(r'\s*\(\d+ messages?\)'), '');
        coalesced.add(NhNotification(
          id: newest.id,
          type: newest.type,
          title: count > 1 ? '$cleanTitle ($count messages)' : cleanTitle,
          body: newest.body,
          refType: newest.refType,
          refId: newest.refId,
          createdAt: newest.createdAt,
          readAt: hasUnread ? null : newest.readAt,
        ));
      }
      coalesced.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      groups['Chat'] = coalesced;
    }

    final groupOrder = ['Connect', 'Earn', 'Chat', 'Impact', 'Other'];

    return Scaffold(
      backgroundColor: t.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Text('Alerts',
                      style: GoogleFonts.bricolageGrotesque(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: t.ink)),
                  const Spacer(),
                  if (_selectMode) ...[
                    TextButton(
                      onPressed: () => setState(() {
                        _selectMode = false;
                        _selectedIds.clear();
                      }),
                      child: Text('Cancel',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: t.muted)),
                    ),
                  ] else ...[
                    TextButton(
                      onPressed: _busy ? null : _markAllRead,
                      child: Text('Mark all read',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: NeedHubTokens.clay)),
                    ),
                  ],
                ],
              ),
            ),
            // ── Sub-header: Clear button & selection actions ─────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  if (_selectMode) ...[
                    // Select-all toggle
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_selectedIds.length == list.length) {
                            _selectedIds.clear();
                          } else {
                            _selectedIds
                              ..clear()
                              ..addAll(list.map((n) => n.id));
                          }
                        });
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _selectedIds.length == list.length
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            size: 20,
                            color: NeedHubTokens.clay,
                          ),
                          const SizedBox(width: 6),
                          Text('Select all',
                              style: GoogleFonts.hankenGrotesk(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: t.muted)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text('${_selectedIds.length} selected',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 12, color: t.muted)),
                    const SizedBox(width: 12),
                    _PillButton(
                      label: 'Delete',
                      icon: Icons.delete_outline_rounded,
                      color: NeedHubTokens.clay,
                      enabled: _selectedIds.isNotEmpty && !_busy,
                      onTap: _deleteSelected,
                    ),
                  ] else ...[
                    const Spacer(),
                    if (list.isNotEmpty)
                      _PillButton(
                        label: 'Clear',
                        icon: Icons.filter_list_off_rounded,
                        color: t.muted,
                        enabled: !_busy,
                        onTap: _showClearSheet,
                      ),
                  ],
                ],
              ),
            ),
            // ── Body ─────────────────────────────────────────────────────
            if (list.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_none_rounded,
                          size: 44, color: t.muted),
                      const SizedBox(height: 12),
                      Text('No notifications yet',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 14, color: t.muted)),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
                  children: groupOrder
                      .where((g) => groups.containsKey(g))
                      .expand((group) {
                    final alerts = groups[group]!;
                    final groupColor = _groupColor(group);
                    return [
                      _GroupHeader(label: group, color: groupColor, t: t),
                      ...alerts.asMap().entries.map((e) {
                        final n = e.value;
                        final isLast = e.key == alerts.length - 1;
                        return Column(
                          children: [
                            Dismissible(
                              key: ValueKey(n.id),
                              direction: _selectMode
                                  ? DismissDirection.none
                                  : DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                color: NeedHubTokens.clay.withValues(alpha: 0.15),
                                padding: const EdgeInsets.only(right: 24),
                                child: const Icon(Icons.delete_outline_rounded,
                                    color: NeedHubTokens.clay, size: 22),
                              ),
                              onDismissed: (_) => _deleteSingle(n),
                              child: _selectMode
                                  ? _SelectableNotifRow(
                                      notif: n,
                                      t: t,
                                      selected: _selectedIds.contains(n.id),
                                      onToggle: () {
                                        setState(() {
                                          if (_selectedIds.contains(n.id)) {
                                            _selectedIds.remove(n.id);
                                          } else {
                                            _selectedIds.add(n.id);
                                          }
                                        });
                                      },
                                    )
                                  : _NotifRow(
                                      notif: n,
                                      t: t,
                                      onTap: () =>
                                          NotificationNavigator.handleTap(
                                        context: context,
                                        notif: n,
                                        ref: ref,
                                      ),
                                    ),
                            ),
                            if (!isLast)
                              Divider(color: t.rail, height: 1, indent: 76),
                          ],
                        );
                      }),
                      const SizedBox(height: 8),
                    ];
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _groupFor(String type) {
    switch (type) {
      case 'FRIEND_REQUEST_RECEIVED':
      case 'FRIEND_REQUEST_ACCEPTED':
        return 'Connect';
      case 'NEED_RESPONSE_RECEIVED':
        return 'Earn';
      case 'MESSAGE_RECEIVED':
        return 'Chat';
      case 'REVIEW_RECEIVED':
      case 'POINTS_AWARDED':
      case 'CERT_APPROVED':
      case 'CERT_REJECTED':
      case 'REDEMPTION_READY':
      case 'REPORT_ACTIONED':
        return 'Impact';
      default:
        return 'Other';
    }
  }

  Color _groupColor(String group) {
    switch (group) {
      case 'Connect':
        return NeedHubTokens.forest;
      case 'Earn':
        return NeedHubTokens.ochre;
      case 'Chat':
        return NeedHubTokens.clay;
      case 'Impact':
        return NeedHubTokens.clay;
      default:
        return NeedHubTokens.clay;
    }
  }
}

// ── Pill button widget ─────────────────────────────────────────────────────────

class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(label,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Clear option tile ──────────────────────────────────────────────────────────

class _ClearOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final NeedHubTokens t;
  final VoidCallback onTap;

  const _ClearOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: t.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 12, color: t.muted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: t.muted),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Group header ───────────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  final String label;
  final Color color;
  final NeedHubTokens t;

  const _GroupHeader(
      {required this.label, required this.color, required this.t});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.5,
                )),
          ),
        ],
      ),
    );
  }
}

// ── Notification row ───────────────────────────────────────────────────────────

class _NotifRow extends StatelessWidget {
  final NhNotification notif;
  final NeedHubTokens t;
  final VoidCallback onTap;

  const _NotifRow({required this.notif, required this.t, required this.onTap});

  IconData get _icon {
    switch (notif.type) {
      case 'FRIEND_REQUEST_RECEIVED':
        return Icons.person_add_alt_rounded;
      case 'FRIEND_REQUEST_ACCEPTED':
        return Icons.handshake_outlined;
      case 'NEED_RESPONSE_RECEIVED':
        return Icons.currency_rupee_rounded;
      case 'MESSAGE_RECEIVED':
        return Icons.chat_bubble_outline_rounded;
      case 'REVIEW_RECEIVED':
        return Icons.star_outline_rounded;
      case 'POINTS_AWARDED':
        return Icons.stars_rounded;
      case 'CERT_APPROVED':
        return Icons.verified_rounded;
      case 'CERT_REJECTED':
        return Icons.cancel_outlined;
      case 'REDEMPTION_READY':
        return Icons.card_giftcard_rounded;
      case 'REPORT_ACTIONED':
        return Icons.warning_amber_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  Color get _iconColor {
    switch (notif.type) {
      case 'FRIEND_REQUEST_RECEIVED':
      case 'FRIEND_REQUEST_ACCEPTED':
      case 'CERT_APPROVED':
        return NeedHubTokens.forest;
      case 'NEED_RESPONSE_RECEIVED':
      case 'REVIEW_RECEIVED':
      case 'POINTS_AWARDED':
        return NeedHubTokens.ochre;
      default:
        return NeedHubTokens.clay;
    }
  }

  String get _timeAgo {
    final diff = DateTime.now().difference(notif.createdAt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: notif.isUnread
            ? _iconColor.withValues(alpha: 0.04)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_icon, color: _iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(notif.title,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 14,
                              fontWeight: notif.isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: context.tokens.ink,
                            )),
                      ),
                      const SizedBox(width: 8),
                      Text(_timeAgo,
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 12, color: context.tokens.muted)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(notif.body,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 13,
                          color: context.tokens.muted2,
                          height: 1.4)),
                ],
              ),
            ),
            if (notif.isUnread) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  color: NeedHubTokens.clay,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Selectable notification row (manual selection mode) ────────────────────────

class _SelectableNotifRow extends StatelessWidget {
  final NhNotification notif;
  final NeedHubTokens t;
  final bool selected;
  final VoidCallback onToggle;

  const _SelectableNotifRow({
    required this.notif,
    required this.t,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        color: selected
            ? NeedHubTokens.clay.withValues(alpha: 0.08)
            : (notif.isUnread
                ? NeedHubTokens.clay.withValues(alpha: 0.03)
                : Colors.transparent),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Checkbox
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 22,
              color: selected ? NeedHubTokens.clay : t.muted,
            ),
            const SizedBox(width: 10),
            // Notification content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notif.title,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: t.ink)),
                  const SizedBox(height: 2),
                  Text(notif.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 13, color: t.muted2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
