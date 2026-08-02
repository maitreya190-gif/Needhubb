import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/social_providers.dart';
import '../theme/tokens.dart';

/// Create, edit or withdraw a vouch for one skill.
///
/// The AI's role (requirement 3) ends before this sheet ever opens: a
/// suggestion just decides which skill this sheet opens for. Submitting is
/// always an explicit, separate tap — nothing here or upstream ever creates
/// a vouch without it.
class NhVouchSheet extends ConsumerStatefulWidget {
  final String voucheeId;
  final String voucheeName;
  final String skillId;
  final String skillLabel;

  /// Present when editing an existing vouch — enables the testimonial
  /// pre-fill and the Withdraw action.
  final String? existingVouchId;
  final String? existingTestimonial;

  const NhVouchSheet({
    super.key,
    required this.voucheeId,
    required this.voucheeName,
    required this.skillId,
    required this.skillLabel,
    this.existingVouchId,
    this.existingTestimonial,
  });

  static Future<bool?> open(
    BuildContext context, {
    required String voucheeId,
    required String voucheeName,
    required String skillId,
    required String skillLabel,
    String? existingVouchId,
    String? existingTestimonial,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NhVouchSheet(
        voucheeId: voucheeId,
        voucheeName: voucheeName,
        skillId: skillId,
        skillLabel: skillLabel,
        existingVouchId: existingVouchId,
        existingTestimonial: existingTestimonial,
      ),
    );
  }

  @override
  ConsumerState<NhVouchSheet> createState() => _NhVouchSheetState();
}

class _NhVouchSheetState extends ConsumerState<NhVouchSheet> {
  late final _testimonialController =
      TextEditingController(text: widget.existingTestimonial ?? '');
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existingVouchId != null;

  @override
  void dispose() {
    _testimonialController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _submitting = true; _error = null; });
    try {
      final api = ref.read(vouchesApiProvider);
      if (_isEdit) {
        await api.edit(widget.existingVouchId!,
            testimonial: _testimonialController.text);
      } else {
        await api.create(
          voucheeId: widget.voucheeId,
          skillId: widget.skillId,
          testimonial: _testimonialController.text,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _isEdit
            ? 'Could not save your changes. Please try again.'
            : 'Could not submit your vouch. Please try again.';
      });
    }
  }

  Future<void> _withdraw() async {
    setState(() { _submitting = true; _error = null; });
    try {
      await ref.read(vouchesApiProvider).withdraw(widget.existingVouchId!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not withdraw right now. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: t.rail, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _isEdit ? 'Edit your vouch' : 'Vouch for a skill',
              style: GoogleFonts.bricolageGrotesque(
                  fontSize: 19, fontWeight: FontWeight.w800, color: t.ink),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.voucheeName} — ${widget.skillLabel}',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: t.muted2),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  _error!,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 12.5, color: Colors.orange.shade800),
                ),
              ),
            ],
            Text(
              'TESTIMONIAL (OPTIONAL)',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.muted2,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _testimonialController,
              maxLines: 3,
              maxLength: 500,
              style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
              decoration: InputDecoration(
                hintText: 'What was it like working with them?',
                hintStyle:
                    GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted),
                filled: true,
                fillColor: t.paper,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: t.rail),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_isEdit) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting ? null : _withdraw,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade600,
                        side: BorderSide(color: Colors.red.shade200),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Withdraw'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: _isEdit ? 1 : 2,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NeedHubTokens.forest,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: GoogleFonts.hankenGrotesk(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isEdit ? 'Save' : 'Submit Vouch'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
