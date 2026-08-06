import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../l10n/app_strings.dart';
import '../../services/profiles_api.dart';
import '../../services/social_providers.dart';
import '../../theme/tokens.dart';

class IdVerifyScreen extends ConsumerStatefulWidget {
  const IdVerifyScreen({super.key});

  @override
  ConsumerState<IdVerifyScreen> createState() => _IdVerifyScreenState();
}

class _IdVerifyScreenState extends ConsumerState<IdVerifyScreen> {
  // Step 0 = intro, 1 = pick ID, 2 = take selfie, 3 = verifying, 4 = done/error
  int _step = 0;
  File? _idPhoto;
  File? _selfie;
  bool _verifying = false;
  String? _errorReason;
  String? _errorCode;

  final _picker = ImagePicker();

  Future<void> _pickIdPhoto() async {
    final xf = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (xf == null) return;
    setState(() {
      _idPhoto = File(xf.path);
      _step = 2;
    });
  }

  Future<void> _takeSelfie() async {
    final xf = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 85,
      maxWidth: 1280,
      maxHeight: 1280,
    );
    if (xf == null) return;
    setState(() {
      _selfie = File(xf.path);
    });
    await _submit();
  }

  Future<void> _submit() async {
    if (_idPhoto == null || _selfie == null) return;
    setState(() {
      _verifying = true;
      _errorReason = null;
      _errorCode = null;
      _step = 3;
    });
    try {
      await ref.read(profilesApiProvider).verifyId(
        idPhotoPath: _idPhoto!.path,
        selfiePath: _selfie!.path,
      );
      // Refresh profile so badge + trust score update immediately
      final updated = await ref.read(profilesApiProvider).me();
      myProfileNotifier.value = updated;
      if (mounted) setState(() => _step = 4);
    } on DioException catch (e) {
      final body = e.response?.data;
      final reason = body is Map ? body['reason'] as String? : null;
      final code = body is Map ? body['code'] as String? : null;
      if (mounted) {
        setState(() {
          _verifying = false;
          _errorReason = reason ?? 'Verification failed. Please try again.';
          _errorCode = code;
          // Go back to appropriate step based on error
          _step = (code == 'NO_FACE_ON_ID' || code == 'FACE_MISMATCH')
              ? 1  // retake ID
              : 2; // retake selfie
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _verifying = false;
          _errorReason = 'Something went wrong. Please try again.';
          _step = 1;
        });
      }
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
        title: Text(
          'ID Verification',
          style: GoogleFonts.bricolageGrotesque(fontSize: 18, fontWeight: FontWeight.w700, color: t.ink),
        ),
      ),
      body: SafeArea(
        child: _buildStep(t),
      ),
    );
  }

  Widget _buildStep(NeedHubTokens t) {
    return switch (_step) {
      0 => _IntroStep(t: t, onStart: () => setState(() => _step = 1)),
      1 => _IdPhotoStep(t: t, onPick: _pickIdPhoto, error: _errorCode == 'NO_FACE_ON_ID' || _errorCode == 'FACE_MISMATCH' ? _errorReason : null),
      2 => _SelfieStep(t: t, idPhoto: _idPhoto!, onTakeSelfie: _takeSelfie, error: _errorReason != null && _errorCode != 'NO_FACE_ON_ID' && _errorCode != 'FACE_MISMATCH' ? _errorReason : null),
      3 => _VerifyingStep(t: t),
      4 => _SuccessStep(t: t, onDone: () => Navigator.of(context).pop(true)),
      _ => const SizedBox.shrink(),
    };
  }
}

// ── Step 0: Intro ─────────────────────────────────────────────────────────────

class _IntroStep extends StatelessWidget {
  final NeedHubTokens t;
  final VoidCallback onStart;
  const _IntroStep({required this.t, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: NeedHubTokens.forest.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.verified_user_rounded, color: NeedHubTokens.forest, size: 28),
          ),
          const SizedBox(height: 20),
          Text('Verify your identity',
              style: GoogleFonts.bricolageGrotesque(fontSize: 22, fontWeight: FontWeight.w800, color: t.ink)),
          const SizedBox(height: 10),
          Text(
            'Upload a government ID (Aadhaar, PAN, or driving licence) and take a live selfie. Our system checks that the face on the ID matches you — in seconds, fully automated.',
            style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted, height: 1.6),
          ),
          const SizedBox(height: 24),
          _BulletPoint(t: t, icon: Icons.shield_rounded, color: NeedHubTokens.forest,
              text: 'Your ID is never stored — images are checked and immediately discarded.'),
          const SizedBox(height: 12),
          _BulletPoint(t: t, icon: Icons.lock_rounded, color: NeedHubTokens.ochre,
              text: 'Only the verification result is saved — not the photo.'),
          const SizedBox(height: 12),
          _BulletPoint(t: t, icon: Icons.badge_rounded, color: NeedHubTokens.clay,
              text: 'Earn the ID Verified badge and the highest trust score boost on NeedHub.'),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onStart,
              style: ElevatedButton.styleFrom(
                backgroundColor: NeedHubTokens.forest,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Text('Start Verification',
                  style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final NeedHubTokens t;
  final IconData icon;
  final Color color;
  final String text;
  const _BulletPoint({required this.t, required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.muted, height: 1.5))),
      ],
    );
  }
}

// ── Step 1: ID Photo ──────────────────────────────────────────────────────────

class _IdPhotoStep extends StatelessWidget {
  final NeedHubTokens t;
  final VoidCallback onPick;
  final String? error;
  const _IdPhotoStep({required this.t, required this.onPick, this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepIndicator(t: t, step: 1, total: 2, label: 'Government ID'),
          const SizedBox(height: 24),
          Text('Upload your ID',
              style: GoogleFonts.bricolageGrotesque(fontSize: 20, fontWeight: FontWeight.w800, color: t.ink)),
          const SizedBox(height: 8),
          Text('Take a clear photo of your Aadhaar card, PAN card, or driving licence.',
              style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted, height: 1.5)),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: onPick,
            child: Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: error != null ? NeedHubTokens.clay : t.rail,
                  width: error != null ? 1.5 : 1,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_rounded, size: 36, color: t.muted2),
                  const SizedBox(height: 10),
                  Text('Tap to upload ID photo',
                      style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w600, color: t.muted2)),
                  const SizedBox(height: 4),
                  Text('From your gallery', style: GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted)),
                ],
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            _ErrorBox(t: t, message: error!),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: t.chip, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.tips_and_updates_rounded, size: 16, color: t.muted2),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Make sure all text on the ID is clearly readable. Avoid glare and shadows.',
                style: GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted2, height: 1.4),
              )),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── Step 2: Selfie ────────────────────────────────────────────────────────────

class _SelfieStep extends StatelessWidget {
  final NeedHubTokens t;
  final File idPhoto;
  final VoidCallback onTakeSelfie;
  final String? error;
  const _SelfieStep({required this.t, required this.idPhoto, required this.onTakeSelfie, this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepIndicator(t: t, step: 2, total: 2, label: 'Live Selfie'),
          const SizedBox(height: 16),
          Row(children: [
            Container(
              width: 60, height: 40,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              clipBehavior: Clip.hardEdge,
              child: Image.file(idPhoto, fit: BoxFit.cover),
            ),
            const SizedBox(width: 10),
            Icon(Icons.check_circle_rounded, color: NeedHubTokens.forest, size: 18),
            const SizedBox(width: 6),
            Text('ID uploaded', style: GoogleFonts.hankenGrotesk(fontSize: 13, color: NeedHubTokens.forest, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 20),
          Text('Now take a selfie',
              style: GoogleFonts.bricolageGrotesque(fontSize: 20, fontWeight: FontWeight.w800, color: t.ink)),
          const SizedBox(height: 8),
          Text('Use your front camera. Your face must be clearly visible and your eyes open.',
              style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted, height: 1.5)),
          const SizedBox(height: 32),
          if (error != null) ...[
            _ErrorBox(t: t, message: error!),
            const SizedBox(height: 20),
          ],
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: NeedHubTokens.ochre.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NeedHubTokens.ochre.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LIVENESS CHECK', style: GoogleFonts.hankenGrotesk(fontSize: 10, fontWeight: FontWeight.w700, color: NeedHubTokens.ochre, letterSpacing: 0.8)),
                const SizedBox(height: 8),
                Text('Our system checks that you\'re a real person — not a photo or screen. Keep your eyes open and hold the camera naturally.',
                    style: GoogleFonts.hankenGrotesk(fontSize: 13, color: t.ink, height: 1.5)),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onTakeSelfie,
              icon: const Icon(Icons.camera_front_rounded, size: 20),
              label: Text('Take Selfie',
                  style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: NeedHubTokens.forest,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 3: Verifying ─────────────────────────────────────────────────────────

class _VerifyingStep extends StatelessWidget {
  final NeedHubTokens t;
  const _VerifyingStep({required this.t});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 56, height: 56,
              child: CircularProgressIndicator(strokeWidth: 3, color: NeedHubTokens.forest),
            ),
            const SizedBox(height: 28),
            Text('Verifying…',
                style: GoogleFonts.bricolageGrotesque(fontSize: 20, fontWeight: FontWeight.w800, color: t.ink)),
            const SizedBox(height: 8),
            Text('Checking liveness and matching your face to the ID.\nThis takes about 3 seconds.',
                textAlign: TextAlign.center,
                style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

// ── Step 4: Success ───────────────────────────────────────────────────────────

class _SuccessStep extends StatelessWidget {
  final NeedHubTokens t;
  final VoidCallback onDone;
  const _SuccessStep({required this.t, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: NeedHubTokens.forest.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_rounded, size: 44, color: NeedHubTokens.forest),
          ),
          const SizedBox(height: 24),
          Text('ID Verified!',
              style: GoogleFonts.bricolageGrotesque(fontSize: 26, fontWeight: FontWeight.w800, color: t.ink)),
          const SizedBox(height: 10),
          Text(
            'Your government ID matches your selfie. Your profile now shows the ID Verified badge and your trust score has been updated.',
            textAlign: TextAlign.center,
            style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted, height: 1.6),
          ),
          const SizedBox(height: 36),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onDone,
              style: ElevatedButton.styleFrom(
                backgroundColor: NeedHubTokens.forest,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Text(S.current.done,
                  style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final NeedHubTokens t;
  final int step;
  final int total;
  final String label;
  const _StepIndicator({required this.t, required this.step, required this.total, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text('Step $step of $total',
          style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: t.muted2, letterSpacing: 0.5)),
      const SizedBox(width: 8),
      Expanded(child: LinearProgressIndicator(
        value: step / total,
        backgroundColor: t.rail,
        color: NeedHubTokens.forest,
        borderRadius: BorderRadius.circular(4),
        minHeight: 4,
      )),
    ]);
  }
}

class _ErrorBox extends StatelessWidget {
  final NeedHubTokens t;
  final String message;
  const _ErrorBox({required this.t, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NeedHubTokens.clay.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NeedHubTokens.clay.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: NeedHubTokens.clay),
          const SizedBox(width: 8),
          Expanded(child: Text(message,
              style: GoogleFonts.hankenGrotesk(fontSize: 13, color: NeedHubTokens.clay, height: 1.4))),
        ],
      ),
    );
  }
}
