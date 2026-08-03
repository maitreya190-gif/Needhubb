import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_strings.dart';
import '../../services/plus_api.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';

/// The claim form is rendered ENTIRELY from offer.payoutFields — nothing
/// here is hardcoded to "cashback" or "UPI". Adding a ₹200 Amazon gift card
/// reward later needs zero changes to this screen: an admin creates a new
/// RewardOffer row with kind=GIFT_CARD and a different payoutFields list
/// (e.g. an email field instead of a UPI id), and this form adapts.
class PlusRewardClaimScreen extends ConsumerStatefulWidget {
  final PlusRewardOffer offer;

  const PlusRewardClaimScreen({super.key, required this.offer});

  @override
  ConsumerState<PlusRewardClaimScreen> createState() => _PlusRewardClaimScreenState();
}

class _PlusRewardClaimScreenState extends ConsumerState<PlusRewardClaimScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final field in widget.offer.payoutFields) {
      _controllers[field.key] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate(PlusPayoutField field, String? value) {
    final v = value?.trim() ?? '';
    if (field.required && v.isEmpty) return '${field.label} is required';
    if (v.isNotEmpty && field.type == 'upi' && !RegExp(r'^[\w.-]{2,256}@[a-zA-Z]{2,64}$').hasMatch(v)) {
      return "Doesn't look like a valid UPI ID";
    }
    if (v.isNotEmpty && field.type == 'email' && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)) {
      return "Doesn't look like a valid email";
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final details = {for (final e in _controllers.entries) e.key: e.value.text.trim()};
    try {
      await ref.read(plusApiProvider).claimReward(widget.offer.key, details);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: context.tokens.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(S.current.claimSubmitted, style: GoogleFonts.bricolageGrotesque(fontSize: 17, fontWeight: FontWeight.w800)),
          content: Text(
            S.current.claimSubmittedDesc(widget.offer.title),
            style: GoogleFonts.hankenGrotesk(fontSize: 13.5, color: context.tokens.muted, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: NeedHubTokens.forest, foregroundColor: Colors.white),
              child: Text(S.current.gotIt),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      String message = S.current.couldNotSubmitClaim;
      if (e is DioException) {
        final code = (e.response?.data as Map?)?['code'] as String?;
        switch (code) {
          case 'ALREADY_CLAIMED':
            message = "You've already claimed this reward.";
            break;
          case 'REWARD_EXHAUSTED':
            message = S.current.rewardExhausted;
            break;
          case 'BELOW_VERIFIED_POINTS':
            message = S.current.belowVerifiedPoints;
            break;
          case 'INSUFFICIENT_BALANCE':
            message = S.current.insufficientBalance;
            break;
          default:
            final msg = (e.response?.data as Map?)?['error'] as String?;
            if (msg != null) message = msg;
        }
      }
      setState(() {
        _error = message;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final offer = widget.offer;

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
        title: Text(S.current.claimReward, style: GoogleFonts.bricolageGrotesque(fontSize: 18, fontWeight: FontWeight.w700, color: t.ink)),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: NeedHubTokens.forest.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: NeedHubTokens.forest.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(offer.title, style: GoogleFonts.bricolageGrotesque(fontSize: 17, fontWeight: FontWeight.w800, color: t.ink)),
                    const SizedBox(height: 6),
                    Text(offer.description, style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted, height: 1.4)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(S.current.rewardValue, style: GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted)),
                        Text('₹${offer.rewardValueRupees.toStringAsFixed(0)}',
                            style: GoogleFonts.bricolageGrotesque(fontSize: 15, fontWeight: FontWeight.w700, color: NeedHubTokens.forest)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(S.current.costs, style: GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted)),
                        Row(
                          children: [
                            const Icon(Icons.stars_rounded, size: 14, color: NeedHubTokens.ochre),
                            const SizedBox(width: 3),
                            Text('${offer.pointsCost} pts',
                                style: GoogleFonts.bricolageGrotesque(fontSize: 15, fontWeight: FontWeight.w700, color: NeedHubTokens.ochre)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (offer.payoutFields.isNotEmpty) ...[
                Text(S.current.whereSendIt.toUpperCase(),
                    style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: t.muted2, letterSpacing: 0.7)),
                const SizedBox(height: 12),
                ...offer.payoutFields.map((field) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextFormField(
                        controller: _controllers[field.key],
                        keyboardType: field.type == 'email' ? TextInputType.emailAddress : TextInputType.text,
                        style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.ink),
                        decoration: InputDecoration(
                          labelText: field.label + (field.required ? ' *' : ''),
                          filled: true,
                          fillColor: t.card,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.rail)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.rail)),
                        ),
                        validator: (v) => _validate(field, v),
                      ),
                    )),
              ],
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: NeedHubTokens.clay.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                  child: Text(_error!, style: GoogleFonts.hankenGrotesk(fontSize: 12.5, color: NeedHubTokens.clay)),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NeedHubTokens.forest,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: t.rail,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(S.current.submitClaimPts(offer.pointsCost), style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
