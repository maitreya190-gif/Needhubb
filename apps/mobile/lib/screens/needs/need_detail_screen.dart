import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/need.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../theme/tokens.dart';
import '../../widgets/nh_empty_state.dart';
import '../../widgets/nh_report_sheet.dart';
import '../../widgets/nh_urgent_badge.dart';
import '../hub/conversation_screen.dart';
import '../../widgets/nh_full_screen_image_viewer.dart';
import '../../services/social_providers.dart';
import '../../services/needs_api.dart';

class _OfferRevisionData {
  final String note;
  final String amount;
  final String? workSampleUrl;
  final DateTime createdAt;

  const _OfferRevisionData({
    required this.note,
    required this.amount,
    this.workSampleUrl,
    required this.createdAt,
  });
}

class _OfferData {
  final String initials;
  final String name;
  final String note;
  final String amount;
  final Color tint;
  final String? responseId;
  final String? responderId;
  final String status;
  final String? avatarUrl;
  final String? workSampleUrl;
  final DateTime? createdAt;
  final List<_OfferRevisionData> revisions;

  const _OfferData({
    required this.initials,
    required this.name,
    required this.note,
    required this.amount,
    required this.tint,
    this.responseId,
    this.responderId,
    this.status = 'PENDING',
    this.avatarUrl,
    this.workSampleUrl,
    this.createdAt,
    this.revisions = const [],
  });

  _OfferData withStatus(String newStatus) => _OfferData(
        initials: initials,
        name: name,
        note: note,
        amount: amount,
        tint: tint,
        responseId: responseId,
        responderId: responderId,
        status: newStatus,
        avatarUrl: avatarUrl,
        workSampleUrl: workSampleUrl,
        createdAt: createdAt,
        revisions: revisions,
      );
}

class NeedDetailScreen extends ConsumerStatefulWidget {
  final Need need;

  const NeedDetailScreen({super.key, required this.need});

  @override
  ConsumerState<NeedDetailScreen> createState() => _NeedDetailScreenState();
}

class _NeedDetailScreenState extends ConsumerState<NeedDetailScreen> {
  Need get need => widget.need;
  List<_OfferData> _realOffers = const [];
  List<Map<String, dynamic>> _needReviews = const [];
  String _offerSortMode = 'newest';
  Timer? _pollTimer;

  bool get _isNeedFrozen =>
      need.isFrozen || _realOffers.any((o) => o.status == 'ACCEPTED');

  bool _renewing = false;

  /// Reposts an expired urgent need with a fresh deadline — the owner-only
  /// counterpart to Rescue Mode's expiry (see POST /needs/:id/renew, and
  /// lib/urgency.ts on the API for why nothing auto-renews on its own).
  Future<void> _renewNeed() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 3)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 3))),
    );
    if (time == null || !mounted) return;
    final deadline =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);

    setState(() => _renewing = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/needs/${need.id}/renew', {
        'deadline': deadline.toIso8601String(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Renewed! Your need is live again with a fresh deadline.'),
        backgroundColor: NeedHubTokens.forest,
      ));
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _renewing = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not renew right now. Please try again.'),
      ));
    }
  }

  @override
  void initState() {
    super.initState();
    offersNotifier.addListener(_rebuild);
    Future.microtask(() {
      _hydrateOffers();
      _fetchNeedReviews();
    });
    // Poll for new responses every 15 s so the poster sees them without refreshing
    _pollTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _hydrateOffers());
  }

  Future<void> _fetchNeedReviews() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/reviews/need/${need.id}');
      if (!mounted) return;
      setState(() {
        _needReviews =
            ((res['reviews'] as List?) ?? const []).cast<Map<String, dynamic>>();
      });
    } catch (_) {}
  }

  bool get _isPoster {
    final myId = ref.read(authProvider).userId;
    if (myId != null && need.posterId.isNotEmpty) return need.posterId == myId;
    // Fallback for mock data
    return need.authorName == 'You' || need.authorInitials == 'ME';
  }

  NeedOffer? get _myOffer {
    final localOffer = need.myOffer;
    if (localOffer != null) return localOffer;

    final myId = ref.read(authProvider).userId;
    if (myId == null) return null;
    for (final offer in _realOffers) {
      if (offer.responderId == myId) {
        return NeedOffer(
          name: 'You',
          initials: 'ME',
          note: offer.note,
          amount: offer.amount,
          color: offer.tint,
          responseId: offer.responseId,
          workSampleUrl: offer.workSampleUrl,
          createdAt: offer.createdAt,
        );
      }
    }
    return null;
  }

  Future<void> _hydrateOffers() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/needs/${need.id}/responses');
      final rows = ((res['responses'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _realOffers = rows.map((j) {
          final responder =
              (j['responder'] as Map<String, dynamic>?) ?? const {};
          final responderProfile =
              (responder['profile'] as Map<String, dynamic>?) ?? const {};
          final name = responder['displayName'] as String? ?? 'Someone';
          final initials = _initialsOf(name);
          final price = (j['quotedPrice'] as num?)?.toInt();
          final revisions = ((j['revisions'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map((revision) {
            final revisionPrice = (revision['quotedPrice'] as num?)?.toInt();
            return _OfferRevisionData(
              note: revision['message'] as String? ?? '',
              amount: revisionPrice != null ? '₹$revisionPrice' : '—',
              workSampleUrl: revision['workSampleUrl'] as String?,
              createdAt:
                  DateTime.tryParse(revision['createdAt'] as String? ?? '') ??
                      DateTime.now(),
            );
          }).toList();
          return _OfferData(
            initials: initials,
            name: name,
            note: j['message'] as String? ?? '',
            amount: price != null ? '₹$price' : '—',
            tint: NeedHubTokens.forest,
            responseId: j['id'] as String?,
            responderId: responder['id'] as String?,
            status: j['status'] as String? ?? 'PENDING',
            avatarUrl: responderProfile['avatarUrl'] as String?,
            workSampleUrl: j['workSampleUrl'] as String?,
            createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
            revisions: revisions,
          );
        }).toList();
      });
    } catch (e) {
      debugPrint('[NeedDetailScreen] Failed to hydrate offers for ${need.id}: $e');
    }
  }

  /// Shows a freeze-warning dialog before accepting. The poster must
  /// explicitly confirm — accepting an offer permanently freezes the need.
  Future<void> _confirmAndAcceptOffer(String responseId, String offerName) async {
    final t = context.tokens;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: NeedHubTokens.clay.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lock_rounded,
                  color: NeedHubTokens.clay, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Accept & Freeze Need?',
                  style: GoogleFonts.bricolageGrotesque(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: t.ink)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 14, color: t.muted2, height: 1.5),
                children: [
                  const TextSpan(text: 'You are about to accept '),
                  TextSpan(
                    text: offerName,
                    style: GoogleFonts.hankenGrotesk(
                        fontWeight: FontWeight.w700, color: t.ink),
                  ),
                  const TextSpan(text: "'s offer."),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: NeedHubTokens.clay.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: NeedHubTokens.clay.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: NeedHubTokens.clay, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This will permanently freeze your need. '  
                      'No other applicants can respond, and '  
                      'this action cannot be undone.',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 13,
                          color: NeedHubTokens.clay,
                          height: 1.45,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text('Cancel',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.muted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: NeedHubTokens.forest,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text('Yes, accept & freeze',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _acceptOffer(responseId);
    }
  }

  Future<void> _acceptOffer(String responseId) async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.patch(
        '/needs/${need.id}/responses/$responseId',
        {'status': 'ACCEPTED'},
      );
      if (!mounted) return;
      final dmThreadId = res['dmThreadId'] as String?;
      final accepted = _realOffers.firstWhere(
        (o) => o.responseId == responseId,
        orElse: () => const _OfferData(
          initials: '?', name: 'Helper', note: '', amount: '—',
          tint: NeedHubTokens.forest,
        ),
      );
      setState(() {
        _realOffers = _realOffers
            .map((o) => o.responseId == responseId ? o.withStatus('ACCEPTED') : o)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offer accepted! Opening chat…')),
      );
      // Jump straight into the conversation so the poster can message the
      // responder right away. The DmThread was created server-side on accept.
      if (accepted.responderId != null) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ConversationScreen(
              name: accepted.name,
              initials: accepted.initials,
              avatarColor: NeedHubTokens.forest,
              avatarUrl: accepted.avatarUrl,
              userId: accepted.responderId,
              threadId: dmThreadId,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not accept offer: $e')),
        );
      }
    }
  }

  Future<void> _declineOffer(String responseId) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.patch(
          '/needs/${need.id}/responses/$responseId', {'status': 'DECLINED'});
      if (mounted) {
        setState(() {
          _realOffers = _realOffers
              .map((o) =>
                  o.responseId == responseId ? o.withStatus('DECLINED') : o)
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not decline offer: $e')),
        );
      }
    }
  }

  static String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  String _offerKey(_OfferData offer) {
    final currentUserId = ref.read(authProvider).userId;
    if (offer.responderId != null && offer.responderId == currentUserId) return 'me';
    if (offer.name == 'You' || offer.initials == 'ME') return 'me';
    if (offer.responderId != null) return 'responder:${offer.responderId}';
    if (offer.responseId != null) return 'response:${offer.responseId}';
    return 'local:${offer.name}:${offer.note}';
  }

  static bool _canEditOffer(NeedOffer? offer) {
    final createdAt = offer?.createdAt;
    if (offer == null) return false;
    if (createdAt == null) return true;
    return DateTime.now().difference(createdAt) <= const Duration(minutes: 10);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _pollTimer?.cancel();
    offersNotifier.removeListener(_rebuild);
    super.dispose();
  }

  Color get _categoryColor {
    switch (need.category) {
      case 'earn':
        return NeedHubTokens.ochre;
      case 'chitchat':
        return NeedHubTokens.clay;
      default:
        return NeedHubTokens.forest;
    }
  }

  String get _categoryLabel {
    switch (need.category) {
      case 'earn':
        return 'Earn';
      case 'chitchat':
        return 'Chit-chat';
      default:
        return 'Connect';
    }
  }

  String get _actionLabel {
    switch (need.category) {
      case 'earn':
        return 'Apply to Help';
      case 'chitchat':
        return 'Start a chat';
      default:
        return 'Connect';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cat = _categoryColor;
    final hasBudget = need.budgetMin != null;

    return Scaffold(
      backgroundColor: t.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header nav
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: t.card,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: t.ink.withValues(alpha: 0.09),
                                  width: 1,
                                ),
                              ),
                              child: Icon(Icons.chevron_left_rounded,
                                  size: 20, color: t.ink),
                            ),
                          ),
                          if (_isPoster) ...[
                            Row(
                              children: [
                                if (need.isExpiredUrgent) ...[
                                  TextButton.icon(
                                    onPressed: _renewing ? null : _renewNeed,
                                    icon: _renewing
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Icon(Icons.replay_rounded,
                                            size: 18),
                                    label: const Text('Renew'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: NeedHubTokens.clay,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  color: t.ink,
                                  tooltip: 'Edit Need',
                                  onPressed: _isNeedFrozen
                                      ? null
                                      : () {
                                          showModalBottomSheet(
                                            context: context,
                                            isScrollControlled: true,
                                            backgroundColor: Colors.transparent,
                                            builder: (_) => _EditNeedSheet(
                                              need: need,
                                              onUpdated: () => setState(() {}),
                                            ),
                                          );
                                        },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                                  color: Colors.red,
                                  tooltip: 'Delete Need',
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Delete Need'),
                                        content: const Text(
                                            'Are you sure you want to delete this need? This action cannot be undone.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () async {
                                              Navigator.pop(ctx);
                                              // Temp-ID needs were never saved to the server — just remove locally
                                              if (need.id.startsWith('posted_')) {
                                                mockNeeds.removeWhere((n) => n.id == need.id);
                                                feedNeedsNotifier.value = feedNeedsNotifier.value.where((n) => n.id != need.id).toList();
                                                if (mounted) {
                                                  Navigator.of(context).pop();
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('Need removed.')),
                                                  );
                                                }
                                                return;
                                              }
                                              try {
                                                await ref.read(needsApiProvider).deleteNeed(need.id);
                                                if (!mounted) return;
                                                Navigator.of(context).pop();
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Need deleted successfully.')),
                                                );
                                              } catch (e) {
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text('Failed to delete need: $e')),
                                                  );
                                                }
                                              }
                                            },
                                            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ] else ...[
                            GestureDetector(
                              onTap: () => NhReportSheet.open(
                                context,
                                targetName: need.title,
                                targetType: 'NEED',
                                targetId: need.id,
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.flag_outlined,
                                      size: 15, color: t.muted),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Report',
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: t.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Main need card (with left bar)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: t.card,
                          border: Border.all(
                            color:
                                const Color(0xFF211E17).withValues(alpha: 0.10),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          children: [
                            // Left bar
                            Positioned(
                              top: 0,
                              bottom: 0,
                              left: 0,
                              child: Container(width: 8, color: cat),
                            ),
                            // Content
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(24, 20, 20, 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Category + pay badge row
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: cat,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  child: Text(
                                                    _categoryLabel
                                                        .toUpperCase(),
                                                    style: GoogleFonts
                                                        .hankenGrotesk(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing:
                                                          0.06 * 11,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                                if (need.isUrgent) ...[
                                                  const SizedBox(width: 8),
                                                  NhUrgentBadge(need: need),
                                                ] else if (need
                                                    .isExpiredUrgent) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 10,
                                                        vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: t.muted
                                                          .withValues(
                                                              alpha: 0.15),
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(20),
                                                    ),
                                                    child: Text(
                                                      'Expired',
                                                      style: GoogleFonts
                                                          .hankenGrotesk(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: t.muted,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              need.title,
                                              style: GoogleFonts
                                                  .bricolageGrotesque(
                                                fontSize: 22,
                                                fontWeight: FontWeight.w800,
                                                color: t.ink,
                                                height: 1.15,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (hasBudget) ...[
                                        const SizedBox(width: 14),
                                        Transform.rotate(
                                          angle: 0.0524,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 10),
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                  color: cat, width: 2.5),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Column(
                                              children: [
                                                Text(
                                                  '₹${need.budgetMin}',
                                                  style: GoogleFonts
                                                      .bricolageGrotesque(
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.w800,
                                                    color: cat,
                                                    height: 1,
                                                  ),
                                                ),
                                                Text(
                                                  'per job',
                                                  style:
                                                      GoogleFonts.hankenGrotesk(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: t.muted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),

                                  // Description
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Text(
                                      need.description,
                                      style: GoogleFonts.hankenGrotesk(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: t.ink2,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),

                                  // Tags
                                  if (need.tags.isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    Wrap(
                                      spacing: 7,
                                      runSpacing: 7,
                                      children: need.tags
                                          .map((tag) => Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: t.chip,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  '#$tag',
                                                  style:
                                                      GoogleFonts.hankenGrotesk(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    color: t.muted2,
                                                  ),
                                                ),
                                              ))
                                          .toList(),
                                    ),
                                  ],

                                  // Footer (author)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Container(
                                      padding: const EdgeInsets.only(top: 14),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          top: BorderSide(
                                            color: const Color(0xFF211E17)
                                                .withValues(alpha: 0.16),
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Builder(builder: (_) {
                                            final url = need.posterAvatarUrl;
                                            if (url != null && url.isNotEmpty) {
                                              return ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                child: Image.network(
                                                  url,
                                                  width: 34,
                                                  height: 34,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      _InitialsAvatar(
                                                    initials:
                                                        need.authorInitials,
                                                    tint: t.rail2,
                                                    textColor: t.muted4,
                                                    size: 34,
                                                  ),
                                                ),
                                              );
                                            }
                                            return _InitialsAvatar(
                                              initials: need.authorInitials,
                                              tint: t.rail2,
                                              textColor: t.muted4,
                                              size: 34,
                                            );
                                          }),
                                          const SizedBox(width: 9),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    need.authorName,
                                                    style:
                                                        GoogleFonts.hankenGrotesk(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w700,
                                                      color: t.ink,
                                                    ),
                                                  ),
                                                  if (need.posterFaceVerified) ...[
                                                    const SizedBox(width: 4),
                                                    const Icon(
                                                      Icons.verified_user_rounded,
                                                      size: 12,
                                                      color: Color(0xFF2563EB),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              Builder(builder: (context) {
                                                final userOffers =
                                                    (mockOffers[need.id] ?? [])
                                                        .map((o) => _OfferData(
                                                              initials:
                                                                  o.initials,
                                                              name: o.name,
                                                              note: o.note,
                                                              amount: o.amount,
                                                              tint: o.color,
                                                              responseId:
                                                                  o.responseId,
                                                              workSampleUrl: o
                                                                  .workSampleUrl,
                                                              createdAt:
                                                                  o.createdAt,
                                                            ))
                                                        .toList();

                                                final Map<String, _OfferData>
                                                    mergedMap = {};
                                                for (final o in _realOffers) {
                                                  mergedMap[_offerKey(o)] = o;
                                                }
                                                for (final u in userOffers) {
                                                  final key = _offerKey(u);
                                                  if (!mergedMap
                                                      .containsKey(key)) {
                                                    mergedMap[key] = u;
                                                  }
                                                }
                                                final count = mergedMap.length;
                                                return Text(
                                                  '${need.location} · $count ${count == 1 ? 'offer' : 'offers'}',
                                                  style:
                                                      GoogleFonts.hankenGrotesk(
                                                    fontSize: 12,
                                                    color: t.muted,
                                                  ),
                                                );
                                              }),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Recent offers section — all offers made by people are visible
                    Builder(builder: (context) {
                      final userOffers = (mockOffers[need.id] ?? [])
                          .map((o) => _OfferData(
                                initials: o.initials,
                                name: o.name,
                                note: o.note,
                                amount: o.amount,
                                tint: o.color,
                                responseId: o.responseId,
                                workSampleUrl: o.workSampleUrl,
                                createdAt: o.createdAt,
                              ))
                          .toList();

                      final Map<String, _OfferData> mergedMap = {};
                      for (final o in _realOffers) {
                        mergedMap[_offerKey(o)] = o;
                      }
                      for (final u in userOffers) {
                        final key = _offerKey(u);
                        if (!mergedMap.containsKey(key)) {
                          mergedMap[key] = u;
                        }
                      }
                      final List<_OfferData> displayOffers =
                          mergedMap.values.toList();

                      // Apply sorting: time, price, location
                      if (_offerSortMode == 'oldest') {
                        displayOffers.sort((a, b) => 1);
                      } else if (_offerSortMode == 'price_high') {
                        displayOffers.sort((a, b) {
                          final pa = int.tryParse(
                                  a.amount.replaceAll(RegExp(r'[^\d]'), '')) ??
                              0;
                          final pb = int.tryParse(
                                  b.amount.replaceAll(RegExp(r'[^\d]'), '')) ??
                              0;
                          return pb.compareTo(pa);
                        });
                      } else if (_offerSortMode == 'price_low') {
                        displayOffers.sort((a, b) {
                          final pa = int.tryParse(
                                  a.amount.replaceAll(RegExp(r'[^\d]'), '')) ??
                              0;
                          final pb = int.tryParse(
                                  b.amount.replaceAll(RegExp(r'[^\d]'), '')) ??
                              0;
                          return pa.compareTo(pb);
                        });
                      } else if (_offerSortMode == 'nearest') {
                        displayOffers.sort((a, b) => a.name.compareTo(b.name));
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'OFFERS (${displayOffers.length})',
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.08 * 12,
                                    color: t.muted,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'Public Offers',
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: NeedHubTokens.forest,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Filter/Sort chips row
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _OfferSortChip(
                                    label: '⏱ Newest',
                                    selected: _offerSortMode == 'newest',
                                    onTap: () => setState(
                                        () => _offerSortMode = 'newest'),
                                    t: t,
                                  ),
                                  const SizedBox(width: 6),
                                  _OfferSortChip(
                                    label: '💰 Highest ₹',
                                    selected: _offerSortMode == 'price_high',
                                    onTap: () => setState(
                                        () => _offerSortMode = 'price_high'),
                                    t: t,
                                  ),
                                  const SizedBox(width: 6),
                                  _OfferSortChip(
                                    label: '🏷 Lowest ₹',
                                    selected: _offerSortMode == 'price_low',
                                    onTap: () => setState(
                                        () => _offerSortMode = 'price_low'),
                                    t: t,
                                  ),
                                  const SizedBox(width: 6),
                                  _OfferSortChip(
                                    label: '📍 Nearest',
                                    selected: _offerSortMode == 'nearest',
                                    onTap: () => setState(
                                        () => _offerSortMode = 'nearest'),
                                    t: t,
                                  ),
                                  const SizedBox(width: 6),
                                  _OfferSortChip(
                                    label: '⏳ Oldest',
                                    selected: _offerSortMode == 'oldest',
                                    onTap: () => setState(
                                        () => _offerSortMode = 'oldest'),
                                    t: t,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (displayOffers.isEmpty)
                              const NhEmptyState(
                                icon: Icons.inbox_outlined,
                                title: 'No offers yet',
                                subtitle:
                                    'Offers made by people will appear here',
                              )
                            else
                              ...displayOffers.map((o) => Padding(
                                    padding: const EdgeInsets.only(bottom: 9),
                                    child: _OfferCard(
                                      initials: o.initials,
                                      name: o.name,
                                      note: o.note,
                                      amount: o.amount,
                                      tint: o.tint,
                                      catTint: cat,
                                      t: t,
                                      isPoster: _isPoster,
                                      status: o.status,
                                      avatarUrl: o.avatarUrl,
                                      workSampleUrl: o.workSampleUrl,
                                      revisions: o.revisions,
                                      onAccept: (_isPoster &&
                                              o.responseId != null)
                                          ? () => _confirmAndAcceptOffer(
                                                o.responseId!, o.name)
                                          : null,
                                      onDecline: (_isPoster &&
                                              o.responseId != null)
                                          ? () => _declineOffer(o.responseId!)
                                          : null,
                                    ),
                                  )),
                          ],
                        ),
                      );
                    }),

                    // Feedback & Ratings section — rendered when need is frozen or accepted
                    if (_isNeedFrozen) ...[
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _buildFeedbackSection(context, t),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // CTA button — hidden entirely for the poster of the need
            ValueListenableBuilder<int>(
              valueListenable: offersNotifier,
              builder: (context, _, __) {
                if (_isPoster) return const SizedBox.shrink();
                if (_isNeedFrozen) {
                  return Container(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      16,
                      20,
                      MediaQuery.of(context).padding.bottom + 16,
                    ),
                    decoration: BoxDecoration(
                      color: t.paper,
                      border: Border(top: BorderSide(color: t.rail, width: 1)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.lock_outline_rounded, size: 18),
                        label: const Text('Need Accepted & Frozen'),
                        onPressed: null,
                        style: ElevatedButton.styleFrom(
                          disabledBackgroundColor: t.rail,
                          disabledForegroundColor: t.muted,
                        ),
                      ),
                    ),
                  );
                }

                final myOffer = _myOffer;
                final hasApplied = myOffer != null;
                final canEdit = !hasApplied || _canEditOffer(myOffer);
                final ctaText = hasApplied
                    ? (canEdit
                        ? (need.category == 'earn'
                            ? 'Edit Offered Help'
                            : 'Edit Application')
                        : (need.category == 'earn'
                            ? 'Offer Locked'
                            : 'Application Locked'))
                    : _actionLabel;

                return Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    MediaQuery.of(context).padding.bottom + 16,
                  ),
                  decoration: BoxDecoration(
                    color: t.paper,
                    border: Border(top: BorderSide(color: t.rail, width: 1)),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      icon: hasApplied
                          ? Icon(
                              canEdit
                                  ? Icons.edit_outlined
                                  : Icons.lock_outline_rounded,
                              size: 18)
                          : const SizedBox.shrink(),
                      label: Text(ctaText),
                      onPressed: canEdit
                          ? () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => need.category == 'earn'
                              ? _EarnOfferSheet(
                                  need: need, existingOffer: myOffer)
                              : _ConnectSheet(
                                  need: need,
                                  existingOffer: myOffer,
                                  actionLabel: ctaText,
                                  categoryColor: cat,
                                ),
                        );
                      }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cat,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: GoogleFonts.bricolageGrotesque(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackSection(BuildContext context, NeedHubTokens t) {
    final currentUserId = ref.read(authProvider).userId;
    final acceptedOffer = _realOffers.firstWhere(
      (o) => o.status.toUpperCase() == 'ACCEPTED',
      orElse: () => _realOffers.isNotEmpty
          ? _realOffers.first
          : const _OfferData(
              initials: '?',
              name: 'User',
              note: '',
              amount: '—',
              tint: NeedHubTokens.forest,
            ),
    );

    final isPoster = _isPoster;
    final isAcceptedHelper = acceptedOffer.responderId == currentUserId;
    final isParticipant = isPoster || isAcceptedHelper;

    final rawCounterpartyName = isPoster ? acceptedOffer.name : need.authorName;
    final counterpartyName = (rawCounterpartyName.isEmpty || rawCounterpartyName == 'a')
        ? (isPoster ? 'Helper' : 'Poster')
        : rawCounterpartyName;
    final counterpartyId = isPoster ? acceptedOffer.responderId : need.posterId;

    final myReview = _needReviews.firstWhere(
      (r) => r['reviewerId'] == currentUserId,
      orElse: () => const {},
    );
    final hasMyReview = myReview.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(
          color: const Color(0xFF211E17).withValues(alpha: 0.10),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, color: Color(0xFFEAB308), size: 20),
              const SizedBox(width: 8),
              Text(
                'FEEDBACK & RATINGS (${_needReviews.length})',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.08 * 12,
                  color: t.ink,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF15803D).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'FROZEN',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF15803D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_needReviews.isEmpty)
            Text(
              'No feedback submitted yet.',
              style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted),
            )
          else
            ..._needReviews.map((rev) {
              final reviewer = rev['reviewer'] as Map<String, dynamic>? ?? {};
              final reviewerProfile =
                  reviewer['profile'] as Map<String, dynamic>?;
              final reviewerName =
                  reviewer['displayName'] as String? ?? 'User';
              final rating = (rev['rating'] as num?)?.toInt() ?? 5;
              final comment = rev['comment'] as String?;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.paper,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.rail, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ClipOval(
                          child: reviewerProfile?['avatarUrl'] != null
                              ? Image.network(
                                  reviewerProfile!['avatarUrl'] as String,
                                  width: 28,
                                  height: 28,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 28,
                                    height: 28,
                                    color: t.rail2,
                                    alignment: Alignment.center,
                                    child: Text(
                                      reviewerName.isNotEmpty
                                          ? reviewerName[0]
                                          : '?',
                                      style: GoogleFonts.hankenGrotesk(
                                          fontSize: 11,
                                          color: t.muted4,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 28,
                                  height: 28,
                                  color: t.rail2,
                                  alignment: Alignment.center,
                                  child: Text(
                                    reviewerName.isNotEmpty
                                        ? reviewerName[0]
                                        : '?',
                                    style: GoogleFonts.hankenGrotesk(
                                        fontSize: 11,
                                        color: t.muted4,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            reviewerName,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: t.ink,
                            ),
                          ),
                        ),
                        Row(
                          children: List.generate(
                            5,
                            (i) => Icon(
                              i < rating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 14,
                              color:
                                  i < rating ? const Color(0xFFEAB308) : t.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (comment != null && comment.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        comment,
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 12.5, color: t.ink),
                      ),
                    ],
                  ],
                ),
              );
            }),
          if (isParticipant &&
              counterpartyId != null &&
              counterpartyId.isNotEmpty &&
              !hasMyReview) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.rate_review_outlined, size: 18),
                label: Text('Rate & Give Feedback to $counterpartyName'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NeedHubTokens.forest,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _FeedbackSheet(
                      needId: need.id,
                      revieweeId: counterpartyId,
                      revieweeName: counterpartyName,
                      onSubmitted: _fetchNeedReviews,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OfferCard extends StatefulWidget {
  final String initials;
  final String name;
  final String note;
  final String amount;
  final Color tint;
  final Color catTint;
  final NeedHubTokens t;
  final bool isPoster;
  final String status;
  final String? avatarUrl;
  final String? workSampleUrl;
  final List<_OfferRevisionData> revisions;
  final Future<void> Function()? onAccept;
  final Future<void> Function()? onDecline;

  const _OfferCard({
    required this.initials,
    required this.name,
    required this.note,
    required this.amount,
    required this.tint,
    required this.catTint,
    required this.t,
    this.isPoster = false,
    this.status = 'PENDING',
    this.avatarUrl,
    this.workSampleUrl,
    this.revisions = const [],
    this.onAccept,
    this.onDecline,
  });

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  bool _acting = false;

  void _showOfferDetails() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _OfferDetailsSheet(
        name: widget.name,
        note: widget.note,
        amount: widget.amount,
        workSampleUrl: widget.workSampleUrl,
        revisions: widget.revisions,
        t: widget.t,
      ),
    );
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _OfferHistorySheet(revisions: widget.revisions, t: widget.t),
    );
  }

  Future<void> _tap(Future<void> Function() fn) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final isAccepted = widget.status == 'ACCEPTED';
    final isDeclined = widget.status == 'DECLINED';

    return Opacity(
      opacity: isDeclined ? 0.5 : 1.0,
      child: GestureDetector(
        onTap: _showOfferDetails,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: isAccepted
                ? NeedHubTokens.forest.withValues(alpha: 0.06)
                : t.card,
            border: Border.all(
              color: isAccepted
                  ? NeedHubTokens.forest.withValues(alpha: 0.3)
                  : const Color(0xFF211E17).withValues(alpha: 0.08),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Profile picture — network image with initials fallback
                  Builder(builder: (_) {
                    final url = widget.avatarUrl;
                    if (url != null && url.isNotEmpty) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.network(
                          url,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _InitialsAvatar(
                            initials: widget.initials,
                            tint: widget.tint,
                            size: 40,
                          ),
                        ),
                      );
                    }
                    return _InitialsAvatar(
                      initials: widget.initials,
                      tint: widget.tint,
                      size: 40,
                    );
                  }),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: t.ink,
                          ),
                        ),
                        Text(
                          widget.note,
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 12,
                            color: t.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    widget.amount,
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: widget.catTint,
                    ),
                  ),
                  if (widget.revisions.isNotEmpty)
                    IconButton(
                      tooltip: 'Offer history',
                      onPressed: _showHistory,
                      icon:
                          Icon(Icons.history_rounded, size: 18, color: t.muted),
                    ),
                ],
              ),
              if (isAccepted) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: NeedHubTokens.forest, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Accepted',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: NeedHubTokens.forest),
                    ),
                  ],
                ),
              ] else if (isDeclined) ...[
                const SizedBox(height: 8),
                Text(
                  'Declined',
                  style:
                      GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted),
                ),
              ] else if (widget.isPoster &&
                  widget.onAccept != null &&
                  !isAccepted &&
                  !isDeclined) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _acting ? null : () => _tap(widget.onDecline!),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade400,
                          side: BorderSide(color: Colors.red.shade300),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text('Decline',
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            _acting ? null : () => _tap(widget.onAccept!),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NeedHubTokens.forest,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: _acting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text('Accept',
                                style: GoogleFonts.hankenGrotesk(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OfferDetailsSheet extends StatelessWidget {
  final String name;
  final String note;
  final String amount;
  final String? workSampleUrl;
  final List<_OfferRevisionData> revisions;
  final NeedHubTokens t;

  const _OfferDetailsSheet(
      {required this.name,
      required this.note,
      required this.amount,
      required this.workSampleUrl,
      required this.revisions,
      required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
          color: t.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(name,
                      style: GoogleFonts.bricolageGrotesque(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: t.ink))),
              Text(amount,
                  style: GoogleFonts.bricolageGrotesque(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: NeedHubTokens.ochre)),
            ]),
            const SizedBox(height: 8),
            Text(note,
                style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted)),
            if (workSampleUrl != null && workSampleUrl!.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('WORK SAMPLE',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: t.muted)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => NHFullScreenImageViewer.open(context,
                    imageUrl: workSampleUrl, title: '$name’s work sample'),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(workSampleUrl!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          height: 80,
                          color: t.rail,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined))),
                ),
              ),
            ],
            if (revisions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                      onPressed: () => showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          builder: (_) =>
                              _OfferHistorySheet(revisions: revisions, t: t)),
                      icon: const Icon(Icons.history_rounded, size: 17),
                      label: Text('View edit history (${revisions.length})'))),
            ],
          ]),
    );
  }
}

class _OfferHistorySheet extends StatelessWidget {
  final List<_OfferRevisionData> revisions;
  final NeedHubTokens t;
  const _OfferHistorySheet({required this.revisions, required this.t});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, MediaQuery.of(context).padding.bottom + 20),
        decoration: BoxDecoration(
            color: t.card,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Offer edit history',
                  style: GoogleFonts.bricolageGrotesque(
                      fontSize: 20, fontWeight: FontWeight.w800, color: t.ink)),
              const SizedBox(height: 10),
              ...revisions.map((r) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_rounded),
                  title: Text(r.amount,
                      style: GoogleFonts.hankenGrotesk(
                          fontWeight: FontWeight.w700)),
                  subtitle: Text(r.note),
                  trailing: r.workSampleUrl != null
                      ? const Icon(Icons.image_outlined)
                      : null)),
            ]),
      );
}

// ── Earn Offer sheet ──────────────────────────────────────────────────────────

class _EarnOfferSheet extends ConsumerStatefulWidget {
  final Need need;
  final NeedOffer? existingOffer;

  const _EarnOfferSheet({required this.need, this.existingOffer});

  @override
  ConsumerState<_EarnOfferSheet> createState() => _EarnOfferSheetState();
}

class _EarnOfferSheetState extends ConsumerState<_EarnOfferSheet> {
  final _rateController = TextEditingController();
  final _noteController = TextEditingController();
  String? _workSamplePath;
  bool _sent = false;
  bool _sending = false;
  bool _suggesting = false;
  bool _removeWorkSample = false;
  String? _submittedResponseId;
  String? _submittedWorkSampleUrl;

  @override
  void initState() {
    super.initState();
    if (widget.existingOffer != null) {
      final digits =
          widget.existingOffer!.amount.replaceAll(RegExp(r'[^\d]'), '');
      _rateController.text = digits;
      _noteController.text = widget.existingOffer!.note;
    }
  }

  @override
  void dispose() {
    _rateController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSend =>
      _rateController.text.trim().isNotEmpty &&
      _noteController.text.trim().length >= 5 &&
      !_sending &&
      !_suggesting;

  Future<void> _suggestIntro() async {
    setState(() => _suggesting = true);
    try {
      final api = ref.read(apiClientProvider);
      final res =
          await api.post('/needs/${widget.need.id}/suggest-response', {});
      final suggestion = res['suggestion'] as String? ?? '';
      if (suggestion.isNotEmpty && mounted) {
        _noteController.text = suggestion;
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not generate suggestion. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  Future<void> _submit() async {
    if (!_canSend) return;
    setState(() => _sending = true);
    final rateText = _rateController.text.trim();
    final noteText = _noteController.text.trim();
    final double price = double.tryParse(rateText) ?? 0;

    try {
      final api = ref.read(apiClientProvider);
      if (_workSamplePath != null) {
        final form = FormData.fromMap({
          'message': noteText,
          'quotedPrice': price,
          'removeWorkSample': false,
          'workSample': await MultipartFile.fromFile(
            _workSamplePath!,
            filename: _workSamplePath!.split('/').last,
          ),
        });
        if (widget.existingOffer?.responseId != null) {
          final result = await api.patchForm(
              '/needs/${widget.need.id}/responses/${widget.existingOffer!.responseId}/edit',
              form);
          _submittedWorkSampleUrl = (result['response']
              as Map<String, dynamic>?)?['workSampleUrl'] as String?;
        } else {
          final result =
              await api.postForm('/needs/${widget.need.id}/responses', form);
          _submittedResponseId =
              (result['response'] as Map<String, dynamic>?)?['id'] as String?;
          _submittedWorkSampleUrl = (result['response']
              as Map<String, dynamic>?)?['workSampleUrl'] as String?;
        }
      } else {
        final body = {
          'message': noteText,
          'quotedPrice': price,
          'removeWorkSample': _removeWorkSample,
        };
        if (widget.existingOffer?.responseId != null) {
          await api.patch(
              '/needs/${widget.need.id}/responses/${widget.existingOffer!.responseId}/edit',
              body);
        } else {
          final result =
              await api.post('/needs/${widget.need.id}/responses', body);
          _submittedResponseId =
              (result['response'] as Map<String, dynamic>?)?['id'] as String?;
        }
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      final code = (data is Map ? data['code'] : null) as String? ?? '';
      final status = e.response?.statusCode;
      if (mounted) {
        if (status == 422 ||
            code == 'MODERATION_HARD_BLOCK' ||
            code == 'MODERATION_BLOCKED') {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Message blocked'),
              content: const Text(
                  'Your message contains content that violates community guidelines. Please revise it.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK')),
              ],
            ),
          );
        } else if (status == 400 && code == 'SELF_RESPONSE') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("You can't apply to your own need.")),
          );
        } else if (status == 400 && code == 'RESPONSE_EDIT_WINDOW_EXPIRED') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Offers can only be edited for 10 minutes.')),
          );
        } else if (status == 404) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This need is no longer available.')),
          );
        } else if (status == 401) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Session expired. Please log in again.')),
          );
        } else {
          final msg = (data is Map ? data['error'] : null) as String?;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(msg != null
                    ? 'Error: $msg'
                    : 'Could not send offer (${status ?? 'network error'}). Please try again.')),
          );
        }
      }
      setState(() => _sending = false);
      return;
    }

    // Update local offers list so the offer displays immediately in the UI
    final offers = mockOffers.putIfAbsent(widget.need.id, () => []);
    final existingIdx =
        offers.indexWhere((o) => o.name == 'You' || o.initials == 'ME');
    final updatedOffer = NeedOffer(
      name: 'You',
      initials: 'ME',
      note: noteText,
      amount: '₹$rateText',
      color: NeedHubTokens.forest,
      responseId: widget.existingOffer?.responseId ?? _submittedResponseId,
      workSampleUrl: _submittedWorkSampleUrl ??
          (_removeWorkSample ? null : widget.existingOffer?.workSampleUrl),
      createdAt: widget.existingOffer?.createdAt ?? DateTime.now(),
    );

    if (existingIdx != -1) {
      offers[existingIdx] = updatedOffer;
    } else {
      offers.insert(0, updatedOffer);
    }
    offersNotifier.value++;

    if (mounted) {
      setState(() {
        _sent = true;
        _sending = false;
      });
    }
  }

  Future<void> _withdrawOffer() async {
    final responseId = widget.existingOffer?.responseId;
    if (responseId == null) {
      mockOffers[widget.need.id]?.removeWhere((o) => o.name == 'You' || o.initials == 'ME');
      offersNotifier.value++;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Application withdrawn.')),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw Application'),
        content: const Text('Are you sure you want to withdraw your application?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Withdraw', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ref.read(needsApiProvider).withdrawResponse(widget.need.id, responseId);
      mockOffers[widget.need.id]?.removeWhere((o) => o.name == 'You' || o.initials == 'ME');
      offersNotifier.value++;
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Application withdrawn successfully.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to withdraw application: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad + 20),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: _sent
          ? _OfferSentView(
              t: t,
              isEditing: widget.existingOffer != null,
            )
          : _OfferFormView(
              need: widget.need,
              t: t,
              rateController: _rateController,
              noteController: _noteController,
              workSamplePath: _workSamplePath,
              currentWorkSampleUrl: _removeWorkSample
                  ? null
                  : widget.existingOffer?.workSampleUrl,
              canSend: _canSend,
              sending: _sending,
              suggesting: _suggesting,
              isEditing: widget.existingOffer != null,
              onPickWorkSample: () async {
                final file = await ImagePicker().pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 80,
                );
                if (file != null && mounted) {
                  setState(() {
                    _workSamplePath = file.path;
                    _removeWorkSample = false;
                  });
                }
              },
              onRemoveWorkSample: widget.existingOffer?.workSampleUrl != null
                  ? () => setState(() {
                        _workSamplePath = null;
                        _removeWorkSample = true;
                      })
                  : null,
              onSend: _submit,
              onSuggest: _suggestIntro,
              onChanged: () => setState(() {}),
              onWithdraw: widget.existingOffer != null ? _withdrawOffer : null,
            ),
    );
  }
}

class _OfferFormView extends StatelessWidget {
  final Need need;
  final NeedHubTokens t;
  final TextEditingController rateController;
  final TextEditingController noteController;
  final String? workSamplePath;
  final String? currentWorkSampleUrl;
  final bool canSend;
  final bool sending;
  final bool suggesting;
  final bool isEditing;
  final VoidCallback onPickWorkSample;
  final VoidCallback? onRemoveWorkSample;
  final VoidCallback onSend;
  final VoidCallback onSuggest;
  final VoidCallback onChanged;
  final VoidCallback? onWithdraw;

  const _OfferFormView({
    required this.need,
    required this.t,
    required this.rateController,
    required this.noteController,
    required this.workSamplePath,
    this.currentWorkSampleUrl,
    required this.canSend,
    required this.sending,
    required this.suggesting,
    required this.isEditing,
    required this.onPickWorkSample,
    this.onRemoveWorkSample,
    required this.onSend,
    required this.onSuggest,
    required this.onChanged,
    this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    final hasCurrentSample =
        currentWorkSampleUrl != null &&
            currentWorkSampleUrl!.isNotEmpty &&
            workSamplePath == null;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: t.rail, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEditing ? 'Edit your offer' : 'Apply to help',
                      style: GoogleFonts.bricolageGrotesque(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: t.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      need.title,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 14, color: t.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: t.paper,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.rail, width: 1),
                  ),
                  child: Icon(Icons.close_rounded, size: 18, color: t.muted2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Subtle 10-Minute Info Notice
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFEAB308).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFEAB308).withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 14, color: Color(0xFFB45309)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Applications can be edited or withdrawn within 10 minutes of submitting.',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Rate
          Text('YOUR RATE (₹/hr)',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: t.muted2,
                  letterSpacing: 0.7)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: t.paper,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: t.rail, width: 1.5),
            ),
            child: TextField(
              controller: rateController,
              keyboardType: TextInputType.number,
              onChanged: (_) => onChanged(),
              style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
              decoration: InputDecoration(
                hintText: 'e.g. 500',
                hintStyle:
                    GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
                prefixIcon: Icon(Icons.currency_rupee_rounded,
                    size: 18, color: t.muted),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                filled: false,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Note
          Row(
            children: [
              Text('INTRO NOTE',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: t.muted2,
                      letterSpacing: 0.7)),
              const Spacer(),
              GestureDetector(
                onTap: suggesting ? null : onSuggest,
                child: Row(
                  children: [
                    if (suggesting)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.auto_awesome_rounded,
                          size: 14, color: NeedHubTokens.clay),
                    const SizedBox(width: 4),
                    Text(
                      'AI Suggest',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: NeedHubTokens.clay,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: t.paper,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: t.rail, width: 1.5),
            ),
            child: TextField(
              controller: noteController,
              maxLines: 4,
              onChanged: (_) => onChanged(),
              style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
              decoration: InputDecoration(
                hintText: 'Explain why you are a good fit for this task…',
                hintStyle:
                    GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
                filled: false,
              ),
            ),
          ),
          // Work sample label
          Text('WORK SAMPLE (OPTIONAL)',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: t.muted2,
                  letterSpacing: 0.7)),
          const SizedBox(height: 8),
          if (hasCurrentSample) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NeedHubTokens.ochre.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                    color: NeedHubTokens.ochre.withValues(alpha: 0.35),
                    width: 1.5),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      currentWorkSampleUrl!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 44,
                        height: 44,
                        color: t.rail,
                        child: Icon(Icons.image_outlined,
                            size: 20, color: t.muted),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Current work sample',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: t.ink),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onRemoveWorkSample,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Remove'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          GestureDetector(
            onTap: onPickWorkSample,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: workSamplePath != null
                    ? NeedHubTokens.ochre.withValues(alpha: 0.08)
                    : t.paper,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: workSamplePath != null ? NeedHubTokens.ochre : t.rail,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    workSamplePath != null
                        ? Icons.check_circle_rounded
                        : Icons.attach_file_rounded,
                    color:
                        workSamplePath != null ? NeedHubTokens.ochre : t.muted,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workSamplePath != null
                              ? 'Work sample added'
                              : 'Add work sample (optional)',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: workSamplePath != null
                                ? NeedHubTokens.ochre
                                : t.muted2,
                          ),
                        ),
                        Text(
                          'Portfolio, screenshot, or file',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 12, color: t.muted),
                        ),
                      ],
                    ),
                  ),
                  if (workSamplePath == null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: t.chip,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: t.rail),
                      ),
                      child: Text(
                        'Browse',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: t.muted2),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: canSend ? onSend : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: NeedHubTokens.ochre,
                foregroundColor: Colors.white,
                disabledBackgroundColor: t.rail,
                disabledForegroundColor: t.muted,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                textStyle: GoogleFonts.bricolageGrotesque(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
              child: sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(isEditing ? 'Update offer' : 'Send offer'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferSentView extends StatelessWidget {
  final NeedHubTokens t;
  final bool isEditing;

  const _OfferSentView({required this.t, this.isEditing = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: NeedHubTokens.ochre.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.check_rounded,
              color: NeedHubTokens.ochre, size: 30),
        ),
        const SizedBox(height: 16),
        Text(
          isEditing ? 'Offer updated!' : 'Offer sent!',
          style: GoogleFonts.bricolageGrotesque(
              fontSize: 22, fontWeight: FontWeight.w800, color: t.ink),
        ),
        const SizedBox(height: 6),
        Text(
          isEditing
              ? 'Your updated offer details have been saved.'
              : 'Chat unlocks when they accept your offer.',
          style: GoogleFonts.hankenGrotesk(
              fontSize: 14, color: t.muted, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Done',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

// ── Connect / Apply bottom sheet ───────────────────────────────────────────────

class _ConnectSheet extends ConsumerStatefulWidget {
  final Need need;
  final NeedOffer? existingOffer;
  final String actionLabel;
  final Color categoryColor;

  const _ConnectSheet({
    required this.need,
    this.existingOffer,
    required this.actionLabel,
    required this.categoryColor,
  });

  @override
  ConsumerState<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends ConsumerState<_ConnectSheet> {
  final _controller = TextEditingController();
  bool _sent = false;
  bool _sending = false;
  bool _suggesting = false;
  String? _submittedResponseId;

  @override
  void initState() {
    super.initState();
    final existingNote = widget.existingOffer?.note.trim();
    if (existingNote != null && existingNote.isNotEmpty) {
      _controller.text = existingNote;
    }
  }

  Future<void> _suggestIntro() async {
    setState(() => _suggesting = true);
    try {
      final api = ref.read(apiClientProvider);
      final res =
          await api.post('/needs/${widget.need.id}/suggest-response', {});
      final suggestion = res['suggestion'] as String? ?? '';
      if (suggestion.isNotEmpty && mounted) {
        _controller.text = suggestion;
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not generate suggestion. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad + 20),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: _sent
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: NeedHubTokens.forest.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: NeedHubTokens.forest, size: 28),
                ),
                const SizedBox(height: 14),
                Text(
                  'Message sent!',
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: t.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.need.authorName} will be notified.',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    color: t.muted,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Done',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.rail,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.actionLabel,
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: t.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Send a short intro to ${widget.need.authorName}',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 14, color: t.muted),
                      ),
                    ),
                    GestureDetector(
                      onTap: _suggesting ? null : _suggestIntro,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: NeedHubTokens.forest
                              .withValues(alpha: _suggesting ? 0.05 : 0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color:
                                  NeedHubTokens.forest.withValues(alpha: 0.3)),
                        ),
                        child: _suggesting
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: NeedHubTokens.forest,
                                ),
                              )
                            : Text(
                                '✦ Suggest intro',
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: NeedHubTokens.forest,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Subtle 10-Minute Info Notice
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAB308).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFEAB308).withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 14, color: Color(0xFFB45309)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Applications can be edited or withdrawn within 10 minutes of submitting.',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: t.paper,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: t.rail, width: 1.5),
                  ),
                  child: TextField(
                    controller: _controller,
                    minLines: 3,
                    maxLines: 5,
                    style:
                        GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
                    decoration: InputDecoration(
                      hintText: 'Introduce yourself…',
                      hintStyle: GoogleFonts.hankenGrotesk(
                        fontSize: 14,
                        color: t.muted,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(14),
                      filled: false,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _sending
                        ? null
                        : () async {
                            final msg = _controller.text.trim();
                            if (msg.isEmpty) return;
                            setState(() => _sending = true);
                            try {
                              final api = ref.read(apiClientProvider);
                              final res =
                                  widget.existingOffer?.responseId != null
                                      ? await api.patch(
                                          '/needs/${widget.need.id}/responses/${widget.existingOffer!.responseId}/edit',
                                          {'message': msg},
                                        )
                                      : await api.post(
                                          '/needs/${widget.need.id}/responses',
                                          {'message': msg},
                                        );
                              final response =
                                  res['response'] as Map<String, dynamic>?;
                              _submittedResponseId =
                                  response?['id'] as String? ??
                                      widget.existingOffer?.responseId;
                            } on DioException catch (e) {
                              if (!mounted) return;
                              final data = e.response?.data;
                              final code = (data is Map ? data['code'] : null)
                                      as String? ??
                                  '';
                              final status = e.response?.statusCode;
                              setState(() => _sending = false);
                              if (status == 422 ||
                                  code == 'MODERATION_HARD_BLOCK' ||
                                  code == 'MODERATION_BLOCKED') {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Message blocked'),
                                    content: const Text(
                                        'Your message contains content that violates community guidelines. Please revise it.'),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('OK')),
                                    ],
                                  ),
                                );
                              } else if (status == 400 &&
                                  code == 'SELF_RESPONSE') {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          "You can't apply to your own need.")),
                                );
                              } else if (status == 400 &&
                                  code == 'RESPONSE_EDIT_WINDOW_EXPIRED') {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Applications can only be edited for 10 minutes.')),
                                );
                              } else if (status == 404) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'This need is no longer available.')),
                                );
                              } else if (status == 401) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Session expired. Please log in again.')),
                                );
                              } else {
                                final msg = (data is Map ? data['error'] : null)
                                    as String?;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(msg != null
                                          ? 'Error: $msg'
                                          : 'Could not send message (${status ?? 'network error'}). Please try again.')),
                                );
                              }
                              return;
                            }

                            // Update local state optimistically after confirmed API success
                            final offers = mockOffers.putIfAbsent(
                                widget.need.id, () => []);
                            final existingIdx = offers.indexWhere(
                                (o) => o.name == 'You' || o.initials == 'ME');
                            final updatedOffer = NeedOffer(
                              name: 'You',
                              initials: 'ME',
                              note: msg,
                              amount: '—',
                              color: widget.categoryColor,
                              responseId: widget.existingOffer?.responseId ??
                                  _submittedResponseId,
                              workSampleUrl:
                                  widget.existingOffer?.workSampleUrl,
                              createdAt:
                                  widget.existingOffer?.createdAt ?? DateTime.now(),
                            );
                            if (existingIdx != -1) {
                              offers[existingIdx] = updatedOffer;
                            } else {
                              offers.insert(0, updatedOffer);
                            }
                            offersNotifier.value++;
                            if (mounted) setState(() => _sent = true);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.categoryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: GoogleFonts.bricolageGrotesque(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(widget.existingOffer != null ? 'Update message' : 'Send message'),
                  ),
                ),
                if (widget.existingOffer != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                      label: Text(
                        'Withdraw Application',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.red,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () async {
                        final respId = widget.existingOffer?.responseId;
                        if (respId == null) {
                          mockOffers[widget.need.id]?.removeWhere((o) => o.name == 'You' || o.initials == 'ME');
                          offersNotifier.value++;
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Application withdrawn.')),
                          );
                          return;
                        }
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Withdraw Application'),
                            content: const Text('Are you sure you want to withdraw your application?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Withdraw', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (confirm != true) return;

                        try {
                          await ref.read(needsApiProvider).withdrawResponse(widget.need.id, respId);
                          mockOffers[widget.need.id]?.removeWhere((o) => o.name == 'You' || o.initials == 'ME');
                          offersNotifier.value++;
                          if (!mounted) return;
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Application withdrawn successfully.')),
                          );
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to withdraw application: $e')),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _OfferSortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final NeedHubTokens t;

  const _OfferSortChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? NeedHubTokens.clay.withValues(alpha: 0.14) : t.card,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? NeedHubTokens.clay : t.rail,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.hankenGrotesk(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? NeedHubTokens.clay : t.muted,
          ),
        ),
      ),
    );
  }
}

/// Circular avatar that renders initials on a solid tinted background.
/// Used as fallback when a network profile picture is unavailable.
class _InitialsAvatar extends StatelessWidget {
  final String initials;
  final Color tint;
  final Color textColor;
  final double size;

  const _InitialsAvatar({
    required this.initials,
    required this.tint,
    this.textColor = Colors.white,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.hankenGrotesk(
          fontSize: size * 0.35,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }
}

class _FeedbackSheet extends StatefulWidget {
  final String needId;
  final String revieweeId;
  final String revieweeName;
  final VoidCallback onSubmitted;

  const _FeedbackSheet({
    required this.needId,
    required this.revieweeId,
    required this.revieweeName,
    required this.onSubmitted,
  });

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  int _rating = 5;
  final _commentController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            24,
      ),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: t.rail,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Rate & Give Feedback',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: t.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'How was your experience with ${widget.revieweeName}?',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 13.5,
              color: t.muted,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final star = index + 1;
              return IconButton(
                onPressed: () => setState(() => _rating = star),
                icon: Icon(
                  star <= _rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: star <= _rating ? const Color(0xFFEAB308) : t.muted,
                  size: 36,
                ),
              );
            }),
          ),
          Center(
            child: Text(
              '$_rating Star${_rating == 1 ? '' : 's'}',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _commentController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Write feedback (visible only to both of you)…',
              hintStyle:
                  GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted),
              filled: true,
              fillColor: t.paper,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.rail),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style:
                    GoogleFonts.hankenGrotesk(fontSize: 12, color: Colors.red)),
          ],
          const SizedBox(height: 20),
          Consumer(
            builder: (context, ref, _) => SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _submitting
                    ? null
                    : () async {
                        setState(() {
                          _submitting = true;
                          _error = null;
                        });
                        try {
                          final api = ref.read(reviewsApiProvider);
                          final pts = await api.submit(
                            needId: widget.needId,
                            revieweeId: widget.revieweeId,
                            rating: _rating,
                            comment: _commentController.text.trim(),
                          );
                          if (!mounted) return;
                          Navigator.of(context).pop();
                          widget.onSubmitted();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Feedback submitted! ${pts > 0 ? "+$pts points awarded!" : ""}')),
                          );
                        } catch (e) {
                          if (mounted) {
                            setState(() {
                              _error = 'Failed to submit feedback: $e';
                              _submitting = false;
                            });
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: NeedHubTokens.forest,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _submitting
                    ? const CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)
                    : Text('Submit Feedback & Rating',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditNeedSheet extends StatefulWidget {
  final Need need;
  final VoidCallback onUpdated;

  const _EditNeedSheet({required this.need, required this.onUpdated});

  @override
  State<_EditNeedSheet> createState() => _EditNeedSheetState();
}

class _EditNeedSheetState extends State<_EditNeedSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late final TextEditingController _budgetMinController;
  late final TextEditingController _budgetMaxController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.need.title);
    _descController = TextEditingController(text: widget.need.description);
    _budgetMinController = TextEditingController(
        text: widget.need.budgetMin != null ? '${widget.need.budgetMin}' : '');
    _budgetMaxController = TextEditingController(
        text: widget.need.budgetMax != null ? '${widget.need.budgetMax}' : '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _budgetMinController.dispose();
    _budgetMaxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            24,
      ),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.rail,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Edit Need',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: t.ink,
              ),
            ),
            const SizedBox(height: 16),
            Text('TITLE',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 11, fontWeight: FontWeight.w700, color: t.muted2)),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                filled: true,
                fillColor: t.paper,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            Text('DESCRIPTION',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 11, fontWeight: FontWeight.w700, color: t.muted2)),
            const SizedBox(height: 6),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: InputDecoration(
                filled: true,
                fillColor: t.paper,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MIN BUDGET (₹)',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: t.muted2)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _budgetMinController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: t.paper,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MAX BUDGET (₹)',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: t.muted2)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _budgetMaxController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: t.paper,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 12, color: Colors.red)),
            ],
            const SizedBox(height: 20),
            Consumer(
              builder: (context, ref, _) => SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          setState(() {
                            _saving = true;
                            _error = null;
                          });
                          if (widget.need.id.startsWith('posted_')) {
                            setState(() {
                              _error = 'This need was not saved to the server. Please delete it and repost.';
                              _saving = false;
                            });
                            return;
                          }
                          try {
                            final api = ref.read(needsApiProvider);
                            await api.updateNeed(
                              widget.need.id,
                              title: _titleController.text.trim(),
                              description: _descController.text.trim(),
                              budgetMin:
                                  int.tryParse(_budgetMinController.text.trim()),
                              budgetMax:
                                  int.tryParse(_budgetMaxController.text.trim()),
                            );
                            if (!mounted) return;
                            Navigator.of(context).pop();
                            widget.onUpdated();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Need updated successfully!')),
                            );
                          } catch (e) {
                            if (mounted) {
                              setState(() {
                                _error = 'Failed to update need: $e';
                                _saving = false;
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NeedHubTokens.forest,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)
                      : Text('Save Changes',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
