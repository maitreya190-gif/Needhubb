import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_strings.dart';
import '../../theme/tokens.dart';

const String _kTutorialPendingKey = 'nh_tutorial_pending';

/// Queued at the end of signup so the tour runs for brand-new accounts only.
/// Users who were already signed in never get the flag, so they never see it.
Future<void> markTutorialPending() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kTutorialPendingKey, true);
}

/// True exactly once, for a new account. Clears the flag as it reads it so a
/// crash mid-tour can't trap the user in a loop.
Future<bool> consumeTutorialPending() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kTutorialPendingKey) != true) return false;
  await prefs.remove(_kTutorialPendingKey);
  return true;
}

/// One stop on the tour: which tab to open, what to punch a hole around, and
/// the copy to show beside it. A null [target] means "no spotlight" — used for
/// the opening card, which floats centred over a plain dim.
class TourStep {
  final int tab;
  final GlobalKey? target;
  final String title;
  final String body;
  final List<String> chips;
  final double radius;

  const TourStep({
    required this.tab,
    required this.title,
    required this.body,
    this.chips = const [],
    this.target,
    this.radius = 18,
  });
}

class TutorialOverlay extends StatefulWidget {
  final List<TourStep> steps;

  /// Switches the host's visible tab. Called before each step is measured.
  final ValueChanged<int> onGoToTab;
  final VoidCallback onFinish;

  const TutorialOverlay({
    super.key,
    required this.steps,
    required this.onGoToTab,
    required this.onFinish,
  });

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with TickerProviderStateMixin {
  int _step = 0;
  Rect? _rect;

  late final AnimationController _move;
  late final AnimationController _pulse;
  Rect? _from;

  @override
  void initState() {
    super.initState();
    _move = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyStep(0));
  }

  @override
  void dispose() {
    _move.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// Opens the step's tab, then measures its target once layout has settled.
  /// Two frames: one for the tab switch to build, one for it to lay out.
  Future<void> _applyStep(int i) async {
    widget.onGoToTab(widget.steps[i].tab);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final next = _measure(widget.steps[i].target);
    setState(() {
      _from = _rect;
      _rect = next;
    });
    _move.forward(from: 0);
  }

  Rect? _measure(GlobalKey? key) {
    final ctx = key?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _next() {
    if (_step >= widget.steps.length - 1) {
      widget.onFinish();
      return;
    }
    setState(() => _step++);
    _applyStep(_step);
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_step];
    final isLast = _step == widget.steps.length - 1;
    final media = MediaQuery.of(context);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Dim + spotlight. Tapping anywhere advances, so the tour never
          // feels like it's trapping you behind a tiny button.
          Positioned.fill(
            child: GestureDetector(
              onTap: _next,
              child: AnimatedBuilder(
                animation: Listenable.merge([_move, _pulse]),
                builder: (_, __) {
                  final t = Curves.easeOutCubic.transform(_move.value);
                  final hole = _rect == null
                      ? null
                      : (_from == null ? _rect : Rect.lerp(_from, _rect, t));
                  return CustomPaint(
                    painter: _SpotlightPainter(
                      hole: hole == null ? null : _inflate(hole, 8),
                      radius: step.radius,
                      glow: _pulse.value,
                    ),
                  );
                },
              ),
            ),
          ),

          // Copy card, placed on whichever side of the spotlight has room.
          AnimatedBuilder(
            animation: _move,
            builder: (context, child) {
              final t = Curves.easeOutCubic.transform(_move.value);
              final hole = _rect == null
                  ? null
                  : (_from == null ? _rect : Rect.lerp(_from, _rect, t));
              return _positionCard(
                media: media,
                hole: hole,
                child: Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - t)),
                    child: child,
                  ),
                ),
              );
            },
            child: _TourCard(
              step: step,
              index: _step,
              total: widget.steps.length,
              isLast: isLast,
              onNext: _next,
              onSkip: widget.onFinish,
            ),
          ),
        ],
      ),
    );
  }

  Rect _inflate(Rect r, double by) => Rect.fromLTRB(
        r.left - by,
        r.top - by,
        r.right + by,
        r.bottom + by,
      );

  Widget _positionCard({
    required MediaQueryData media,
    required Rect? hole,
    required Widget child,
  }) {
    const margin = 18.0;
    if (hole == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: margin),
          child: child,
        ),
      );
    }
    // Spotlight low on screen (nav bar, FAB) → card sits above it.
    final below = hole.center.dy < media.size.height * 0.5;
    return Positioned(
      left: margin,
      right: margin,
      top: below ? hole.bottom + 18 : null,
      bottom: below ? null : media.size.height - hole.top + 18,
      child: child,
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? hole;
  final double radius;
  final double glow;

  _SpotlightPainter({
    required this.hole,
    required this.radius,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final dim = Paint()..color = const Color(0xFF14100B).withValues(alpha: 0.82);

    if (hole == null) {
      canvas.drawRect(full, dim);
      return;
    }

    final rrect = RRect.fromRectAndRadius(hole!, Radius.circular(radius));

    canvas.saveLayer(full, Paint());
    canvas.drawRect(full, dim);
    canvas.drawRRect(rrect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    // Pulsing ring — the "this one" cue.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = NeedHubTokens.clay.withValues(alpha: 0.55 + 0.45 * glow),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          hole!.left - 5 * glow,
          hole!.top - 5 * glow,
          hole!.right + 5 * glow,
          hole!.bottom + 5 * glow,
        ),
        Radius.circular(radius + 5 * glow),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = NeedHubTokens.clay.withValues(alpha: 0.30 * (1 - glow)),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.glow != glow || old.radius != radius;
}

class _TourCard extends StatelessWidget {
  final TourStep step;
  final int index;
  final int total;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _TourCard({
    required this.step,
    required this.index,
    required this.total,
    required this.isLast,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = S.current;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 30,
            offset: Offset(0, 12),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.title,
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: t.ink,
              letterSpacing: -0.4,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            step.body,
            style: GoogleFonts.hankenGrotesk(
              fontSize: 14,
              height: 1.42,
              color: t.muted2,
            ),
          ),
          if (step.chips.isNotEmpty) ...[
            const SizedBox(height: 13),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final c in step.chips)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: NeedHubTokens.clay.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      c,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: NeedHubTokens.clay,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              // Progress dots. Expanded + Wrap so a long CTA label or a
              // wordy translation can never push this row into an overflow.
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: List.generate(total, (i) {
                    final active = i == index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      height: 5,
                      width: active ? 16 : 5,
                      decoration: BoxDecoration(
                        color: active ? NeedHubTokens.clay : t.rail2,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
              if (!isLast)
                GestureDetector(
                  onTap: onSkip,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    child: Text(
                      s.tutSkip,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.muted,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Flexible(
                child: GestureDetector(
                  onTap: onNext,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: NeedHubTokens.clay,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isLast ? '${s.startExploring} →' : s.next,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
