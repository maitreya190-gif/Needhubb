import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
      // Optimistic local update.
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

  Future<void> _markOneRead(NhNotification n) async {
    if (!n.isUnread) return;
    final api = ref.read(notificationsApiProvider);
    // Optimistic update.
    final now = DateTime.now();
    notificationsListNotifier.value = notificationsListNotifier.value
        .map((x) => x.id == n.id
            ? NhNotification(
                id: x.id,
                type: x.type,
                title: x.title,
                body: x.body,
                refType: x.refType,
                refId: x.refId,
                createdAt: x.createdAt,
                readAt: now,
              )
            : x)
        .toList();
    unreadCountNotifier.value =
        (unreadCountNotifier.value - 1).clamp(0, 9999);
    try {
      await api.markRead(n.id);
    } catch (_) {/* revert would be noisy — just log */}
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
    final groupOrder = ['Connect', 'Earn', 'Chat', 'Impact', 'Other'];

    return Scaffold(
      backgroundColor: t.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Text('Alerts',
                      style: GoogleFonts.bricolageGrotesque(
                          fontSize: 26, fontWeight: FontWeight.w800, color: t.ink)),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : _markAllRead,
                    child: Text('Mark all read',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: NeedHubTokens.clay)),
                  ),
                ],
              ),
            ),
            if (list.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_none_rounded, size: 44, color: t.muted),
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
                        final isLast = e.key == alerts.length - 1;
                        return Column(
                          children: [
                            _NotifRow(
                              notif: e.value,
                              t: t,
                              onTap: () => _markOneRead(e.value),
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
      case 'Impact':
        return NeedHubTokens.clay;
      default:
        return NeedHubTokens.clay;
    }
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;
  final Color color;
  final NeedHubTokens t;

  const _GroupHeader({required this.label, required this.color, required this.t});

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
                              color: t.ink,
                            )),
                      ),
                      const SizedBox(width: 8),
                      Text(_timeAgo,
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 12, color: t.muted)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(notif.body,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 13, color: t.muted2, height: 1.4)),
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
