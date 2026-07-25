import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/tokens.dart';

class AdminConfirmDialog extends StatelessWidget {
  final String title;
  final String body;
  final String confirmLabel;

  const AdminConfirmDialog({
    super.key,
    required this.title,
    required this.body,
    this.confirmLabel = 'Remove',
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      backgroundColor: t.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        title,
        style: GoogleFonts.bricolageGrotesque(
            fontSize: 18, fontWeight: FontWeight.w700, color: t.ink),
      ),
      content: Text(
        body,
        style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel',
              style: GoogleFonts.hankenGrotesk(color: t.muted2)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: NeedHubTokens.clay,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(
            confirmLabel,
            style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class AdminErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const AdminErrorView(
      {super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, color: t.muted, size: 40),
            const SizedBox(height: 12),
            Text(
              'Could not connect to API',
              style: GoogleFonts.bricolageGrotesque(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: t.ink),
            ),
            const SizedBox(height: 4),
            Text(
              error,
              style:
                  GoogleFonts.hankenGrotesk(fontSize: 12, color: t.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminEmptyView extends StatelessWidget {
  final String message;

  const AdminEmptyView({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Text(
        message,
        style: GoogleFonts.hankenGrotesk(fontSize: 14, color: t.muted),
      ),
    );
  }
}

class AdminMiniChip extends StatelessWidget {
  final String label;

  const AdminMiniChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: t.chip,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.hankenGrotesk(
            fontSize: 11, fontWeight: FontWeight.w600, color: t.muted2),
      ),
    );
  }
}
