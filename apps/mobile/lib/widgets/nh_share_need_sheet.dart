import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/need.dart';
import '../services/api_client.dart';
import '../theme/tokens.dart';
import 'nh_shareable_need_card.dart';

/// Share sheet for a Need — the entry point for Smart Shareable Need Cards.
///
/// Shows the exact card that will be shared, then hands off to the chosen
/// platform. Text-based targets (WhatsApp, Telegram, X) get the link, which
/// the API renders as a rich preview with an "Open in NeedHub / Install"
/// CTA; image-first targets (Instagram) and "More" get the rendered card PNG
/// alongside the link.
///
/// Only Needs that are still open are shareable — the caller decides via
/// [canShareNeed], and the API independently enforces the same rule so a
/// stale client cannot leak a closed Need.
class NhShareNeedSheet extends StatefulWidget {
  final Need need;

  const NhShareNeedSheet({super.key, required this.need});

  static Future<void> open(BuildContext context, {required Need need}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NhShareNeedSheet(need: need),
    );
  }

  @override
  State<NhShareNeedSheet> createState() => _NhShareNeedSheetState();
}

/// A Need is shareable only while it is still open to the public. Mirrors
/// isShareable() in the API's lib/share-card.ts — kept in sync deliberately
/// so the button never appears for something the server would refuse.
bool canShareNeed(Need need) {
  final status = need.status.toUpperCase();
  if (status != 'OPEN' && status != 'IN_PROGRESS') return false;
  final deadline = need.deadline;
  if (need.isUrgent && deadline != null && !deadline.isAfter(DateTime.now())) {
    return false;
  }
  return true;
}

class _NhShareNeedSheetState extends State<NhShareNeedSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _busy = false;

  String get _shareUrl => '$apiBaseUrl/n/${widget.need.id}';

  String get _shareText {
    final n = widget.need;
    final parts = <String>[n.title];
    if (n.location.trim().isNotEmpty) parts.add('📍 ${n.location}');
    return '${parts.join('\n')}\n\nFound this on NeedHub — open it here:\n$_shareUrl';
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Could not share: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens a platform's share URL, falling back to copying the link so the
  /// user is never left with a button that silently does nothing.
  Future<void> _launchOrCopy(String url, String platformName) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    await Clipboard.setData(ClipboardData(text: _shareText));
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('$platformName isn\'t installed — link copied instead'),
        ));
    }
  }

  Future<void> _shareWhatsApp() => _run(() => _launchOrCopy(
        'https://api.whatsapp.com/send?text=${Uri.encodeComponent(_shareText)}',
        'WhatsApp',
      ));

  Future<void> _shareTelegram() => _run(() => _launchOrCopy(
        'https://t.me/share/url?url=${Uri.encodeComponent(_shareUrl)}'
        '&text=${Uri.encodeComponent(widget.need.title)}',
        'Telegram',
      ));

  Future<void> _shareX() => _run(() => _launchOrCopy(
        'https://twitter.com/intent/tweet?text=${Uri.encodeComponent(widget.need.title)}'
        '&url=${Uri.encodeComponent(_shareUrl)}',
        'X',
      ));

  /// Instagram has no public text-share URL, so the card image goes through
  /// the system sheet — which is where Instagram's Stories/Feed targets live.
  Future<void> _shareInstagram() => _run(() => _shareImage(
        fallbackMessage: 'Pick Instagram from the share menu',
      ));

  Future<void> _shareMore() => _run(() => _shareImage());

  Future<void> _shareImage({String? fallbackMessage}) async {
    final Uint8List? png = await renderShareCardPng(_cardKey);

    if (png == null) {
      // Rendering failed — still share something useful rather than nothing.
      await SharePlus.instance.share(
        ShareParams(text: _shareText, subject: widget.need.title),
      );
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        text: _shareText,
        subject: widget.need.title,
        files: [
          XFile.fromData(
            png,
            mimeType: 'image/png',
            name: 'needhub-${widget.need.id}.png',
          ),
        ],
      ),
    );

    if (fallbackMessage != null && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(fallbackMessage)));
    }
  }

  Future<void> _copyLink() => _run(() async {
        await Clipboard.setData(ClipboardData(text: _shareUrl));
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('Link copied')));
        }
      });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: t.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
              'Share this need',
              style: GoogleFonts.bricolageGrotesque(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: t.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Anyone who opens the link can view it — no account needed.',
              style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted),
            ),
            const SizedBox(height: 18),

            // The card preview *is* the shared artwork — RepaintBoundary lets
            // it be rasterised exactly as shown.
            Center(
              child: RepaintBoundary(
                key: _cardKey,
                child: NhShareableNeedCard(
                  need: widget.need,
                  shareUrl: _shareUrl,
                ),
              ),
            ),
            const SizedBox(height: 22),

            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _ShareTarget(
                  icon: Icons.chat_bubble_rounded,
                  label: 'WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: _shareWhatsApp,
                  t: t,
                ),
                _ShareTarget(
                  icon: Icons.photo_camera_rounded,
                  label: 'Instagram',
                  color: const Color(0xFFE1306C),
                  onTap: _shareInstagram,
                  t: t,
                ),
                _ShareTarget(
                  icon: Icons.send_rounded,
                  label: 'Telegram',
                  color: const Color(0xFF229ED9),
                  onTap: _shareTelegram,
                  t: t,
                ),
                _ShareTarget(
                  icon: Icons.close_rounded,
                  label: 'X',
                  color: t.ink,
                  onTap: _shareX,
                  t: t,
                ),
              ],
            ),
            const SizedBox(height: 18),

            OutlinedButton.icon(
              onPressed: _busy ? null : _copyLink,
              icon: const Icon(Icons.link_rounded, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: t.ink,
                minimumSize: const Size.fromHeight(46),
                side: BorderSide(color: t.rail, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              label: Text(
                'Copy link',
                style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _shareMore,
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              style: FilledButton.styleFrom(
                backgroundColor: t.ink,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              label: Text(
                'More options',
                style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareTarget extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final NeedHubTokens t;

  const _ShareTarget({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: GoogleFonts.hankenGrotesk(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
        ],
      ),
    );
  }
}
