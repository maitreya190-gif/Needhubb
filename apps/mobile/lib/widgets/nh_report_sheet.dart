import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_state.dart';
import '../services/api_client.dart';
import '../services/social_providers.dart';
import '../theme/tokens.dart';

class NhReportSheet extends ConsumerStatefulWidget {
  final String targetName;
  /// One of 'USER', 'NEED', 'MESSAGE'. When null (legacy callers), the sheet
  /// still shows the UI but the submit does not hit the API — it just marks
  /// as submitted locally. New callers should always pass targetType + targetId.
  final String? targetType;
  final String? targetId;
  // Optional thread ID — when reporting from a conversation, this allows
  // the admin panel to display the last 20 messages as context.
  final String? threadId;
  final bool alsoBlock;

  const NhReportSheet({
    super.key,
    required this.targetName,
    this.targetType,
    this.targetId,
    this.threadId,
    this.alsoBlock = false,
  });

  static Future<void> open(
    BuildContext context, {
    required String targetName,
    String? targetType,
    String? targetId,
    String? threadId,
    bool alsoBlock = false,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NhReportSheet(
        targetName: targetName,
        targetType: targetType,
        targetId: targetId,
        threadId: threadId,
        alsoBlock: alsoBlock,
      ),
    );
  }

  @override
  ConsumerState<NhReportSheet> createState() => _NhReportSheetState();
}

class _NhReportSheetState extends ConsumerState<NhReportSheet> {
  static const _reasons = [
    'Inappropriate content or behaviour',
    'Fake or misleading profile',
    'Harassment or hate speech',
    'Spam or scam',
    'Underage user',
    'Something else',
  ];

  String? _selected;
  final _detailsController = TextEditingController();
  bool _submitted = false;
  bool _submitting = false;
  String? _errorMsg;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _selected != null && _detailsController.text.trim().length >= 10;

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    setState(() {
      _submitting = true;
      _errorMsg = null;
    });

    final reason = '${_selected!} — ${_detailsController.text.trim()}';

    try {
      // Fire the report to the backend when the caller gave us targetType/Id.
      if (widget.targetType != null && widget.targetId != null) {
        final api = ref.read(apiClientProvider);
        await api.post('/reports', {
          'targetType': widget.targetType,
          'targetId': widget.targetId,
          'reason': reason,
          if (widget.threadId != null) 'threadId': widget.threadId,
        });
      }

      // Fire the block in parallel when requested.
      if (widget.alsoBlock) {
        if (widget.targetType == 'USER' && widget.targetId != null) {
          try {
            await ref.read(friendsApiProvider).block(widget.targetId!);
            blockedUserIdsNotifier.value = {
              ...blockedUserIdsNotifier.value,
              widget.targetId!,
            };
          } catch (_) {/* silent — block feedback still shows */}
        }
        // Legacy name-only notifier so any name-driven UIs also react.
        blockUser(widget.targetName);
      }

      if (mounted) setState(() => _submitted = true);
    } on DioException catch (e) {
      final code = e.response?.data is Map
          ? (e.response!.data as Map)['code']?.toString()
          : null;
      String msg;
      if (code == 'DUPLICATE_REPORT') {
        msg = 'You already reported this recently.';
      } else if (code == 'SELF_REPORT') {
        msg = "You can't report yourself.";
      } else if (code == 'TARGET_NOT_FOUND') {
        msg = 'That user or content no longer exists.';
      } else {
        msg = e.response?.statusMessage ?? 'Could not submit — please retry.';
      }
      if (mounted) {
        setState(() {
          _errorMsg = msg;
          _submitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = 'Could not submit — please retry.';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 40),
      padding: EdgeInsets.fromLTRB(
          24, 14, 24, MediaQuery.of(context).viewInsets.bottom + 24),
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
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: t.rail, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            if (_submitted) ...[
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: NeedHubTokens.forest.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: NeedHubTokens.forest, size: 32),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.alsoBlock
                          ? 'Reported and blocked'
                          : 'Report submitted',
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.alsoBlock
                          ? '${widget.targetName} has been blocked and our team will review your report shortly.'
                          : 'Thanks — our trust & safety team will review your report shortly.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 14, color: t.muted, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NeedHubTokens.forest,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Done',
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                widget.alsoBlock
                    ? 'Report and block ${widget.targetName}'
                    : 'Report ${widget.targetName}',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: t.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tell us what happened. Reports are anonymous and reviewed by our team.',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 13.5, color: t.muted, height: 1.4),
              ),
              const SizedBox(height: 18),
              Text(
                'REASON',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: t.muted2,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 10),
              ..._reasons.map((r) {
                final selected = _selected == r;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selected = r),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: selected ? Colors.red.shade50 : t.paper,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? Colors.red.shade300 : t.rail,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            size: 20,
                            color:
                                selected ? Colors.red.shade400 : t.muted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              r,
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: selected ? t.ink : t.muted2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 14),
              Text(
                'DETAILS (REQUIRED, MIN 10 CHARS)',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: t.muted2,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: t.paper,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.rail, width: 1.5),
                ),
                child: TextField(
                  controller: _detailsController,
                  minLines: 3,
                  maxLines: 6,
                  onChanged: (_) => setState(() {}),
                  style:
                      GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
                  decoration: InputDecoration(
                    hintText:
                        'Please describe what happened so our team can investigate…',
                    hintStyle: GoogleFonts.hankenGrotesk(
                        fontSize: 14, color: t.muted),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(14),
                    filled: false,
                  ),
                ),
              ),
              if (_errorMsg != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: Colors.red.shade400, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMsg!,
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 13,
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (_canSubmit && !_submitting) ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade400,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: t.rail,
                    disabledForegroundColor: t.muted,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          widget.alsoBlock
                              ? 'Submit and block'
                              : 'Submit report',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
