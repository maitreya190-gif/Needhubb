import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/tokens.dart';

class NhPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const NhPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: t.surfaceDark,
          foregroundColor: t.onDark,
          disabledBackgroundColor: t.surfaceDark.withValues(alpha: 0.5),
          disabledForegroundColor: t.onDarkMuted,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.onDarkMuted,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  color: t.onDark,
                ),
              ),
      ),
    );
  }
}

class NhOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const NhOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: t.ink,
          side: BorderSide(color: t.rail, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.muted,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
      ),
    );
  }
}
