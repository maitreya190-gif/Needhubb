import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/need.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';
import 'need_detail_screen.dart';

/// Landing point for a shared Need link (`needhub:///need/<id>`).
///
/// A deep link only carries the id, so the Need has to be fetched before the
/// normal detail screen can be shown. This exists purely to do that fetch and
/// then hand off — it deliberately does not reimplement any of the detail UI.
class NeedDeepLinkScreen extends ConsumerStatefulWidget {
  final String needId;

  const NeedDeepLinkScreen({super.key, required this.needId});

  @override
  ConsumerState<NeedDeepLinkScreen> createState() => _NeedDeepLinkScreenState();
}

class _NeedDeepLinkScreenState extends ConsumerState<NeedDeepLinkScreen> {
  Need? _need;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final need = await ref.read(needsApiProvider).getById(widget.needId);
      if (!mounted) return;
      setState(() {
        _need = need;
        _loading = false;
      });
    } catch (_) {
      // Completed, closed, deleted, or simply unreachable — all of which look
      // the same to the recipient, so they get one honest message either way.
      if (mounted) setState(() { _loading = false; _failed = true; });
    }
  }

  void _goHome() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/hub');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    if (_loading) {
      return Scaffold(
        backgroundColor: t.paper,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_failed || _need == null) {
      return Scaffold(
        backgroundColor: t.paper,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.link_off_rounded, size: 44, color: t.muted2),
                  const SizedBox(height: 14),
                  Text(
                    'This need isn\'t available',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'It may have been completed, closed, or expired.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.hankenGrotesk(fontSize: 13.5, color: t.muted),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _goHome,
                    style: FilledButton.styleFrom(backgroundColor: t.ink),
                    child: Text(
                      'Browse needs',
                      style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return NeedDetailScreen(need: _need!);
  }
}
