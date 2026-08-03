import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_strings.dart';
import '../../services/plus_api.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';

/// Real UPI redirect + trust-but-flag confirmation flow.
///
/// There is no payment gateway wired into this app — no merchant account,
/// no credentials to verify a bank transfer server-side. What IS real: a
/// `upi://pay` deep link (built server-side in lib/payments/manual.ts) that
/// genuinely opens the "complete with PhonePe / Paytm / GPay" chooser on
/// Android against the configured collection VPA. When the user returns to
/// the app, we ask them directly whether it went through — per the explicit
/// product decision, "Yes" activates Plus immediately (the payment row is
/// flagged `selfReported` for admin audit, revocable later), "Not sure yet"
/// falls back to polling for up to 5 minutes in case an admin confirms it
/// manually in the meantime.
class PlusPaymentScreen extends ConsumerStatefulWidget {
  const PlusPaymentScreen({super.key});

  @override
  ConsumerState<PlusPaymentScreen> createState() => _PlusPaymentScreenState();
}

enum _Stage { loading, ready, launching, waiting, success, error }

class _PlusPaymentScreenState extends ConsumerState<PlusPaymentScreen> with WidgetsBindingObserver {
  _Stage _stage = _Stage.loading;
  PlusPaymentIntent? _intent;
  String? _error;
  bool _awaitingReturn = false;
  Timer? _pollTimer;
  int _pollsRemaining = 0;
  static const int _maxPolls = 20; // 20 * 15s = 5 minutes

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _createIntent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingReturn) {
      _awaitingReturn = false;
      // Let the frame settle before showing a dialog on top of the resume.
      WidgetsBinding.instance.addPostFrameCallback((_) => _askDidItSucceed());
    }
  }

  Future<void> _createIntent() async {
    setState(() {
      _stage = _Stage.loading;
      _error = null;
    });
    try {
      final intent = await ref.read(plusApiProvider).subscribe();
      if (!mounted) return;
      setState(() {
        _intent = intent;
        _stage = _Stage.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = S.current.couldNotStartCheckout;
        _stage = _Stage.error;
      });
    }
  }

  Future<void> _launchUpi() async {
    final intent = _intent;
    if (intent?.upiDeepLink == null) return;
    setState(() => _stage = _Stage.launching);
    try {
      final uri = Uri.parse(intent!.upiDeepLink!);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        if (mounted) {
          setState(() => _stage = _Stage.ready);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.current.noUpiAppFound)),
          );
        }
        return;
      }
      _awaitingReturn = true;
    } catch (_) {
      if (mounted) {
        setState(() => _stage = _Stage.ready);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.current.couldNotOpenUpi)),
        );
      }
    }
  }

  Future<void> _askDidItSucceed() async {
    if (!mounted || _intent == null) return;
    final t = context.tokens;
    final answer = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: t.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(S.current.didPaymentGoThrough,
            style: GoogleFonts.bricolageGrotesque(fontSize: 17, fontWeight: FontWeight.w800, color: t.ink)),
        content: Text(
          S.current.letUsKnowUpi,
          style: GoogleFonts.hankenGrotesk(fontSize: 13.5, color: t.muted),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'no'),
            child: Text(S.current.noTryAgain, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600, color: t.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'unsure'),
            child: Text(S.current.notSureYet, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600, color: NeedHubTokens.ochre)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'yes'),
            style: ElevatedButton.styleFrom(
              backgroundColor: NeedHubTokens.forest,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(S.current.yesPaid, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (answer == 'yes') {
      await _confirm(selfReportedSuccess: true);
    } else if (answer == 'unsure') {
      await _confirm(selfReportedSuccess: false);
    }
    // 'no' or dismissed: stay on the ready stage, let them retry.
  }

  Future<void> _confirm({required bool selfReportedSuccess}) async {
    final intent = _intent;
    if (intent == null) return;
    setState(() => _stage = _Stage.launching);
    try {
      final result = await ref.read(plusApiProvider).confirmPayment(
            intent.paymentId,
            selfReportedSuccess: selfReportedSuccess,
          );
      if (!mounted) return;
      if (result.activated) {
        setState(() => _stage = _Stage.success);
      } else {
        _startWaiting();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _stage = _Stage.ready);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.current.couldNotConfirmPayment)),
      );
    }
  }

  void _startWaiting() {
    setState(() {
      _stage = _Stage.waiting;
      _pollsRemaining = _maxPolls;
    });
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted) return;
      try {
        final status = await ref.read(plusApiProvider).status();
        if (!mounted) return;
        if (status.active) {
          _pollTimer?.cancel();
          setState(() => _stage = _Stage.success);
          return;
        }
      } catch (_) {/* keep polling */}
      setState(() => _pollsRemaining -= 1);
      if (_pollsRemaining <= 0) {
        _pollTimer?.cancel();
      }
    });
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
          onPressed: () => Navigator.of(context).pop(_stage == _Stage.success),
        ),
        title: Text(S.current.subscribePlus,
            style: GoogleFonts.bricolageGrotesque(fontSize: 18, fontWeight: FontWeight.w700, color: t.ink)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildBody(t),
        ),
      ),
    );
  }

  Widget _buildBody(NeedHubTokens t) {
    switch (_stage) {
      case _Stage.loading:
      case _Stage.launching:
        return const Center(child: CircularProgressIndicator());

      case _Stage.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 40, color: NeedHubTokens.clay),
              const SizedBox(height: 12),
              Text(_error ?? S.current.somethingWentWrong, style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _createIntent, child: Text(S.current.retry)),
            ],
          ),
        );

      case _Stage.waiting:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: NeedHubTokens.ochre),
              const SizedBox(height: 20),
              Text(S.current.waitingForConfirmation,
                  style: GoogleFonts.bricolageGrotesque(fontSize: 17, fontWeight: FontWeight.w800, color: t.ink)),
              const SizedBox(height: 8),
              Text(
                S.current.willActivatePlusWhen,
                style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(S.current.cancel),
              ),
            ],
          ),
        );

      case _Stage.success:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(color: NeedHubTokens.forest, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 20),
              Text(S.current.nowOnNeedHubPlus,
                  style: GoogleFonts.bricolageGrotesque(fontSize: 19, fontWeight: FontWeight.w800, color: t.ink)),
              const SizedBox(height: 8),
              Text(S.current.visibilityBoostActive,
                  style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted, height: 1.4), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NeedHubTokens.forest,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(S.current.done),
              ),
            ],
          ),
        );

      case _Stage.ready:
        final intent = _intent!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: t.rail, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.current.paymentAmount, style: GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted)),
                  const SizedBox(height: 4),
                  Text('₹${(intent.amountPaise / 100).toStringAsFixed(2)}',
                      style: GoogleFonts.bricolageGrotesque(fontSize: 28, fontWeight: FontWeight.w800, color: t.ink)),
                  const SizedBox(height: 12),
                  if (intent.instructions != null)
                    Text(intent.instructions!, style: GoogleFonts.hankenGrotesk(fontSize: 12.5, color: t.muted, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: intent.upiDeepLink != null ? _launchUpi : null,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: Text(S.current.payWithUpi,
                  style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: NeedHubTokens.ochre,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              S.current.youllBeAskedToConfirm,
              style: GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted3),
              textAlign: TextAlign.center,
            ),
          ],
        );
    }
  }
}
