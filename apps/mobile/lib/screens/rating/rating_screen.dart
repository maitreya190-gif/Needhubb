import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_strings.dart';
import '../../models/user_state.dart';
import '../../services/reviews_api.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';

class RatingScreen extends ConsumerStatefulWidget {
  final String personName;
  final String personInitials;
  final String taskLabel;
  final String? needTitle;
  // Real IDs — when provided, submission hits the API.
  final String? needId;
  final String? revieweeId;

  const RatingScreen({
    super.key,
    required this.personName,
    required this.personInitials,
    required this.taskLabel,
    this.needTitle,
    this.needId,
    this.revieweeId,
  });

  @override
  ConsumerState<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends ConsumerState<RatingScreen> {
  int _stars = 0;
  final _controller = TextEditingController();
  bool _submitted = false;
  bool _submitting = false;
  int _pointsAwarded = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0 || _submitting) return;
    setState(() => _submitting = true);
    // Legacy in-memory ratings map — keeps compat with mock screens.
    submitRating(widget.personName, _stars);
    try {
      if (widget.needId != null && widget.revieweeId != null) {
        final pts = await ref.read(reviewsApiProvider).submit(
              needId: widget.needId!,
              revieweeId: widget.revieweeId!,
              rating: _stars,
              comment: _controller.text.trim().isEmpty
                  ? null
                  : _controller.text.trim(),
            );
        _pointsAwarded = pts;
        // Drop this pending review from the notifier.
        pendingReviewsNotifier.value = pendingReviewsNotifier.value
            .where((p) => p.needId != widget.needId)
            .toList();
      }
      if (mounted) setState(() {
        _submitted = true;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${S.current.error}: $e'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        backgroundColor: t.paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      resizeToAvoidBottomInset: true,
      body: _submitted
          ? _SuccessView(t: t, pointsAwarded: _pointsAwarded, onDone: () => Navigator.of(context).pop())
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, MediaQuery.of(context).padding.bottom + 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Eyebrow
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: NeedHubTokens.clay.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      S.current.taskComplete,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: NeedHubTokens.clay,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Text(
                    'How did it go with\n${widget.personName}?',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: t.ink,
                      height: 1.15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.current.ratingHelpsTrust,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 14, color: t.muted, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Avatar
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: NeedHubTokens.forest.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      widget.personInitials,
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: NeedHubTokens.forest,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.taskLabel,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 13, color: t.muted),
                  ),
                  const SizedBox(height: 28),

                  // Stars
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final selected = i < _stars;
                      return GestureDetector(
                        onTap: () => setState(() => _stars = i + 1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: AnimatedScale(
                            scale: selected ? 1.2 : 1.0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.elasticOut,
                            child: Icon(
                              selected
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 42,
                              color: selected ? NeedHubTokens.ochre : t.rail,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _stars == 0 ? S.current.tapAStarToRate : _starLabel(_stars),
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 13,
                      color: _stars == 0 ? t.muted : NeedHubTokens.ochre,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Note label
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      S.current.quickNoteOptional,
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: t.muted2,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: t.rail, width: 1.5),
                    ),
                    child: TextField(
                      controller: _controller,
                      minLines: 3,
                      maxLines: 5,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 14, color: t.ink),
                      decoration: InputDecoration(
                        hintText: S.current.ratingNoteHint,
                        hintStyle: GoogleFonts.hankenGrotesk(
                            fontSize: 14, color: t.muted),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(14),
                        filled: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (_stars > 0 && !_submitting) ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NeedHubTokens.forest,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: t.rail,
                        disabledForegroundColor: t.muted,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        textStyle: GoogleFonts.bricolageGrotesque(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: Colors.white))
                          : Text(S.current.submitRating),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _starLabel(int stars) {
    switch (stars) {
      case 1:
        return S.current.notGreat;
      case 2:
        return S.current.itWasOkay;
      case 3:
        return S.current.prettyGood;
      case 4:
        return S.current.reallyHelpful;
      case 5:
        return S.current.absolutelyBrilliant;
      default:
        return '';
    }
  }
}

class _SuccessView extends StatelessWidget {
  final NeedHubTokens t;
  final int pointsAwarded;
  final VoidCallback onDone;

  const _SuccessView({
    required this.t,
    required this.pointsAwarded,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: NeedHubTokens.forest.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.check_rounded,
                  color: NeedHubTokens.forest, size: 32),
            ),
            const SizedBox(height: 16),
            Text(S.current.thanksForReview,
                style: GoogleFonts.bricolageGrotesque(
                    fontSize: 22, fontWeight: FontWeight.w800, color: t.ink),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(S.current.feedbackBuildsTrust,
                style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
                textAlign: TextAlign.center),
            if (pointsAwarded > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: NeedHubTokens.clay.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${S.current.theyEarned} +$pointsAwarded ${S.current.points}',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: NeedHubTokens.clay)),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: onDone,
                child: Text(S.current.done,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
